<#
Read-only disk report for Slice 4 (Compact). Runs inside the test VM (via Invoke-GuestScript) and
writes C:\Users\Public\disk-usage.txt: free space on C:, the size of hiberfil.sys, pagefile.sys and
the component store, and the state of hibernation, Compact OS and reserved storage.
vmrun appends a blank argument, so remaining arguments are accepted and ignored.
#>
param([Parameter(ValueFromRemainingArguments)][object[]]$Rest)
$null = $Rest
$OutFile = 'C:\Users\Public\disk-usage.txt'
$ErrorActionPreference = 'Continue'
$lines = New-Object System.Collections.Generic.List[string]

function Add-Line([string]$Name, $Value) { $lines.Add(('{0} = {1}' -f $Name, $Value)) }

function Get-HiddenFileSize([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($item) { return $item.Length }
    'absent'
}

$drive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'"
Add-Line 'disk.size' $drive.Size
Add-Line 'disk.free' $drive.FreeSpace
Add-Line 'disk.used' ($drive.Size - $drive.FreeSpace)
Add-Line 'file.hiberfil' (Get-HiddenFileSize 'C:\hiberfil.sys')
Add-Line 'file.pagefile' (Get-HiddenFileSize 'C:\pagefile.sys')
Add-Line 'ram.total' (Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory

$power = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -ErrorAction SilentlyContinue
foreach ($name in 'HibernateEnabled', 'HibernateEnabledDefault', 'HiberFileSizePercent', 'HiberFileType') {
    Add-Line "power.$name" $power.$name
}
$session = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
Add-Line 'power.HiberbootEnabled' (Get-ItemProperty -LiteralPath $session -ErrorAction SilentlyContinue).HiberbootEnabled

$reserved = Get-WindowsReservedStorageState -ErrorAction SilentlyContinue
Add-Line 'reserved.state' $reserved.ReservedStorageState
$manager = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' -ErrorAction SilentlyContinue
foreach ($name in 'ShippedWithReserves', 'PassedPolicy', 'ActiveScenario', 'MiscPolicyInfo') {
    Add-Line "reserved.$name" $manager.$name
}

$compact = & compact.exe /CompactOS:query 2>&1
Add-Line 'compactos.exitcode' $LASTEXITCODE
foreach ($line in $compact) { if ("$line".Trim()) { Add-Line 'compactos.text' "$line".Trim() } }
# A WOF-compressed file carries reparse tag 0x80000017; this does not depend on the display language.
$wof = & fsutil.exe reparsepoint query 'C:\Windows\System32\ntoskrnl.exe' 2>&1 | Select-Object -First 1
Add-Line 'compactos.ntoskrnl.reparse' "$wof".Trim()

$store = & dism.exe /Online /Cleanup-Image /AnalyzeComponentStore /English 2>&1
foreach ($line in $store) { if ("$line" -match ':' -and "$line" -notmatch '^Deployment|^Version') { Add-Line 'store' "$line".Trim() } }

[IO.File]::WriteAllLines($OutFile, $lines)
