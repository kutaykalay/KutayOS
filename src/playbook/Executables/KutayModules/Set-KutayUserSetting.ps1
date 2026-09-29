#Requires -Version 5.1
<#
.SYNOPSIS
    Writes per-user registry settings to every user profile and the default profile, after
    snapshotting them. Called from tweak YAML files instead of AME's HKCU !registryValue, so the
    snapshot covers exactly the hives that change.
.PARAMETER Setting
    'path|name|type|data', path relative to the user hive; type DWord or String.
.EXAMPLE
    .\KutayModules\Set-KutayUserSetting.ps1 -Id hide-task-view-button -Setting 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|ShowTaskViewButton|DWord|0'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Id,
    [Parameter(Mandatory)][string[]]$Setting
)
$ErrorActionPreference = 'Stop'

try {
    Import-Module (Join-Path $PSScriptRoot 'KutayLog.psm1')
    Import-Module (Join-Path $PSScriptRoot 'KutayState.psm1')
    Set-KutayUserSetting -Id $Id -Setting $Setting
    Write-KutayLog "User settings applied for $Id"
    exit 0
} catch {
    Write-Error "Set-KutayUserSetting $Id failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
