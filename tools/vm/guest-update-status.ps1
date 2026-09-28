<#
.SYNOPSIS
    Runs inside the test VM. Read-only: prints pending Windows updates, reboot state and build.
.DESCRIPTION
    First line: "build=26100.<UBR> reboot=<bool> pending=<n> busy=<servicing processes using CPU>",
    then one line per pending update. Started by tools/vm/watch-updates.ps1.
#>
# vmrun appends a blank argument to every guest command line; swallow it.
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$VmrunExtra)
$null = $VmrunExtra

$ErrorActionPreference = 'Continue'
$reboot = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
$ubr = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR

# Sample servicing before the update search: the search itself starts TiWorker/TrustedInstaller,
# which then linger idle for minutes. A process counts as busy only if it uses CPU in the sample
# window, or started during it. Reading CPU of these SYSTEM processes needs an elevated guest.
$servicing = 'TiWorker', 'MoUsoCoreWorker', 'TrustedInstaller'
$sampleSeconds = 5
$busyCpuSeconds = 0.25
$cpuBefore = @{}
Get-Process $servicing -ErrorAction SilentlyContinue | ForEach-Object { $cpuBefore[$_.Id] = $_.CPU }
Start-Sleep -Seconds $sampleSeconds
$busy = @(Get-Process $servicing -ErrorAction SilentlyContinue | Where-Object {
        -not $cpuBefore.ContainsKey($_.Id) -or ($_.CPU - $cpuBefore[$_.Id]) -ge $busyCpuSeconds
    } | ForEach-Object Name) -join ','

try {
    $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
    $titles = @($searcher.Search('IsInstalled=0 and IsHidden=0').Updates | ForEach-Object { $_.Title })
    $pending = $titles.Count
} catch {
    $pending = -1
    $titles = @("ERROR: $($_.Exception.Message)")
}
"build=26100.$ubr reboot=$reboot pending=$pending busy=$busy"
$titles | ForEach-Object { "  - $_" }
