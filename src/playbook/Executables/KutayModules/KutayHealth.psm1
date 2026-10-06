#Requires -Version 5.1
# Read-only checks that the parts of Windows KutayOS promises to keep still work: Windows Update,
# Defender, search and the WebView2 Runtime. Each check returns { name, status, detail } with
# status Pass, Warn or Fail; a check never throws, so one broken part does not hide the others.
# Sources:
#   https://learn.microsoft.com/en-us/windows/win32/api/wuapi/ne-wuapi-operationresultcode
#   https://learn.microsoft.com/en-us/powershell/module/defender/get-mpcomputerstatus
#   https://learn.microsoft.com/en-us/windows/win32/search/-search-sql-windowssearch-entry
#   https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution#detect-if-a-webview2-runtime-is-already-installed

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'  # modules don't inherit the caller's preference
Import-Module (Join-Path $PSScriptRoot 'KutayState.psm1')

$script:WebView2Client = 'Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
# 64-bit Windows: per-machine install under WOW6432Node, per-user install under HKCU.
$script:WebView2Keys = [ordered]@{
    'per-machine' = "HKLM\SOFTWARE\WOW6432Node\$script:WebView2Client"
    'per-user'    = "HKCU\Software\$script:WebView2Client"
}
$script:NoVersion = [version]'0.0.0.0'
$script:SignatureMaxDays = 7
$script:DefenderSwitches = 'AMServiceEnabled', 'AntivirusEnabled', 'RealTimeProtectionEnabled'
$script:UpdateServices = 'wuauserv', 'BITS', 'UsoSvc', 'CryptSvc'
$script:UpdateCriteria = 'IsInstalled=0 and IsHidden=0'
# OperationResultCode: 2 succeeded, 3 succeeded with errors, 4 failed, 5 aborted.
$script:UpdateSucceeded = 2
$script:UpdatePartial = 3
$script:SearchService = 'WSearch'
$script:SearchConnection = "Provider=Search.CollatorDSO;Extended Properties='Application=Windows';"
$script:SearchQuery = 'SELECT TOP 5 System.ItemUrl FROM SystemIndex'
$script:Checks = [ordered]@{
    'Windows Update'     = 'Test-KutayWindowsUpdate'
    'Microsoft Defender' = 'Test-KutayDefender'
    'Windows Search'     = 'Test-KutaySearch'
    'WebView2 Runtime'   = 'Test-KutayWebView2'
}

function New-KutayCheck([string]$Name, [string]$Status, [string]$Detail) {
    [pscustomobject]@{ name = $Name; status = $Status; detail = $Detail }
}

function ConvertTo-KutayVersion([string]$Text) {
    $version = $null
    if (-not [version]::TryParse($Text, [ref]$version)) { return $null }
    $version
}

function Test-KutayWebView2 {
    $name = 'WebView2 Runtime'
    foreach ($scope in $script:WebView2Keys.Keys) {
        $pv = Read-KutayRegistryValue -Path $script:WebView2Keys[$scope] -Name 'pv'
        if (-not $pv.exists) { continue }
        $version = ConvertTo-KutayVersion ([string]$pv.data)
        if ($version -and $version -gt $script:NoVersion) {
            return New-KutayCheck $name 'Pass' "version $version ($scope)"
        }
    }
    New-KutayCheck $name 'Fail' 'not installed (no pv version above 0.0.0.0)'
}

function Get-KutayDefenderStatus { Get-MpComputerStatus -ErrorAction Stop }

