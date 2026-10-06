#Requires -Version 5.1
<#
.SYNOPSIS
    Checks that Windows Update, Microsoft Defender, Windows Search and the WebView2 Runtime still work.
.DESCRIPTION
    Read-only: changes nothing. Run it as administrator after KutayOS finished and the PC restarted.
    The update search needs an internet connection. Prints one PASS, WARN or FAIL line per check and
    writes them to %windir%\KutayOS\Logs\health.log. Exit code 1 if any check fails.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File "$env:windir\KutayOS\KutayDesktop\Test-KutayHealth.ps1"
#>
[CmdletBinding()]
param(
    # vmrun and some launchers append a blank argument; ignore it.
    [Parameter(ValueFromRemainingArguments)][string[]]$Rest
)
$ErrorActionPreference = 'Stop'
$null = $Rest

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'Run Test-KutayHealth.ps1 as administrator.' -ErrorAction Continue
    exit 1
}

try {
    $modules = Join-Path $PSScriptRoot '..\KutayModules'
    Import-Module (Join-Path $modules 'KutayLog.psm1')
    Import-Module (Join-Path $modules 'KutayHealth.psm1')

    $checks = @(Invoke-KutayHealthCheck)
    foreach ($check in $checks) {
        Write-KutayLog ('{0} {1}: {2}' -f $check.status.ToUpperInvariant(), $check.name, $check.detail) -Log health
    }
    if (@($checks | Where-Object { $_.status -eq 'Fail' }).Count) { exit 1 }
    exit 0
} catch {
    Write-Error "Health check failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
