#Requires -Version 5.1
<#
.SYNOPSIS
    Creates the restore point KutayOS needs before any change. Exits 1 if none was created, so AME
    halts before touching the system.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

try {
    Import-Module (Join-Path $PSScriptRoot 'KutayLog.psm1')
    Import-Module (Join-Path $PSScriptRoot 'KutayRestorePoint.psm1')
    $sequence = New-KutayRestorePoint -Description 'KutayOS: before changes'
    Write-KutayLog "Restore point created (sequence $sequence)"
    exit 0
} catch {
    Write-Error "Restore point failed, no changes were made: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
