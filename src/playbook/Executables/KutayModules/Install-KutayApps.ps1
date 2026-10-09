#Requires -Version 5.1
<#
.SYNOPSIS
    Installs winget (App Installer) and Windows Terminal for all users and registers the task that keeps
    Terminal up to date. LTSC 2024 has neither. Called from the install-winget-terminal tweak.
.DESCRIPTION
    Nothing is installed unless every download matches its pinned SHA256 and carries a Microsoft
    signature. Snapshots are taken first, so Revert-KutayOS can remove what this added.
#>
[CmdletBinding()]
param(
    # AME and vmrun can append a blank argument; ignore it.
    [Parameter(ValueFromRemainingArguments)][string[]]$Rest
)
$ErrorActionPreference = 'Stop'
$null = $Rest

try {
    Import-Module (Join-Path $PSScriptRoot 'KutayLog.psm1')
    Import-Module (Join-Path $PSScriptRoot 'KutayState.psm1')
    Import-Module (Join-Path $PSScriptRoot 'KutayApps.psm1')
    $manifest = Get-KutayAppManifest
    # Snapshot first: the first one wins, so a retry after a failed install still knows the original.
    # Only Terminal can be reverted. App Installer (winget) is marked as part of Windows, which refuses to
    # uninstall it (0x80070032, checked in the VM), so it stays; it is harmless without the Store.
    Save-KutaySystemSnapshot -Id 'install-winget-terminal' -Kind AppPackage -Name $manifest.Terminal.PackageName
    Save-KutaySystemSnapshot -Id 'install-winget-terminal-task' -Kind KutayTask -Name (Get-KutayUpdateTaskName)
    Install-KutayWingetAndTerminal
    Register-KutayUpdateTask
    exit 0
} catch {
    # winget is provisioned before Terminal, and Windows will not uninstall it again, so a failure after
    # that point leaves it installed. Running the playbook again skips it and carries on with Terminal.
    Write-Error "Install-KutayApps failed: $($_.Exception.Message). If winget was already installed it stays; running KutayOS again is safe." -ErrorAction Continue
    exit 1
}
