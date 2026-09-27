<#
.SYNOPSIS
    Checks Windows Update in the running test VM every few minutes and stops once servicing is
    idle and either a reboot is due or nothing is left to install.
.DESCRIPTION
    Needs KUTAY_VM_PASS and KUTAY_GUEST_PASS (see VmGuest.psm1). Read-only in the guest.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/vm/watch-updates.ps1
#>
[CmdletBinding()]
param(
    [string]$Vmx = '',
    [int]$IntervalSeconds = 300,
    [int]$MaxChecks = 24
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'VmGuest.psm1') -Force
$local = Join-Path $env:TEMP 'kutay-update-status.txt'
$guestOut = 'C:\Users\Public\kutay-update-status.txt'

try {
    if (-not $Vmx) { $Vmx = Get-DefaultVmx }
    for ($i = 0; $i -lt $MaxChecks; $i++) {
        Invoke-GuestScript -Vmx $Vmx -ScriptPath (Join-Path $PSScriptRoot 'guest-update-status.ps1') `
            -GuestResult $guestOut -LocalResult $local -StdoutFile $guestOut
        $out = @(Get-Content -LiteralPath $local)
        Write-Output "$(Get-Date -Format HH:mm) $($out -join ' | ')"
        # Stop only when servicing is idle: then either a reboot is due or nothing is left.
        $idle = $out.Count -gt 0 -and $out[0] -match 'busy=$'
        if ($idle -and ($out[0] -match 'reboot=True' -or $out[0] -match 'pending=0 ')) { exit 0 }
        if ($i -lt $MaxChecks - 1) { Start-Sleep -Seconds $IntervalSeconds }
    }
    Write-Output 'Still busy after the last check.'
    exit 0
} catch {
    Write-Error "watch-updates failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
