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
function Invoke-TestVmReset([string]$Vmx, [string]$Snapshot) {
    & $script:Vmrun -T ws -vp $env:KUTAY_VM_PASS revertToSnapshot $Vmx $Snapshot
    if ($LASTEXITCODE -ne 0) { throw "vmrun revertToSnapshot $Snapshot failed ($LASTEXITCODE)" }
    & $script:Vmrun -T ws -vp $env:KUTAY_VM_PASS start $Vmx nogui
    if ($LASTEXITCODE -ne 0) { throw "vmrun start failed ($LASTEXITCODE)" }
    $workstation = Join-Path (Split-Path -Path $script:Vmrun -Parent) 'vmware.exe'
    Start-Process -FilePath $workstation -ArgumentList "`"$Vmx`""
}

Export-ModuleMember -Function Get-DefaultVmx, Get-VmToolsState, Test-GuestDesktop, Invoke-GuestScript,
    Copy-ItemToGuest, Invoke-TestVmReset
