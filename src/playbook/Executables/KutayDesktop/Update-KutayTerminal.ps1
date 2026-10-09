#Requires -Version 5.1
<#
.SYNOPSIS
    Upgrades Windows Terminal through winget. Run by the "Update Windows Terminal" scheduled task as the
    logged-on user (winget is not supported as SYSTEM); it can also be run by hand.
.DESCRIPTION
    Logs to %LOCALAPPDATA%\KutayOS\terminal-update.log. Does nothing when winget is not there yet.
#>
[CmdletBinding()]
param(
    # Launchers can append a blank argument; ignore it.
    [Parameter(ValueFromRemainingArguments)][string[]]$Rest
)
$ErrorActionPreference = 'Stop'
$null = $Rest

try {
    Import-Module (Join-Path $PSScriptRoot '..\KutayModules\KutayApps.psm1')
    exit (Invoke-KutayTerminalUpdate)
} catch {
    Write-Error "Update-KutayTerminal failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
