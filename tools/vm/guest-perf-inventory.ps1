<#
.SYNOPSIS
    Runs inside the test VM. Read-only: which services, processes and scheduled tasks cost
    resources at idle, as JSON.
.DESCRIPTION
    Writes C:\Users\Public\kutay-perf-inventory.json. Started by tools/vm/measure-perf-inventory.ps1.
    Svchost runs one service per process when the machine has more than 3.5 GB RAM (default
    SvcHostSplitThresholdInKB), so a service's process memory is its own cost. Shared processes are
    marked with all their services.
#>
# vmrun appends a blank argument to every guest command line; swallow it.
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$VmrunExtra)
$null = $VmrunExtra

$ErrorActionPreference = 'Continue'
$outFile = 'C:\Users\Public\kutay-perf-inventory.json'
$r = [ordered]@{}

$os = Get-CimInstance Win32_OperatingSystem
$r.collectedAt = (Get-Date).ToString('s')
$r.uptimeMin = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalMinutes, 1)
$r.ramTotalMB = [math]::Round($os.TotalVisibleMemorySize / 1KB)
$r.interactiveSessions = @(Get-Process explorer -ErrorAction SilentlyContinue).Count

$processes = @{}
foreach ($p in Get-CimInstance Win32_Process) { $processes[[int]$p.ProcessId] = $p }
$perfById = @{}
# _Total has process id 0 too; it would overwrite the Idle process.
foreach ($p in Get-CimInstance Win32_PerfFormattedData_PerfProc_Process | Where-Object Name -ne '_Total') { $perfById[[int]$p.IDProcess] = $p }

$services = @(Get-CimInstance Win32_Service)
$byPid = @{}
foreach ($s in $services | Where-Object { $_.ProcessId -gt 0 }) {
    $key = [int]$s.ProcessId
    if (-not $byPid.ContainsKey($key)) { $byPid[$key] = New-Object System.Collections.Generic.List[string] }
    $byPid[$key].Add($s.Name)
}

function Get-PrivateMB([int]$ProcessId) {
    if (-not $perfById.ContainsKey($ProcessId)) { return $null }
    [math]::Round($perfById[$ProcessId].PrivateBytes / 1MB, 1)
}

$r.runningServices = @($services | Where-Object State -eq 'Running' | Sort-Object Name | ForEach-Object {
        $procId = [int]$_.ProcessId
        $serviceName = $_.Name
        [ordered]@{
            name         = $serviceName
            startMode    = $_.StartMode
            delayed      = [bool]$_.DelayedAutoStart
            pid          = $procId
            sharedWith   = @($byPid[$procId] | Where-Object { $_ -ne $serviceName })
            privateMB    = Get-PrivateMB $procId
            workingSetMB = if ($processes.ContainsKey($procId)) { [math]::Round($processes[$procId].WorkingSetSize / 1MB, 1) } else { $null }
        }
    })

$r.processes = @($processes.Values | Sort-Object Name | ForEach-Object {
        [ordered]@{
            name      = $_.Name
            pid       = [int]$_.ProcessId
            privateMB = Get-PrivateMB ([int]$_.ProcessId)
            services  = @($byPid[[int]$_.ProcessId])
        }
    })
$r.processCount = $r.processes.Count

$r.scheduledTasks = @(Get-ScheduledTask | Where-Object State -ne 'Disabled' | ForEach-Object {
        $info = $_ | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        [ordered]@{
            path       = "$($_.TaskPath)$($_.TaskName)"
            state      = [string]$_.State
            lastRun    = if ($info -and $info.LastRunTime -and $info.LastRunTime.Year -gt 2000) { $info.LastRunTime.ToString('s') } else { $null }
            lastResult = if ($info) { $info.LastTaskResult } else { $null }
            nextRun    = if ($info -and $info.NextRunTime) { $info.NextRunTime.ToString('s') } else { $null }
        }
    } | Sort-Object { $_.path })

[IO.File]::WriteAllText($outFile, (ConvertTo-Json -InputObject $r -Depth 5))
