<#
.SYNOPSIS
    Measures the running test VM: waits for Tools and a desktop logon, lets it settle, then runs
    guest-baseline.ps1 in the guest and saves the JSON on the host.
.DESCRIPTION
    Needs KUTAY_VM_PASS and KUTAY_GUEST_PASS (see VmGuest.psm1). Start the VM and log in first.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/vm/measure-baseline.ps1 -OutFile docs/measurements/clean-1.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutFile,
    [string]$Vmx = '',
    [int]$SettleSeconds = 300,
    [int]$CpuSeconds = 120
)

$ErrorActionPreference = 'Stop'
$pollSeconds = 5
$maxPolls = 180
Import-Module (Join-Path $PSScriptRoot 'VmGuest.psm1') -Force

function Wait-Until([scriptblock]$Condition, [string]$What) {
    for ($i = 0; $i -lt $maxPolls; $i++) {
        if (& $Condition) { return }
        Start-Sleep -Seconds $pollSeconds
    }
    throw "Timed out waiting for $What"
}

try {
    if (-not $Vmx) { $Vmx = Get-DefaultVmx }
    Wait-Until { (Get-VmToolsState $Vmx) -match 'running' } 'VMware Tools'
    Wait-Until { Test-GuestDesktop $Vmx } 'a desktop logon'
    Write-Output "$(Get-Date -Format HH:mm:ss) desktop up; settling $SettleSeconds s"
    Start-Sleep -Seconds $SettleSeconds

    Write-Output "$(Get-Date -Format HH:mm:ss) measuring for $CpuSeconds s"
    Invoke-GuestScript -Vmx $Vmx -ScriptPath (Join-Path $PSScriptRoot 'guest-baseline.ps1') `
        -GuestResult 'C:\Users\Public\kutay-baseline.json' -LocalResult $OutFile -ScriptArgs "-CpuSeconds $CpuSeconds"
    Write-Output "$(Get-Date -Format HH:mm:ss) saved $OutFile"
    exit 0
} catch {
    Write-Error "measure-baseline failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
