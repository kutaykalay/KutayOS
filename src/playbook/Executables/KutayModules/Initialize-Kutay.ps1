#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$SupportedBuild = 26100
$root = Join-Path $env:windir 'KutayOS'
Import-Module (Join-Path $PSScriptRoot 'KutayLog.psm1')

$os = Get-CimInstance Win32_OperatingSystem
Write-KutayLog "Playbook started on '$($os.Caption)' build $($os.BuildNumber)"

if ([int]$os.BuildNumber -ne $SupportedBuild) {
    Write-KutayLog "Unsupported build $($os.BuildNumber), expected $SupportedBuild. Aborting."
    exit 1
}
if ($os.Caption -notmatch 'LTSC') {
    Write-KutayLog "Warning: edition is not LTSC, continuing."
}

# The revert scripts must keep working after AME Wizard deletes its temporary folder.
# Copy folder contents (not the folders) so a second run overwrites instead of nesting.
$executables = Split-Path -Parent $PSScriptRoot
foreach ($folder in 'KutayModules', 'KutayDesktop') {
    $target = Join-Path $root $folder
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Copy-Item -Path (Join-Path $executables "$folder\*") -Destination $target -Recurse -Force
}
Write-KutayLog "Copied KutayModules and KutayDesktop to $root"
exit 0
