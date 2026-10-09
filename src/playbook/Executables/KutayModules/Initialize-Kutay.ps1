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

# Only SYSTEM and Administrators may change this folder; everyone else can read and run from it. The
# winget/Terminal update task runs KutayDesktop\Update-KutayTerminal.ps1 for every user, so a script a
# standard user could edit there would run as each user at logon. This is also Windows' default for a
# folder under C:\Windows; setting it makes the rule explicit.
$acl = New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true, $false)
$fullControl = [Security.AccessControl.FileSystemRights]::FullControl
$readExecute = [Security.AccessControl.FileSystemRights]::ReadAndExecute
foreach ($grant in @(@('S-1-5-18', $fullControl), @('S-1-5-32-544', $fullControl), @('S-1-5-32-545', $readExecute))) {
    $identity = New-Object Security.Principal.SecurityIdentifier $grant[0]
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule $identity, $grant[1], 'ContainerInherit, ObjectInherit', 'None', 'Allow'))
}
Set-Acl -LiteralPath $root -AclObject $acl
Write-KutayLog "Set the permissions of ${root}: SYSTEM and Administrators full control, Users read and run"
exit 0
