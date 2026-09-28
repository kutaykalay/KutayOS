#Requires -Version 5.1
# Creates the System Restore point KutayOS takes before it changes anything.
# Sources:
#   https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/checkpoint-computer?view=powershell-5.1
#   https://learn.microsoft.com/en-us/windows/win32/sr/createrestorepoint-systemrestore
# Windows skips a restore point if one was made in the last 24 hours and still reports success,
# so success is checked by comparing sequence numbers, not by errors.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'  # modules don't inherit the caller's preference
Import-Module (Join-Path $PSScriptRoot 'KutayState.psm1')

$script:FrequencyId = 'restore-point-frequency'
$script:FrequencyKey = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
$script:FrequencyName = 'SystemRestorePointCreationFrequency'

function Get-KutayLatestRestorePoint {
    $points = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue)
    if ($points.Count -eq 0) { return 0 }
    [int]($points | Measure-Object -Property SequenceNumber -Maximum).Maximum
}

function New-KutayRestorePoint {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Description)
    if (-not $PSCmdlet.ShouldProcess("$env:SystemDrive\", 'Create restore point')) { return }

    # System Protection is off by default on LTSC; enabling an enabled drive is a no-op.
    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
    $before = Get-KutayLatestRestorePoint

    # 0 = never skip. The prior value (usually absent) is put back right after the checkpoint.
    Save-KutaySnapshot -Id $script:FrequencyId -Registry "$($script:FrequencyKey)|$($script:FrequencyName)"
    try {
        Set-KutayRegistryValue -Path $script:FrequencyKey -Name $script:FrequencyName -Type DWord -Data 0
        Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    } finally {
        Restore-KutaySnapshot -Id $script:FrequencyId
    }

    $after = Get-KutayLatestRestorePoint
    if ($after -le $before) { throw "No new restore point was created (latest sequence number is still $after)" }
    $after
}

Export-ModuleMember -Function New-KutayRestorePoint
