#Requires -Version 5.1
<#
.SYNOPSIS
    Sets a system state (hibernation, Compact OS, reserved storage, scheduled tasks) after
    snapshotting the current one, so Revert-KutayOS can put it back. Called from tweak YAML files.
.EXAMPLE
    .\KutayModules\Set-KutaySystemState.ps1 -Id disable-hibernation -Kind Hibernation -State Off
.EXAMPLE
    .\KutayModules\Set-KutaySystemState.ps1 -Id disable-ceip-tasks -Kind ScheduledTask -State Disabled -Name '\Microsoft\Windows\Autochk\Proxy'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Id,
    [Parameter(Mandatory)][ValidateSet('Hibernation', 'CompactOS', 'ReservedStorage', 'ScheduledTask', 'AppPackage', 'KutayTask')][string]$Kind,
    [Parameter(Mandatory)][string]$State,
    # Scheduled tasks only: full task paths.
    [string[]]$Name = @(''),
    # AME and vmrun can append a blank argument; ignore it.
    [Parameter(ValueFromRemainingArguments)][string[]]$Rest
)
$ErrorActionPreference = 'Stop'
$null = $Rest

try {
    Import-Module (Join-Path $PSScriptRoot 'KutayLog.psm1')
    Import-Module (Join-Path $PSScriptRoot 'KutayState.psm1')
    Import-Module (Join-Path $PSScriptRoot 'KutaySystemState.psm1')
    # Snapshot first: the first one wins, so a retry after a failed change still knows the original.
    # A snapshot left by a failed change is harmless; reverting it sets the state it already has.
    Save-KutaySystemSnapshot -Id $Id -Kind $Kind -Name $Name
    foreach ($item in $Name) {
        if (Set-KutaySystemState -Kind $Kind -State $State -Name $item) {
            Write-KutayLog "$Kind $item is $State for $Id"
        } else {
            Write-KutayLog "$Kind $item skipped for $Id (not on this Windows)"
        }
    }
    exit 0
} catch {
    Write-Error "Set-KutaySystemState $Id failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
