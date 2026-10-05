<#
.SYNOPSIS
    Runs inside the test VM. Read-only: collects baseline numbers and LTSC facts as JSON.
.DESCRIPTION
    Writes C:\Users\Public\kutay-baseline.json. Started by tools/vm/measure-baseline.ps1.
#>
# vmrun appends a blank argument to every guest command line; swallow it.
param(
    [int]$CpuSeconds = 120,
    [double]$QuietPct = 10,
    [int]$QuietMinutes = 5,
    [int]$MaxWaitMinutes = 60,
    # Measure no earlier than this many minutes after boot; 0 measures as soon as it is quiet.
    [int]$MinUptimeMinutes = 0,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$VmrunExtra
)
$null = $VmrunExtra

$ErrorActionPreference = 'Continue'
$outFile = 'C:\Users\Public\kutay-baseline.json'
$r = [ordered]@{}

function Get-OrError([scriptblock]$Block) {
    try { & $Block } catch { "ERROR: $($_.Exception.Message)" }
}

# GetSystemTimes is cheap and not localized, unlike WMI polling or Get-Counter paths
Add-Type -Namespace Kutay -Name Cpu -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
'@

function Get-CpuTime {
    $idle = 0L; $kernel = 0L; $user = 0L
    [void][Kutay.Cpu]::GetSystemTimes([ref]$idle, [ref]$kernel, [ref]$user)
    # kernel time includes idle time
    [pscustomobject]@{ Idle = $idle; Total = $kernel + $user }
}

function Get-BusyPercent($From, $To) {
    $total = $To.Total - $From.Total
    if ($total -le 0) { return 0 }
    100 * (1 - ($To.Idle - $From.Idle) / $total)
}

$os = Get-CimInstance Win32_OperatingSystem
$r.collectedAt = (Get-Date).ToString('s')
$r.os = "$($os.Caption) $($os.Version).$((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR)"
$r.uiLanguage = (Get-Culture).Name
$r.uptimeMin = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalMinutes, 1)
$r.isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
$r.interactiveSessions = @(Get-Process explorer -ErrorAction SilentlyContinue).Count

$r.bootEvents = Get-OrError {
    Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100 } -MaxEvents 5 |
        ForEach-Object {
            $x = [xml]$_.ToXml(); $d = @{}
            foreach ($n in $x.Event.EventData.Data) { $d[$n.Name] = $n.'#text' }
            [ordered]@{ time = $_.TimeCreated.ToString('s'); bootMs = [int]$d.BootTime
                mainPathMs = [int]$d.MainPathBootTime; postBootMs = [int]$d.BootPostBootTime }
        }
}

# Windows runs automatic maintenance (Defender scans, defrag, missed tasks) when it goes idle,
# and again after every snapshot revert because the clock jumps. Measuring a fixed time after
# logon captures that work instead of idle, so wait until CPU stays below $QuietPct for
# $QuietMinutes minutes in a row. How long that takes is a metric of its own.
$waitStart = Get-Date
$quietRun = 0
while ($quietRun -lt $QuietMinutes -and ((Get-Date) - $waitStart).TotalMinutes -lt $MaxWaitMinutes) {
    $from = Get-CpuTime
    Start-Sleep -Seconds 60
    if ((Get-BusyPercent $from (Get-CpuTime)) -lt $QuietPct) { $quietRun++ } else { $quietRun = 0 }
}
$r.quietReached = $quietRun -ge $QuietMinutes
$r.quietWaitMin = [math]::Round(((Get-Date) - $waitStart).TotalMinutes, 1)
$r.quietAtUptimeMin = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalMinutes, 1)
$r.quietRule = "cpu<$QuietPct% for $QuietMinutes min, max $MaxWaitMinutes min"

# Memory keeps settling for a while after maintenance (Defender, indexer, svchost grow and shrink),
# so runs that got quiet at different times are not comparable. Measure all of them at the same
# uptime at the earliest.
$uptimeLeft = $MinUptimeMinutes - ((Get-Date) - $os.LastBootUpTime).TotalMinutes
if ($uptimeLeft -gt 0) { Start-Sleep -Seconds ([int]($uptimeLeft * 60)) }
$r.measuredAtUptimeMin = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalMinutes, 1)

$procCpuBefore = @{}
Get-Process | ForEach-Object { $procCpuBefore[$_.Id] = $_.CPU }
$start = Get-CpuTime
$prev = $start
$perSecond = for ($i = 0; $i -lt $CpuSeconds; $i++) {
    Start-Sleep -Seconds 1
    $now = Get-CpuTime
    Get-BusyPercent $prev $now
    $prev = $now
}
$r.cpuIdleAvgPct = [math]::Round((Get-BusyPercent $start $prev), 2)
$r.cpuIdleMaxPct = [math]::Round(($perSecond | Measure-Object -Maximum).Maximum, 1)
$r.cpuSeconds = $CpuSeconds
# Who used the CPU during the measurement, so a noisy run can be explained afterwards
$r.cpuTopProcesses = @(Get-Process | ForEach-Object {
        $prevCpu = 0
        if ($procCpuBefore.ContainsKey($_.Id)) { $prevCpu = $procCpuBefore[$_.Id] }
        [pscustomobject]@{ name = $_.Name; cpuSec = [math]::Round($_.CPU - $prevCpu, 1) }
    } | Sort-Object cpuSec -Descending | Select-Object -First 5)

$os = Get-CimInstance Win32_OperatingSystem
$r.ramTotalMB = [math]::Round($os.TotalVisibleMemorySize / 1KB)
$r.ramUsedMB = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1KB)
$r.commitMB = [math]::Round((Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory).CommittedBytes / 1MB)
$r.processCount = @(Get-Process).Count
$r.runningServices = @(Get-Service | Where-Object Status -eq 'Running').Count
$c = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$r.diskUsedGB = [math]::Round(($c.Size - $c.FreeSpace) / 1GB, 2)
$r.diskSizeGB = [math]::Round($c.Size / 1GB, 2)

$r.winget = Get-OrError { $w = Get-Command winget.exe -ErrorAction Stop; & $w.Source --version }
$r.appInstallerPkg = Get-OrError { (Get-AppxPackage Microsoft.DesktopAppInstaller).Version }
$r.appxCount = Get-OrError { @(Get-AppxPackage).Count }
$r.bitlocker = Get-OrError { (manage-bde -status C: | Out-String).Trim() }
$r.tpm = Get-OrError { $t = Get-Tpm; "present=$($t.TpmPresent) ready=$($t.TpmReady)" }
$r.secureBoot = Get-OrError { Confirm-SecureBootUEFI }
$r.vbs = Get-OrError {
    $g = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard Win32_DeviceGuard
    "status=$($g.VirtualizationBasedSecurityStatus) running=$($g.SecurityServicesRunning -join ',')"
}
$r.edge = Get-OrError {
    (Get-Item "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" -ErrorAction Stop).VersionInfo.ProductVersion
}
$r.store = Get-OrError { (Get-AppxPackage Microsoft.WindowsStore).Version }

[IO.File]::WriteAllText($outFile, ($r | ConvertTo-Json -Depth 5))