function Test-KutayDefender {
    $name = 'Microsoft Defender'
    try {
        $status = Get-KutayDefenderStatus
        if (-not $status) { return New-KutayCheck $name 'Fail' 'no status returned' }
        # AMRunningMode is missing on older Defender platforms.
        $mode = ''
        if ($status.PSObject.Properties['AMRunningMode']) { $mode = [string]$status.AMRunningMode }
        $off = @($script:DefenderSwitches | Where-Object { -not $status.$_ })
        $age = $status.AntivirusSignatureAge
    } catch { return New-KutayCheck $name 'Fail' "status unavailable: $($_.Exception.Message)" }

    # Passive: another antivirus protects the PC and Defender's real-time protection is off by design.
    if ($mode -like '*Passive*') { return New-KutayCheck $name 'Warn' "running in $mode mode next to another antivirus" }
    if ($off.Count) { return New-KutayCheck $name 'Fail' "off: $($off -join ', ')" }
    if ($null -eq $age) { return New-KutayCheck $name 'Warn' 'protection on, signature age unknown' }
    # Never-updated signatures report 65535 or more days; uint32 does not fit [int].
    $age = [int64]$age
    if ($age -gt $script:SignatureMaxDays) {
        return New-KutayCheck $name 'Warn' "protection on, but signatures are $age days old"
    }
    New-KutayCheck $name 'Pass' "protection on, signatures $age days old"
}

function Invoke-KutayUpdateSearch {
    $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
    $result = $searcher.Search($script:UpdateCriteria)
    [pscustomobject]@{ resultCode = [int]$result.ResultCode; pending = [int]$result.Updates.Count }
}

# Services that cannot start (missing or disabled); a stopped manual service is normal.
function Get-KutayBlockedService([string[]]$Names) {
    $services = @(Get-Service -Name $Names -ErrorAction SilentlyContinue)
    @($Names | Where-Object {
            $one = $_
            $service = @($services | Where-Object { $_.Name -eq $one })
            -not $service.Count -or $service[0].StartType -eq 'Disabled'
        })
}

function Test-KutayWindowsUpdate {
    $name = 'Windows Update'
    $blocked = @(Get-KutayBlockedService $script:UpdateServices)
    if ($blocked.Count) { return New-KutayCheck $name 'Fail' "missing or disabled: $($blocked -join ', ')" }

    try { $search = Invoke-KutayUpdateSearch } catch {
        return New-KutayCheck $name 'Fail' "update search failed (check the internet connection): $($_.Exception.Message)"
    }
    $detail = "search ok, $($search.pending) updates available"
    if ($search.resultCode -eq $script:UpdateSucceeded) { return New-KutayCheck $name 'Pass' $detail }
    if ($search.resultCode -eq $script:UpdatePartial) { return New-KutayCheck $name 'Warn' "$detail, with errors" }
    New-KutayCheck $name 'Fail' "update search ended with result code $($search.resultCode)"
}

# Number of rows (at most 5) the Windows Search index returns.
function Invoke-KutaySearchQuery {
    $connection = New-Object -ComObject ADODB.Connection
    $records = New-Object -ComObject ADODB.Recordset
    try {
        $connection.Open($script:SearchConnection)
        $records.Open($script:SearchQuery, $connection)
        $count = 0
        while (-not $records.EOF) { $count++; $records.MoveNext() }
        [int]$count
    } finally {
        if ($records.State) { $records.Close() }
        if ($connection.State) { $connection.Close() }
    }
}

function Test-KutaySearch {
    $name = 'Windows Search'
    $service = @(Get-Service -Name $script:SearchService -ErrorAction SilentlyContinue)
    if (-not $service.Count) { return New-KutayCheck $name 'Fail' "$($script:SearchService) service is missing" }
    if ($service[0].StartType -eq 'Disabled' -or $service[0].Status -ne 'Running') {
        return New-KutayCheck $name 'Fail' "$($script:SearchService) is $($service[0].Status) ($($service[0].StartType))"
    }

    try { $rows = Invoke-KutaySearchQuery } catch { return New-KutayCheck $name 'Fail' "index query failed: $($_.Exception.Message)" }
    if ($rows -lt 1) { return New-KutayCheck $name 'Warn' 'indexer runs, but the index is still empty; try again later' }
    New-KutayCheck $name 'Pass' 'indexer runs and returns results'
}

# A check that throws anyway becomes a failed check, so the others still run.
function Invoke-KutayHealthCheck {
    foreach ($name in $script:Checks.Keys) {
        try { & $script:Checks[$name] } catch { New-KutayCheck $name 'Fail' "check failed: $($_.Exception.Message)" }
    }
}

Export-ModuleMember -Function Invoke-KutayHealthCheck, Test-KutayWindowsUpdate, Test-KutayDefender, Test-KutaySearch,
    Test-KutayWebView2
