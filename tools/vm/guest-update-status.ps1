<#
.SYNOPSIS
    Runs inside the test VM. Read-only: prints pending Windows updates, reboot state and build.
.DESCRIPTION
    First line: "build=26100.<UBR> reboot=<bool> pending=<n> busy=<servicing processes>",
    then one line per pending update. Started by tools/vm/watch-updates.ps1.
#>
# vmrun appends a blank argument to every guest command line; swallow it.
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$VmrunExtra)
$null = $VmrunExtra

$ErrorActionPreference = 'Continue'
$reboot = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
$ubr = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR
try {
    $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
    $titles = @($searcher.Search('IsInstalled=0 and IsHidden=0').Updates | ForEach-Object { $_.Title })
    $pending = $titles.Count
} catch {
    $pending = -1
    $titles = @("ERROR: $($_.Exception.Message)")
}
$busy = @(Get-Process TiWorker, MoUsoCoreWorker, TrustedInstaller -ErrorAction SilentlyContinue |
    ForEach-Object Name) -join ','
"build=26100.$ubr reboot=$reboot pending=$pending busy=$busy"
$titles | ForEach-Object { "  - $_" }
