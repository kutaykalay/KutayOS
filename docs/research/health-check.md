# Windows 11 LTSC 2024 Health Check Script Research

> Checked in the main session on 2026-10-06: the WebView2 `pv` rule and the `MSFT_MpComputerStatus`
> property meanings against the Microsoft Learn pages listed below. Implemented in
> `src/playbook/Executables/KutayModules/KutayHealth.psm1`.

Read-only PowerShell 5.1 health checks for Windows 11 IoT Enterprise LTSC 2024 (build 26100).

## 1. Windows Update Health

**Cmdlet/API**: Windows Update Agent COM API via PowerShell

```powershell
$session = New-Object -ComObject Microsoft.Update.Session
$session.ClientApplicationID = "Health Check"
$searcher = $session.CreateUpdateSearcher()
$results = $searcher.Search("Type='Software'")
```

**Key properties and meanings**:
- `IUpdateSearcher.Search()` accepts criteria string; `Type='Software'` searches for software updates.
- `SearchResult.Updates` collection contains `IUpdate` objects with properties: `Title`, `IsInstalled`.
- `ResultCode` (from download/install operations) returns `OperationResultCode` enum:
  - 0 = Not Started
  - 1 = In Progress
  - 2 = Succeeded
  - 3 = Succeeded With Errors
  - 4 = Failed
  - 5 = Aborted

**Admin requirement**: No—searching the index does not require elevation.

**Dependencies** (services that must be running):
- `wuauserv` — Windows Update Agent service
- `UsoSvc` — Update Orchestrator Service (Windows 10+)
- `BITS` — Background Intelligent Transfer Service (download)
- `CryptSvc` — Cryptographic Services (signature verification)

**Source**: [Windows Update Agent API - Win32 apps](https://learn.microsoft.com/en-us/windows/win32/api/_wua/) and [Searching, Downloading, and Installing Specific Updates - Win32 apps](https://learn.microsoft.com/en-us/windows/win32/wua_sdk/searching--downloading--and-installing-specific-updates)

## 2. Microsoft Defender Health

**Cmdlet**: `Get-MpComputerStatus` (PowerShell Defender module)

```powershell
$status = Get-MpComputerStatus
```

**Key health properties and meanings**:
- `AMServiceEnabled` (boolean) — "If the AM Engine is enabled"
- `AntivirusEnabled` (boolean) — "Specifies whether Antivirus protection is enabled"
- `RealTimeProtectionEnabled` (boolean) — "Specifies whether real-time protection is enabled"
- `AntispywareEnabled` (boolean) — "Specifies whether Antispyware protection is enabled"
- `BehaviorMonitorEnabled` (boolean) — "Specifies whether behavior monitoring is enabled"
- `OnAccessProtectionEnabled` (boolean) — "Specifies whether the computer is monitoring file and program activity"
- `AntivirusSignatureAge` (uint32) — "Antivirus Signature age in days" (65535 = never updated)
- `AntispywareSignatureAge` (uint32) — "Antispyware Signature age in days" (65535 = never updated)
- `AMRunningMode` (string) — Operational mode, expected: "Normal"
- `QuickScanAge` (uint32) — "Last quick scan age in days"
- `FullScanAge` (uint32) — "Last full scan age in days" (65535 = never run)

**Class**: `MSFT_MpComputerStatus` (Windows Management Instrumentation class in `Root\Microsoft\Windows\Defender` namespace)

**Admin requirement**: No—querying status does not require elevation.

**Source**: [Get-MpComputerStatus (Defender) - PowerShell Module Reference](https://learn.microsoft.com/en-us/powershell/module/defender/get-mpcomputerstatus?view=windowsserver2025-ps) and [MSFT_MpComputerStatus class](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/defender/msft-mpcomputerstatus)

## 3. Windows Search Index

**API**: OLE DB with Search.CollatorDSO provider

```powershell
$connStr = "Provider=Search.CollatorDSO;Extended Properties='Application=Windows';"
$connection = New-Object System.Data.OleDb.OleDbConnection($connStr)
$connection.Open()
$cmd = $connection.CreateCommand()
$cmd.CommandText = "SELECT Top 1 System.ItemPathDisplay FROM SystemIndex"
$reader = $cmd.ExecuteReader()
# Check if query returns results
```

**Query syntax**: SQL subset
```sql
SELECT [columns] FROM SystemIndex WHERE [conditions]
```

**Key points**:
- Provider string: `Provider=Search.CollatorDSO` or `Provider=Search.CollatorDSO.1`
- **Read-only access only**—supports SELECT and GROUP BY; INSERT/DELETE not supported.
- `SystemIndex` is the catalog name; query locally with `FROM SystemIndex` or remotely with `FROM [ComputerName.]SystemIndex`.
- Returns results if at least one indexed item matches.

**Service dependency**: `WSearch` — Windows Search service

**Admin requirement**: No—querying the index does not require elevation.

**Source**: [Using SQL and AQS approaches to query the index - Win32 apps](https://learn.microsoft.com/en-us/windows/win32/search/using-sql-and-aqs-to-query-the-index)

## 4. WebView2 Runtime Detection

**Method**: Registry key inspection (recommended)

```powershell
# Per-machine install (64-bit Windows)
$keyPath64 = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
$versionPM = (Get-ItemProperty -Path $keyPath64 -Name pv -ErrorAction SilentlyContinue).pv

# Per-user install
$keyPathUser = "HKCU:\Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
$versionPU = (Get-ItemProperty -Path $keyPathUser -Name pv -ErrorAction SilentlyContinue).pv

# WebView2 is installed if at least one is present and > 0.0.0.0
$installed = ($versionPM -and $versionPM -ne "0.0.0.0") -or ($versionPU -and $versionPU -ne "0.0.0.0")
```

**Registry keys** (64-bit Windows):
- Per-machine: `HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}`
- Per-user: `HKEY_CURRENT_USER\Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}`

**Value to inspect**: `pv` (REG_SZ string containing semantic version)

**Interpretation**:
- If both keys missing OR both have null/empty/"0.0.0.0" → **not installed**.
- If either key is present with version > 0.0.0.0 → **installed**; value is the runtime version.

**Admin requirement**: No—registry read of EdgeUpdate does not require elevation.

**Alternative method** (C/C++/WinRT only): `GetAvailableCoreWebView2BrowserVersionString()` API returns `nullptr` if not installed.

**Source**: [Distribute your app and the WebView2 Runtime - Microsoft Edge Developer documentation](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution) (section "Detect if a WebView2 Runtime is already installed")

---

## Sources

- [Windows Update Agent API - Win32 apps](https://learn.microsoft.com/en-us/windows/win32/api/_wua/)
- [Searching, Downloading, and Installing Specific Updates - Win32 apps](https://learn.microsoft.com/en-us/windows/win32/wua_sdk/searching--downloading--and-installing-specific-updates)
- [Get-MpComputerStatus (Defender) - PowerShell Module Reference](https://learn.microsoft.com/en-us/powershell/module/defender/get-mpcomputerstatus?view=windowsserver2025-ps)
- [MSFT_MpComputerStatus class](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/defender/msft-mpcomputerstatus)
- [Using SQL and AQS approaches to query the index - Win32 apps](https://learn.microsoft.com/en-us/windows/win32/search/using-sql-and-aqs-to-query-the-index)
- [Distribute your app and the WebView2 Runtime - Microsoft Edge Developer documentation](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution)
