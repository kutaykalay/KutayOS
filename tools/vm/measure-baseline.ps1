<#
.SYNOPSIS
    Measures the test VM: runs guest-baseline.ps1 in the guest, then guest-perf-inventory.ps1, and
    saves both JSON files on the host. The guest script waits until the VM is quiet (automatic
    maintenance done) before it measures, so a run can take up to about 65 minutes.
.DESCRIPTION
    Needs KUTAY_VM_PASS and KUTAY_GUEST_PASS (see VmGuest.psm1).
    -Snapshot reverts to that powered-off snapshot and boots it first; without it the VM must be
    running already. -NoLogon measures without a desktop logon (fully unattended: services and
    system processes only, no boot-to-desktop time); otherwise log in by hand after boot.
    The inventory is saved next to -OutFile as <name>.inventory.json.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/vm/measure-baseline.ps1 -OutFile docs/measurements/slice5/clean-nologon-1.json -Snapshot clean-9550-scanned -NoLogon
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutFile,
    [string]$Vmx = '',
    [string]$Snapshot = '',
    [switch]$NoLogon,
    # Memory for this boot when -Snapshot is used; 4 GB fits the dev host's commit limit. 0 keeps the snapshot's.
    [int]$MemoryMB = 4096,
    [int]$SettleSeconds = 60,
    # Measure no earlier than this many minutes after boot, so runs are compared at the same uptime.
    [int]$MinUptimeMinutes = 30,
    [int]$CpuSeconds = 120
)

$ErrorActionPreference = 'Stop'
$pollSeconds = 5
$maxPolls = 180
# A logon by hand can take a while after boot
$maxLogonPolls = 720
Import-Module (Join-Path $PSScriptRoot 'VmGuest.psm1') -Force

function Wait-Until([scriptblock]$Condition, [string]$What, [int]$MaxPolls = $maxPolls) {
    for ($i = 0; $i -lt $MaxPolls; $i++) {
        if (& $Condition) { return }
        Start-Sleep -Seconds $pollSeconds
    }
    throw "Timed out waiting for $What"
}

try {
    if (-not $Vmx) { $Vmx = Get-DefaultVmx }
    $outDir = Split-Path -Parent ([IO.Path]::GetFullPath($OutFile))
    if (-not (Test-Path -LiteralPath $outDir)) { $null = New-Item -ItemType Directory -Path $outDir }
    $inventoryFile = [IO.Path]::ChangeExtension($OutFile, '.inventory.json')

    if ($Snapshot) {
        Write-Output "$(Get-Date -Format HH:mm:ss) reverting to $Snapshot and starting"
        Invoke-TestVmReset -Vmx $Vmx -Snapshot $Snapshot -MemoryMB $MemoryMB
    }
    Wait-Until { (Get-VmToolsState $Vmx) -match 'running' } 'VMware Tools'
    if ($NoLogon) {
        Write-Output "$(Get-Date -Format HH:mm:ss) Tools up, no logon"
    } else {
        Write-Output "$(Get-Date -Format HH:mm:ss) Tools up; waiting for a desktop logon in the VM window"
        Wait-Until { Test-GuestDesktop $Vmx } 'a desktop logon' $maxLogonPolls
        Write-Output "$(Get-Date -Format HH:mm:ss) desktop up; settling $SettleSeconds s"
        Start-Sleep -Seconds $SettleSeconds
    }

    Write-Output "$(Get-Date -Format HH:mm:ss) waiting for quiet, then measuring for $CpuSeconds s"
    Invoke-GuestScript -Vmx $Vmx -ScriptPath (Join-Path $PSScriptRoot 'guest-baseline.ps1') `
        -GuestResult 'C:\Users\Public\kutay-baseline.json' -LocalResult $OutFile -ScriptArgs "-CpuSeconds $CpuSeconds -MinUptimeMinutes $MinUptimeMinutes"
    Write-Output "$(Get-Date -Format HH:mm:ss) saved $OutFile"
    Invoke-GuestScript -Vmx $Vmx -ScriptPath (Join-Path $PSScriptRoot 'guest-perf-inventory.ps1') `
        -GuestResult 'C:\Users\Public\kutay-perf-inventory.json' -LocalResult $inventoryFile
    Write-Output "$(Get-Date -Format HH:mm:ss) saved $inventoryFile"
    exit 0
} catch {
    Write-Error "measure-baseline failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
