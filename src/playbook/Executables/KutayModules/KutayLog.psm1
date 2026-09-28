#Requires -Version 5.1
# Appends timestamped lines to %windir%\KutayOS\Logs\<name>.log and echoes them for AME's log.

Set-StrictMode -Version 2.0

$script:LogDir = Join-Path $env:windir 'KutayOS\Logs'

function Write-KutayLog {
    param([Parameter(Mandatory)][string]$Message, [string]$Log = 'install')
    New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null
    $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message
    Add-Content -LiteralPath (Join-Path $script:LogDir "$Log.log") -Value $line -Encoding UTF8
    Write-Output $line
}

Export-ModuleMember -Function Write-KutayLog
