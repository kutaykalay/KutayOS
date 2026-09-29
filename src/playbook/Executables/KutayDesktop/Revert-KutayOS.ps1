#Requires -Version 5.1
<#
.SYNOPSIS
    Puts back the settings KutayOS changed, from the snapshots in %windir%\KutayOS\State.
.DESCRIPTION
    Run as administrator. System Protection stays on: turning it off would delete every restore
    point, including the one KutayOS made.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File "$env:windir\KutayOS\KutayDesktop\Revert-KutayOS.ps1" -All
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File "$env:windir\KutayOS\KutayDesktop\Revert-KutayOS.ps1" -Id disable-telemetry
#>
[CmdletBinding(DefaultParameterSetName = 'All')]
param(
    [Parameter(Mandatory, ParameterSetName = 'One')][string[]]$Id,
    [Parameter(ParameterSetName = 'All')][switch]$All,
    # vmrun and some launchers append a blank argument; ignore it.
    [Parameter(ValueFromRemainingArguments)][string[]]$Rest
)
$ErrorActionPreference = 'Stop'
$null = $All, $Rest

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'Run Revert-KutayOS.ps1 as administrator.' -ErrorAction Continue
    exit 1
}

try {
    $modules = Join-Path $PSScriptRoot '..\KutayModules'
    Import-Module (Join-Path $modules 'KutayLog.psm1')
    Import-Module (Join-Path $modules 'KutayState.psm1')
    if ($PSCmdlet.ParameterSetName -eq 'All') { $Id = @(Get-KutaySnapshotId -NewestFirst) }
    if (-not $Id) { Write-KutayLog 'Nothing to revert.' -Log revert; exit 0 }

    $failed = 0
    foreach ($one in $Id) {
        try {
            Restore-KutaySnapshot -Id $one
            Write-KutayLog "Reverted $one" -Log revert
        } catch {
            $failed++
            Write-KutayLog "Could not revert ${one}: $($_.Exception.Message)" -Log revert
        }
    }
    if ($failed) { exit 1 }
    exit 0
} catch {
    Write-Error "Revert failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
