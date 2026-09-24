#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$SupportedBuild = 26100
$root = Join-Path $env:windir 'KutayOS'
$logDir = Join-Path $root 'Logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir 'install.log'

function Write-KutayLog([string]$Message) {
    $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
}

$os = Get-CimInstance Win32_OperatingSystem
Write-KutayLog "Playbook started on '$($os.Caption)' build $($os.BuildNumber)"

if ([int]$os.BuildNumber -ne $SupportedBuild) {
    Write-KutayLog "Unsupported build $($os.BuildNumber), expected $SupportedBuild. Aborting."
    exit 1
}
if ($os.Caption -notmatch 'LTSC') {
    Write-KutayLog "Warning: edition is not LTSC, continuing."
}
exit 0
