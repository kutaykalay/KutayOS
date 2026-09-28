#Requires -Version 5.1
<#
.SYNOPSIS
    Snapshots registry values before a tweak changes them. Called from tweak YAML files.
.EXAMPLE
    .\KutayModules\Save-KutayState.ps1 -Id disable-telemetry -Registry 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection|AllowTelemetry'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Id,
    [Parameter(Mandatory)][string[]]$Registry
)
$ErrorActionPreference = 'Stop'

try {
    Import-Module (Join-Path $PSScriptRoot 'KutayLog.psm1')
    Import-Module (Join-Path $PSScriptRoot 'KutayState.psm1')
    Save-KutaySnapshot -Id $Id -Registry $Registry
    Write-KutayLog "Snapshot ready for $Id"
    exit 0
} catch {
    Write-Error "Save-KutayState $Id failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
