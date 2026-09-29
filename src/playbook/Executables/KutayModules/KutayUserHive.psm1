#Requires -Version 5.1
# Finds every user registry hive (each real user profile plus the default profile that new accounts
# are copied from) and opens it, so per-user settings reach all accounts, not only the one running.
# A hive that is already loaded (a signed-in user, or one AME loaded) is used where it is; any other
# is loaded under HKU\KutayOS_<user> and unloaded again afterwards.
# HKCU\Software\Classes is not in NTUSER.DAT but in the profile's UsrClass.dat (the classes hive).
# The default profile has none: Windows creates it fresh for each new account.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:ProfileListKey = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
$script:HiveListKey = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\hivelist'
# Local and domain accounts; service accounts (S-1-5-18/19/20) have no user settings to change.
$script:UserSidPattern = '^S-1-5-21-[0-9-]+$'
$script:MountPrefix = 'KutayOS_'
$script:ClassesFile = 'AppData\Local\Microsoft\Windows\UsrClass.dat'
$script:ClassesPattern = '^Software\\Classes\\(.+)$'
$script:UnloadAttempts = 5
$script:UnloadRetryMilliseconds = 500

function Get-KutayProfile {
    Get-ChildItem -LiteralPath $script:ProfileListKey | ForEach-Object {
        [pscustomobject]@{
            sid  = $_.PSChildName
            path = [Environment]::ExpandEnvironmentVariables([string]$_.GetValue('ProfileImagePath'))
        }
    }
}

function Get-KutayDefaultProfilePath {
    $default = (Get-ItemProperty -LiteralPath $script:ProfileListKey).Default
    [Environment]::ExpandEnvironmentVariables([string]$default)
}

# Loaded hives as '\REGISTRY\USER\<key>' -> '\Device\HarddiskVolumeN\<path of the hive file>'.
function Get-KutayHiveList {
    $key = Get-Item -LiteralPath $script:HiveListKey
    $list = @{}
    foreach ($name in $key.GetValueNames()) { $list[$name] = [string]$key.GetValue($name) }
    $list
}

# A hive that can't be opened (in use elsewhere, damaged). Callers skip that profile with a warning
# instead of failing every other account.
if (-not ('KutayHiveUnavailableException' -as [type])) {
    Add-Type -TypeDefinition 'public class KutayHiveUnavailableException : System.Exception { public KutayHiveUnavailableException(string message) : base(message) { } }' -WarningAction SilentlyContinue
}

function Invoke-KutayRegExe([string[]]$Arguments) {
    # Under 'Stop', 5.1 turns reg.exe's error output into a terminating error before the exit code
    # can be read, which would also skip the unload retries.
    $ErrorActionPreference = 'Continue'
    $null = & (Join-Path $env:windir 'System32\reg.exe') @Arguments 2>&1
    $LASTEXITCODE
}

function Get-KutayUserHive {
    $profiles = @(Get-KutayProfile | Where-Object { $_.sid -match $script:UserSidPattern -and $_.path } | ForEach-Object {
            $classes = Join-Path $_.path $script:ClassesFile
            if (-not (Test-Path -LiteralPath $classes)) { $classes = $null }
            [pscustomobject]@{ user = $_.sid; file = Join-Path $_.path 'NTUSER.DAT'; classes = $classes }
        })
    $profiles += [pscustomobject]@{ user = 'default'; file = Join-Path (Get-KutayDefaultProfilePath) 'NTUSER.DAT'; classes = $null }
    $profiles | Where-Object { Test-Path -LiteralPath $_.file }
}

# Which hive a per-user path lives in: Software\Classes\... in the classes hive, the rest in the
# user hive. Returns the path inside that hive.
function Split-KutayUserPath([string]$Path) {
    if ($Path -match $script:ClassesPattern) { return [pscustomobject]@{ classes = $true; path = $Matches[1] } }
    [pscustomobject]@{ classes = $false; path = $Path }
}

# The HKU key a hive file is loaded under, or nothing. hivelist names files by device, not drive
# letter, so the path after the drive is compared.
function Find-KutayLoadedHive([string]$File) {
    $tail = $File -replace '^[A-Za-z]:', ''
    $list = Get-KutayHiveList
    foreach ($name in $list.Keys) {
        if ($name -notlike '\REGISTRY\USER\*') { continue }
        if (($list[$name] -replace '^\\Device\\[^\\]+', '') -eq $tail) { return $name.Substring(15) }
    }
}

function Mount-KutayUserHive {
    param([Parameter(Mandatory)]$Hive, [switch]$Classes)
    $file = $Hive.file
    $root = "HKU\$script:MountPrefix$($Hive.user)"
    if ($Classes) { $file = $Hive.classes; $root = "${root}_Classes" }
    $loaded = Find-KutayLoadedHive $file
    if ($loaded) { return [pscustomobject]@{ root = "HKU\$loaded"; mounted = $false } }

    $code = Invoke-KutayRegExe -Arguments @('load', $root, $file)
    if ($code -ne 0) { throw [KutayHiveUnavailableException]::new("reg load $root from $file failed with exit code $code") }
    [pscustomobject]@{ root = $root; mounted = $true }
}

function Dismount-KutayUserHive {
    param([Parameter(Mandatory)]$Mount)
    if (-not $Mount.mounted) { return }
    for ($i = 1; $i -le $script:UnloadAttempts; $i++) {
        # Registry handles from Get-Item are released by the garbage collector; unload fails while
        # one is still open.
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        if ((Invoke-KutayRegExe -Arguments @('unload', $Mount.root)) -eq 0) { return }
        Start-Sleep -Milliseconds $script:UnloadRetryMilliseconds
    }
    throw "reg unload $($Mount.root) failed after $script:UnloadAttempts attempts"
}

# Runs $Script with the hive's root ('HKU\<key>') and always unloads a hive it loaded. With
# -Classes it opens the classes hive instead, and does nothing for a profile that has none.
function Use-KutayUserHive {
    param([Parameter(Mandatory)]$Hive, [Parameter(Mandatory)][scriptblock]$Script, [switch]$Classes)
    if ($Classes -and -not $Hive.classes) { return }
    $mount = Mount-KutayUserHive $Hive -Classes:$Classes
    try { & $Script $mount.root }
    finally { Dismount-KutayUserHive $mount }
}

Export-ModuleMember -Function Get-KutayUserHive, Split-KutayUserPath, Mount-KutayUserHive, Dismount-KutayUserHive,
    Use-KutayUserHive
