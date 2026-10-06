# Shared vmrun helpers for the tools/vm host scripts.
# Passwords come from the environment, never from source:
#   KUTAY_VM_PASS    - VMware encryption password of the VM (vTPM)
#   KUTAY_GUEST_PASS - password of the guest user

$script:Vmrun = Join-Path $env:ProgramFiles 'VMware\VMware Workstation\vmrun.exe'
$script:GuestDir = 'C:\Users\Public'
$script:GuestPowerShell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'

function Get-DefaultVmx {
    Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Virtual Machines\KutayOS-Test\KutayOS-Test.vmx'
}

function Get-VmAuth([string]$GuestUser = 'PC') {
    if (-not $env:KUTAY_VM_PASS -or -not $env:KUTAY_GUEST_PASS) {
        throw 'Set KUTAY_VM_PASS (VM encryption) and KUTAY_GUEST_PASS (guest user) first.'
    }
    @('-T', 'ws', '-vp', $env:KUTAY_VM_PASS, '-gu', $GuestUser, '-gp', $env:KUTAY_GUEST_PASS)
}

function Invoke-Vmrun {
    & $script:Vmrun @(Get-VmAuth) @args
    if ($LASTEXITCODE -ne 0) { throw "vmrun $($args[0]) failed ($LASTEXITCODE)" }
}

function Get-VmToolsState([string]$Vmx) {
    & $script:Vmrun -T ws -vp $env:KUTAY_VM_PASS checkToolsState $Vmx
}

function Test-GuestDesktop([string]$Vmx) {
    $procs = & $script:Vmrun @(Get-VmAuth) listProcessesInGuest $Vmx 2>$null
    [bool]($procs -match 'explorer\.exe')
}

<#
Copies a script into the guest, runs it with Windows PowerShell and copies one result file back.
The call goes through cmd.exe so the output can be redirected. vmrun appends a blank argument to
the command line, so guest scripts must accept extra arguments (ValueFromRemainingArguments).
#>
function Invoke-GuestScript {
    param(
        [Parameter(Mandatory)][string]$Vmx,
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string]$GuestResult,
        [Parameter(Mandatory)][string]$LocalResult,
        [string]$ScriptArgs = '',
        [string]$StdoutFile = ''
    )
    $guestScript = Join-Path -Path $script:GuestDir -ChildPath (Split-Path -Path $ScriptPath -Leaf)
    Invoke-Vmrun CopyFileFromHostToGuest $Vmx $ScriptPath $guestScript
    # A result left by an earlier run must not be copied back if this run fails to write one.
    $exists = & $script:Vmrun @(Get-VmAuth) fileExistsInGuest $Vmx $GuestResult
    if ($exists -match 'The file exists') { Invoke-Vmrun deleteFileInGuest $Vmx $GuestResult }
    $redirect = ''
    if ($StdoutFile) { $redirect = " > $StdoutFile 2>&1" }
    $cmd = "/c $script:GuestPowerShell -NoProfile -ExecutionPolicy Bypass -File $guestScript $ScriptArgs$redirect"
    Invoke-Vmrun runProgramInGuest $Vmx 'C:\Windows\System32\cmd.exe' $cmd
    Invoke-Vmrun CopyFileFromGuestToHost $Vmx $GuestResult $LocalResult
}

# Copies a file or a whole folder from the host into the guest. vmrun doesn't create a missing
# parent folder ("A file was not found"), so create it first.
function Copy-ItemToGuest([string]$Vmx, [string]$Source, [string]$Destination) {
    $parent = Split-Path -Path $Destination -Parent
    $exists = & $script:Vmrun @(Get-VmAuth) directoryExistsInGuest $Vmx $parent
    if ($exists -match 'does not exist') { Invoke-Vmrun createDirectoryInGuest $Vmx $parent }
    Invoke-Vmrun CopyFileFromHostToGuest $Vmx $Source $Destination
}

