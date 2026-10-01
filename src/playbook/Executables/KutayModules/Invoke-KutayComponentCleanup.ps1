#Requires -Version 5.1
<#
.SYNOPSIS
    Removes superseded component versions from the component store (WinSxS) now, instead of after
    the 30-day grace period of the StartComponentCleanup task. No /ResetBase: installed updates
    stay uninstallable. One-way: removed component versions can't be put back, so no snapshot.
.EXAMPLE
    .\KutayModules\Invoke-KutayComponentCleanup.ps1
#>
[CmdletBinding()]
param(
    # AME and vmrun can append a blank argument; ignore it.
    [Parameter(ValueFromRemainingArguments)][string[]]$Rest
)
$ErrorActionPreference = 'Stop'
$null = $Rest
# DISM exits with 3010 when the cleanup finished and a restart completes it.
$successCodes = 0, 3010

try {
    Import-Module (Join-Path $PSScriptRoot 'KutayLog.psm1')
    Import-Module (Join-Path $PSScriptRoot 'KutaySystemState.psm1')
    Write-KutayLog 'Component store cleanup started'
    $code = Invoke-KutayNativeCommand -FilePath 'dism.exe' -SuccessCode $successCodes `
        -ArgumentList '/Online', '/Cleanup-Image', '/StartComponentCleanup', '/English'
    $note = ''
    if ($code -eq 3010) { $note = ', a restart completes it' }
    Write-KutayLog "Component store cleanup finished (exit code $code$note)"
    exit 0
} catch {
    Write-Error "Component store cleanup failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
