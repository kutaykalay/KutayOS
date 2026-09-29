#Requires -Version 5.1
# Snapshots of the state KutayOS changes, so every change can be put back.
# One JSON file per tweak id under %windir%\KutayOS\State. The first snapshot wins: running a tweak
# twice must not record KutayOS's own value as the original.

Set-StrictMode -Version 2.0
# Modules don't inherit the caller's preference. A non-terminating registry error must stop a
# revert, or the snapshot would be deleted although the value was never put back.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'KutayUserHive.psm1')

$script:StateRoot = Join-Path $env:windir 'KutayOS\State'
$script:IdPattern = '^[a-z0-9]+(-[a-z0-9]+)*$'
$script:Hives = @{
    HKLM = 'HKEY_LOCAL_MACHINE'
    HKCU = 'HKEY_CURRENT_USER'
    HKU  = 'HKEY_USERS'
    HKCR = 'HKEY_CLASSES_ROOT'
}
# Per-user settings a tweak can write. Add more when a tweak needs them.
$script:UserTypes = 'DWord', 'String'
$script:DefaultValueName = '(default)'

function ConvertTo-KutayProviderPath([string]$Path) {
    $hive, $rest = $Path -split '\\', 2
    if (-not $script:Hives.ContainsKey($hive)) { throw "Unknown registry hive in '$Path'" }
    "Registry::$($script:Hives[$hive])\$rest"
}

function Get-SnapshotFile([string]$Id) {
    if ($Id -cnotmatch $script:IdPattern) { throw "Invalid snapshot id '$Id' (use lowercase letters, digits and hyphens)" }
    Join-Path $script:StateRoot "$Id.json"
}

function Split-RegistryItem([string]$Item) {
    $path, $name = $Item -split '\|', 2
    if (-not $path -or -not $name) { throw "Registry item '$Item' must look like 'path|name'" }
    [pscustomobject]@{ path = $path; name = $name }
}

# The registry provider cmdlets call a key's default value '(default)'; RegistryKey methods call it ''.
function Get-KeyValueName([string]$Name) {
    if ($Name -eq $script:DefaultValueName) { return '' }
    $Name
}

function Read-KutayRegistryValue {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    $key = Get-Item -LiteralPath (ConvertTo-KutayProviderPath $Path) -ErrorAction SilentlyContinue
    $valueName = Get-KeyValueName $Name
    if (-not $key -or $key.GetValueNames() -notcontains $valueName) {
        return [pscustomobject]@{ exists = $false; type = $null; data = $null }
    }
    $type = $key.GetValueKind($valueName).ToString()
    $data = $key.GetValue($valueName, $null, 'DoNotExpandEnvironmentNames')
    if ($type -eq 'Binary') { $data = [Convert]::ToBase64String($data) }
    [pscustomobject]@{ exists = $true; type = $type; data = $data }
}

function Set-KutayRegistryValue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'QWord', 'MultiString')]
        [string]$Type,
        [AllowEmptyString()][AllowEmptyCollection()]$Data
    )
    $key = ConvertTo-KutayProviderPath $Path
    if (-not $PSCmdlet.ShouldProcess("$Path\$Name", "Set $Type value")) { return }
    # New-Item -Force on an existing key wipes its values, so only create a missing key.
    if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force -ErrorAction Stop | Out-Null }
    # Plain assignments: a switch would unroll these arrays into object[] through the pipeline.
    $value = $Data
    if ($Type -eq 'Binary') { [byte[]]$value = [Convert]::FromBase64String($Data) }
    if ($Type -eq 'MultiString') { [string[]]$value = @($Data) }
    New-ItemProperty -LiteralPath $key -Name $Name -PropertyType $Type -Value $value -Force -ErrorAction Stop | Out-Null
}

function Remove-KutayRegistryValue {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    $key = ConvertTo-KutayProviderPath $Path
    $item = Get-Item -LiteralPath $key -ErrorAction SilentlyContinue
    if ($item -and $item.GetValueNames() -contains (Get-KeyValueName $Name) -and $PSCmdlet.ShouldProcess("$Path\$Name", 'Remove value')) {
        Remove-ItemProperty -LiteralPath $key -Name $Name -ErrorAction Stop
    }
}

function Save-KutaySnapshot {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Id,
        [Parameter(Mandatory)][string[]]$Registry
    )
    $file = Get-SnapshotFile $Id
    $items = @($Registry | ForEach-Object { Split-RegistryItem $_ })
    if (Test-Path -LiteralPath $file) { return }

    $values = @($items | ForEach-Object {
            $current = Read-KutayRegistryValue -Path $_.path -Name $_.name
            [ordered]@{ path = $_.path; name = $_.name; exists = $current.exists; type = $current.type; data = $current.data }
        })
    Write-SnapshotFile $file ([ordered]@{ id = $Id; createdAt = (Get-Date).ToString('s'); registry = $values })
}