# Reverts to a powered-off snapshot and boots the VM. vmrun starts it without the GUI: a GUI start
# can block vmrun on the Workstation window asking for the encryption password. But without a
# display attached the guest stalls before VMware Tools starts, so the Workstation window is then
# opened on the running VM (no password prompt, it is already unlocked).
# A revert brings back the snapshot's VMX, so the overrides are written after it, every boot.
# -MemoryMB / -CpuCount set the hardware for this boot (0 keeps the snapshot's). uuid.action keep:
# the VM was copied to a new host, and without it every revert asks "moved or copied?", which nogui
# answers "copied" with a new BIOS UUID and MAC (new network profile in the guest, measurement noise).
# The install ISO is gone, so the CD-ROM starts disconnected. These keys are plain text in the
# encrypted VMX.
function Set-VmxValue([string]$Vmx, [System.Collections.IDictionary]$Values) {
    $text = [IO.File]::ReadAllText($Vmx)
    $newline = "`n"
    if ($text.Contains("`r`n")) { $newline = "`r`n" }
    foreach ($key in $Values.Keys) {
        $line = "$key = `"$($Values[$key])`""
        # Whole key, any case, any spacing; the line's own \r stays in place.
        $pattern = '(?im)^' + [regex]::Escape($key) + '\s*=.*?(?=\r?$)'
        $count = [regex]::Matches($text, $pattern).Count
        if ($count -gt 1) { throw "$Vmx has $key $count times" }
        if ($count -eq 1) { $text = [regex]::Replace($text, $pattern, $line.Replace('$', '$$')) }
        else { $text = $text.TrimEnd() + $newline + $line + $newline }
    }
    # Write next to it and swap, so a crash mid-write can't leave a half-written VMX.
    $temp = "$Vmx.kutay-tmp"
    [IO.File]::WriteAllText($temp, $text)
    Move-Item -LiteralPath $temp -Destination $Vmx -Force
}

function Invoke-TestVmReset([string]$Vmx, [string]$Snapshot, [int]$MemoryMB = 0, [int]$CpuCount = 0) {
    & $script:Vmrun -T ws -vp $env:KUTAY_VM_PASS revertToSnapshot $Vmx $Snapshot
    if ($LASTEXITCODE -ne 0) { throw "vmrun revertToSnapshot $Snapshot failed ($LASTEXITCODE)" }
    $values = [ordered]@{ 'uuid.action' = 'keep'; 'sata0:1.startConnected' = 'FALSE' }
    if ($MemoryMB -gt 0) { $values['memsize'] = $MemoryMB }
    if ($CpuCount -gt 0) { $values['numvcpus'] = $CpuCount; $values['cpuid.coresPerSocket'] = $CpuCount }
    Set-VmxValue -Vmx $Vmx -Values $values
    & $script:Vmrun -T ws -vp $env:KUTAY_VM_PASS start $Vmx nogui
    if ($LASTEXITCODE -ne 0) { throw "vmrun start failed ($LASTEXITCODE)" }
    $workstation = Join-Path (Split-Path -Path $script:Vmrun -Parent) 'vmware.exe'
    Start-Process -FilePath $workstation -ArgumentList "`"$Vmx`""
    # The window asks for the encryption password even when Credential Manager has it; until it is
    # unlocked the guest has no display and Tools does not start.
    $unlocked = (& (Join-Path $PSScriptRoot 'Unlock-VmWindow.ps1')) -eq $true
    if (-not $unlocked) { Write-Warning 'No VMware password pane found; the VM window may still be locked' }
}

# Shuts the guest down cleanly and saves the powered-off VM as a snapshot. An existing snapshot with
# that name is replaced, so the measurement scripts always find exactly one.
function Save-TestVmSnapshot([string]$Vmx, [string]$Snapshot) {
    & $script:Vmrun -T ws -vp $env:KUTAY_VM_PASS stop $Vmx soft
    if ($LASTEXITCODE -ne 0) { throw "vmrun stop failed ($LASTEXITCODE)" }
    $existing = & $script:Vmrun -T ws -vp $env:KUTAY_VM_PASS listSnapshots $Vmx
    if ($LASTEXITCODE -ne 0) { throw "vmrun listSnapshots failed ($LASTEXITCODE)" }
    if (@($existing | Select-Object -Skip 1) -contains $Snapshot) {
        & $script:Vmrun -T ws -vp $env:KUTAY_VM_PASS deleteSnapshot $Vmx $Snapshot
        if ($LASTEXITCODE -ne 0) { throw "vmrun deleteSnapshot $Snapshot failed ($LASTEXITCODE)" }
    }
    & $script:Vmrun -T ws -vp $env:KUTAY_VM_PASS snapshot $Vmx $Snapshot
    if ($LASTEXITCODE -ne 0) { throw "vmrun snapshot $Snapshot failed ($LASTEXITCODE)" }
}

Export-ModuleMember -Function Get-DefaultVmx, Get-VmToolsState, Test-GuestDesktop, Invoke-GuestScript,
    Copy-ItemToGuest, Invoke-TestVmReset, Save-TestVmSnapshot, Set-VmxValue
