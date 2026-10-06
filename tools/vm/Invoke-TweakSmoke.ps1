<#
.SYNOPSIS
    Smoke-tests every tweak the playbook runs, in the test VM: apply twice, check, revert, check.
.DESCRIPTION
    Reverts the VM to a snapshot and boots it, copies src\playbook\Executables and a manifest built
    from custom.yml into the guest, runs guest-smoke-tweaks.ps1 there and prints its PASS/FAIL lines.
    The restore point step is skipped (covered in Slice 1); the full AME run is a separate test.
    Needs KUTAY_VM_PASS and KUTAY_GUEST_PASS (see VmGuest.psm1). Exit code 1 if any check fails.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/vm/Invoke-TweakSmoke.ps1
#>
[CmdletBinding()]
param(
    [string]$Snapshot = 'clean-9550-scanned',
    [string]$Vmx = '',
    [string]$OutFile = '',
    # Hardware for this boot (0 keeps the snapshot's): 8 GB / 4 vCPU on the desktop host (Ryzen 5 9600X, 32 GB).
    [int]$MemoryMB = 8192,
    [int]$CpuCount = 4,
    # Use the VM as it runs now; only when it was just reverted to the snapshot and nothing ran since.
    [switch]$NoReset,
    # Apply the default tweaks once (no revert, no FeaturePages options), shut the VM down and save it
    # as this snapshot, for performance measurements of the applied playbook.
    [string]$SaveAppliedAs = '',
    # With -SaveAppliedAs: apply nothing, only let the VM run as long as applying takes and save it.
    # The control for the applied snapshot: both have booted once after the revert and shut down.
    [switch]$Control,
    [int]$ControlMinutes = 10
)

$ErrorActionPreference = 'Stop'
$pollSeconds = 5
$maxPolls = 180
$guestRoot = 'C:\Users\Public\KutaySmoke'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$playbook = Join-Path $repo 'src\playbook'
Import-Module (Join-Path $PSScriptRoot 'VmGuest.psm1') -Force
Import-Module (Join-Path $repo 'tools\KutayTweak.psm1') -Force

function Wait-Until([scriptblock]$Condition, [string]$What) {
    for ($i = 0; $i -lt $maxPolls; $i++) {
        if (& $Condition) { return }
        Start-Sleep -Seconds $pollSeconds
    }
    throw "Timed out waiting for $What"
}

function Write-SmokeManifest([string]$Path) {
    $config = Join-Path $playbook 'Configuration'
    $tweaks = @(Get-KutayTaskPath -Path (Join-Path $config 'custom.yml') | ForEach-Object {
            $file = Join-Path $config $_
            [ordered]@{
                id          = [IO.Path]::GetFileNameWithoutExtension($file)
                commands    = @(Get-KutayTweakCommand -Path $file)
                changes     = @(Get-KutayTweakChange -Path $file)
                userChanges = @(Get-KutayTweakUserChange -Path $file)
                system      = @(Get-KutayTweakSystemChange -Path $file)
                oneWay      = Test-KutayTweakOneWay -Path $file
                option      = Test-KutayTweakOption -Path $file
            }
        })
    [IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $tweaks -Depth 5))
    $tweaks.Count
}

try {
    if (-not $Vmx) { $Vmx = Get-DefaultVmx }
    if (-not $OutFile) { $OutFile = Join-Path $env:TEMP 'kutay-smoke-result.txt' }
    $manifest = Join-Path $env:TEMP 'kutay-smoke-manifest.json'
    $count = Write-SmokeManifest $manifest
    Write-Output "$(Get-Date -Format HH:mm:ss) manifest: $count tweaks"

    if (-not $NoReset) {
        Write-Output "$(Get-Date -Format HH:mm:ss) reverting to $Snapshot and starting"
        Invoke-TestVmReset -Vmx $Vmx -Snapshot $Snapshot -MemoryMB $MemoryMB -CpuCount $CpuCount
    }
    # Guest operations only need Tools, not a logon: the VM boots without the GUI and has no autologon.
    Wait-Until { (Get-VmToolsState $Vmx) -match 'running' } 'VMware Tools'

    Copy-ItemToGuest $Vmx (Join-Path $playbook 'Executables') "$guestRoot\Executables"
    Copy-ItemToGuest $Vmx $manifest "$guestRoot\manifest.json"
    if ($SaveAppliedAs -and $Control) {
        Write-Output "$(Get-Date -Format HH:mm:ss) control: running $ControlMinutes min without tweaks"
        Start-Sleep -Seconds ($ControlMinutes * 60)
        Save-TestVmSnapshot -Vmx $Vmx -Snapshot $SaveAppliedAs
        Write-Output "$(Get-Date -Format HH:mm:ss) saved snapshot $SaveAppliedAs"
        exit 0
    }
    if ($SaveAppliedAs) {
        Write-Output "$(Get-Date -Format HH:mm:ss) applying the default tweaks"
        Invoke-GuestScript -Vmx $Vmx -ScriptPath (Join-Path $PSScriptRoot 'guest-smoke-tweaks.ps1') `
            -GuestResult "$guestRoot\result.txt" -LocalResult $OutFile -ScriptArgs '-ApplyOnly'
        $lines = @(Get-Content -LiteralPath $OutFile)
        $lines
        if (@($lines | Where-Object { $_ -like 'FAIL *' }).Count -or -not @($lines | Where-Object { $_ -like 'PASS applied *' }).Count) {
            throw 'applying the tweaks failed; no snapshot saved'
        }
        # The guest shuts down cleanly, so the snapshot boots like a PC after the playbook's restart.
        Save-TestVmSnapshot -Vmx $Vmx -Snapshot $SaveAppliedAs
        Write-Output "$(Get-Date -Format HH:mm:ss) saved snapshot $SaveAppliedAs"
        exit 0
    }

    Write-Output "$(Get-Date -Format HH:mm:ss) running the guest smoke script"
    Invoke-GuestScript -Vmx $Vmx -ScriptPath (Join-Path $PSScriptRoot 'guest-smoke-tweaks.ps1') `
        -GuestResult "$guestRoot\result.txt" -LocalResult $OutFile

    $lines = @(Get-Content -LiteralPath $OutFile)
    $lines
    $failed = @($lines | Where-Object { $_ -like 'FAIL *' }).Count
    # A guest run that stopped early writes fewer lines, not FAIL lines: every tweak must report in.
    $reported = @($lines | Where-Object { $_ -like 'PASS * snapshot kept on second run' }).Count
    if ($reported -ne $count) {
        $failed++
        Write-Output "FAIL only $reported of $count tweaks finished both passes"
    }
    $checks = @($lines | Where-Object { $_ -like 'PASS *' -or $_ -like 'FAIL *' }).Count
    Write-Output "$(Get-Date -Format HH:mm:ss) $($checks - $failed)/$checks PASS, result in $OutFile"
    if ($failed) { exit 1 }
    exit 0
} catch {
    Write-Error "Invoke-TweakSmoke failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