function Write-SnapshotFile([string]$File, $Snapshot) {
    New-Item -ItemType Directory -Force -Path $script:StateRoot | Out-Null
    [IO.File]::WriteAllText($File, (ConvertTo-Json -InputObject $Snapshot -Depth 5))
}

# A per-user item names a path inside the user hive ('Software\...'); the hive comes from the user.
function Split-UserRegistryItem([string]$Item) {
    $parsed = Split-RegistryItem $Item
    if ($parsed.path -match '^(HK|Registry::)') { throw "User registry item '$Item' must use a path relative to the user hive" }
    $parsed
}

function Split-UserSetting([string]$Setting) {
    $path, $name, $type, $data = $Setting -split '\|', 4
    if ($null -eq $data -or -not $type) { throw "User setting '$Setting' must look like 'path|name|type|data'" }
    if ($script:UserTypes -notcontains $type) { throw "User setting '$Setting' uses type $type; allowed: $($script:UserTypes -join ', ')" }
    $item = Split-UserRegistryItem "$path|$name"
    [pscustomobject]@{ path = $item.path; name = $item.name; type = $type; data = $data }
}

function Save-KutayUserSnapshot {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Id,
        [Parameter(Mandatory)][string[]]$Registry
    )
    $file = Get-SnapshotFile $Id
    $items = @($Registry | ForEach-Object { Split-UserRegistryItem $_ })

    # The first snapshot of a value wins. A later run only adds users it doesn't know yet (an account
    # created since, or one an earlier run could not reach), so revert covers them too.
    $snapshot = [ordered]@{ id = $Id; createdAt = (Get-Date).ToString('s'); registry = @(); users = @() }
    if (Test-Path -LiteralPath $file) {
        $existing = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
        $snapshot = [ordered]@{ id = $existing.id; createdAt = $existing.createdAt; registry = @($existing.registry); users = @() }
        if ($existing.PSObject.Properties['users']) { $snapshot.users = @($existing.users) }
    }
    $recorded = Get-SnapshotUserKey $snapshot.users

    $values = New-Object System.Collections.Generic.List[object]
    foreach ($hive in @(Get-KutayUserHive)) {
        $missing = @($items | Where-Object { -not $recorded.ContainsKey("$($hive.user)|$($_.path)|$($_.name)") })
        if (-not $missing.Count) { continue }
        $read = Invoke-KutayUserHiveItem -Hive $hive -Items $missing -Action {
            param($Item, $Root, $Inner)
            $current = Read-KutayRegistryValue -Path "$Root\$Inner" -Name $Item.name
            # Keys KutayOS creates must go again on revert: an empty CLSID key still changes Explorer.
            $createdKey = $null
            $missing = Find-KutayMissingKey -Root $Root -Inner $Inner
            if ($missing) { $createdKey = $Item.path.Substring(0, $Item.path.Length - $Inner.Length) + $missing }
            [ordered]@{
                user = $hive.user; path = $Item.path; name = $Item.name
                exists = $current.exists; type = $current.type; data = $current.data; createdKey = $createdKey
            }
        }
        foreach ($value in @($read)) { $values.Add($value) }
    }
    if ((Test-Path -LiteralPath $file) -and -not $values.Count) { return }
    $snapshot.users = @($snapshot.users) + $values.ToArray()
    Write-SnapshotFile $file $snapshot
}

# 'user|path|name' of every user entry in a snapshot.
function Get-SnapshotUserKey([object[]]$Users) {
    $keys = @{}
    foreach ($entry in $Users) { $keys["$($entry.user)|$($entry.path)|$($entry.name)"] = $true }
    $keys
}

# Invoke-KutayUserItem for one hive, but a hive that can't be opened is skipped with a warning, so one
# locked profile doesn't stop the playbook for every other account.
function Invoke-KutayUserHiveItem($Hive, [object[]]$Items, [scriptblock]$Action) {
    try {
        Invoke-KutayUserItem -Hive $Hive -Items $Items -Action $Action
    } catch [KutayHiveUnavailableException] {
        Write-Warning "Profile $($Hive.user) skipped: $($_.Exception.Message)"
    }
}

# Snapshots, then writes each setting to every user hive, including the default profile.
function Set-KutayUserSetting {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string[]]$Setting
    )
    $settings = @($Setting | ForEach-Object { Split-UserSetting $_ })
    if (-not $PSCmdlet.ShouldProcess($Id, 'Write user settings to every user hive')) { return }
    Save-KutayUserSnapshot -Id $Id -Registry @($settings | ForEach-Object { "$($_.path)|$($_.name)" })
    # Only values whose original is on disk may change, or revert could not put them back.
    $recorded = Get-SnapshotUserKey @((Get-Content -LiteralPath (Get-SnapshotFile $Id) -Raw | ConvertFrom-Json).users)
    foreach ($hive in @(Get-KutayUserHive)) {
        $safe = @($settings | Where-Object { $recorded.ContainsKey("$($hive.user)|$($_.path)|$($_.name)") })
        if (-not $safe.Count) { continue }
        Invoke-KutayUserHiveItem -Hive $hive -Items $safe -Action {
            param($Item, $Root, $Inner)
            Set-KutayRegistryValue -Path "$Root\$Inner" -Name $Item.name -Type $Item.type -Data $Item.data
        } | Out-Null
    }
}

# Runs $Action with each item, the root of the hive part it lives in and its path inside that part
# (Software\Classes paths live in the classes hive). Classes items are skipped for a hive without one.
function Invoke-KutayUserItem($Hive, [object[]]$Items, [scriptblock]$Action) {
    foreach ($classes in $false, $true) {
        $part = @($Items | Where-Object { (Split-KutayUserPath $_.path).classes -eq $classes })
        if (-not $part.Count) { continue }
        Use-KutayUserHive -Hive $Hive -Classes:$classes -Script {
            param($Root)
            foreach ($one in $part) { & $Action $one $Root (Split-KutayUserPath $one.path).path }
        }
    }
}

function Test-KutayRegistryKey([string]$Path) { Test-Path -LiteralPath (ConvertTo-KutayProviderPath $Path) }

# The first key of $Inner (a path under $Root) that doesn't exist, relative to $Root; $null if all do.
function Find-KutayMissingKey([string]$Root, [string]$Inner) {
    $parts = @($Inner -split '\\')
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $relative = $parts[0..$i] -join '\'
        if (-not (Test-KutayRegistryKey "$Root\$relative")) { return $relative }
    }
}

# Removes $Path and its parents while they hold no values and no subkeys, never going above $StopAt.
function Remove-KutayEmptyKey {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$StopAt)
    if ($Path -ne $StopAt -and -not $Path.StartsWith("$StopAt\", [StringComparison]::OrdinalIgnoreCase)) {
        throw "StopAt '$StopAt' is not '$Path' or one of its parents"
    }
    $current = $Path
    while ($true) {
        $provider = ConvertTo-KutayProviderPath $current
        $key = Get-Item -LiteralPath $provider -ErrorAction SilentlyContinue
        if ($key) {
            if (@($key.GetValueNames()).Count -or $key.SubKeyCount) { return }
            if ($PSCmdlet.ShouldProcess($current, 'Remove empty key')) { Remove-Item -LiteralPath $provider -ErrorAction Stop }
        }
        if ($current -eq $StopAt) { return }
        $current = $current.Substring(0, $current.LastIndexOf('\'))
    }
}

function Restore-KutayRegistryItem([string]$Path, $Item) {
    if ($Item.exists) {
        Set-KutayRegistryValue -Path $Path -Name $Item.name -Type $Item.type -Data $Item.data
    } else {
        Remove-KutayRegistryValue -Path $Path -Name $Item.name
    }
}

function Restore-KutayUserItem([object[]]$Items) {
    $hives = @(Get-KutayUserHive)
    foreach ($group in @($Items | Group-Object -Property user)) {
        $hive = @($hives | Where-Object { $_.user -eq $group.Name }) | Select-Object -First 1
        if (-not $hive) {
            # The account was deleted after KutayOS ran: there is nothing left to put back.
            Write-Warning "Profile $($group.Name) no longer exists; its values were skipped"
            continue
        }
        Invoke-KutayUserItem -Hive $hive -Items @($group.Group) -Action {
            param($Item, $Root, $Inner)
            Restore-KutayRegistryItem "$Root\$Inner" $Item
            # Snapshots from before key tracking have no createdKey.
            $created = $null
            if ($Item.PSObject.Properties['createdKey']) { $created = $Item.createdKey }
            if (-not $Item.exists -and $created) {
                Remove-KutayEmptyKey -Path "$Root\$Inner" -StopAt "$Root\$((Split-KutayUserPath $created).path)"
            }
        } | Out-Null
    }
}

function Restore-KutaySnapshot {
    param([Parameter(Mandatory)][string]$Id)
    $file = Get-SnapshotFile $Id
    if (-not (Test-Path -LiteralPath $file)) { return }

    $snapshot = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
    foreach ($item in @($snapshot.registry)) { Restore-KutayRegistryItem $item.path $item }
    # Snapshots from before per-user support have no users list.
    if ($snapshot.PSObject.Properties['users'] -and @($snapshot.users).Count) { Restore-KutayUserItem @($snapshot.users) }
    # Only forget the snapshot once every value is back, so a failed revert can be retried.
    Remove-Item -LiteralPath $file
}

function Get-KutaySnapshotId {
    if (-not (Test-Path -LiteralPath $script:StateRoot)) { return }
    Get-ChildItem -LiteralPath $script:StateRoot -Filter *.json | Sort-Object Name | ForEach-Object { $_.BaseName }
}

Export-ModuleMember -Function Save-KutaySnapshot, Save-KutayUserSnapshot, Set-KutayUserSetting,
    Restore-KutaySnapshot, Get-KutaySnapshotId,
    Read-KutayRegistryValue, Set-KutayRegistryValue, Remove-KutayRegistryValue, Remove-KutayEmptyKey
