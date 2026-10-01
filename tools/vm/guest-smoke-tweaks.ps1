<#
Guest side of Invoke-TweakSmoke.ps1. Runs inside the test VM, never on the dev host.
Applies every tweak from manifest.json twice the way AME would (the commands, then the registry
values), checks the values and snapshots (per-user values in every user hive and the default
profile), reverts everything with Revert-KutayOS.ps1 -All and
checks that every value is back. Writes PASS/FAIL lines to result.txt; the host decides the verdict.
vmrun appends a blank argument, so remaining arguments are accepted and ignored.
#>
param([Parameter(ValueFromRemainingArguments)][object[]]$Rest)
$null = $Rest
$ErrorActionPreference = 'Stop'

$root = 'C:\Users\Public\KutaySmoke'
$executables = Join-Path $root 'Executables'
$stateRoot = Join-Path $env:windir 'KutayOS\State'
$revertScript = Join-Path $env:windir 'KutayOS\KutayDesktop\Revert-KutayOS.ps1'
$results = New-Object System.Collections.Generic.List[string]
$script:SystemStates = @{
    Hibernation     = 'On', 'Off'
    CompactOS       = 'Always', 'Never'
    ReservedStorage = 'Enabled', 'Disabled'
}

function Add-Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    $verdict = 'FAIL'
    if ($Ok) { $verdict = 'PASS' }
    $line = "$verdict $Name"
    if ($Detail) { $line = "$line ($Detail)" }
    $results.Add($line)
}

function Get-ProviderPath([string]$Path) {
    'Registry::' + ($Path -replace '^HKLM\\', 'HKEY_LOCAL_MACHINE\' -replace '^HKU\\', 'HKEY_USERS\')
}

# Per-user values in every user hive, keyed 'user|path|name'; $null where a value doesn't exist.
# Software\Classes paths are read from the classes hive; a hive without one has no entry.
function Read-UserValue([object[]]$Changes) {
    $values = @{}
    foreach ($hive in @(Get-KutayUserHive)) {
        foreach ($change in $Changes) {
            $split = Split-KutayUserPath $change.path
            Use-KutayUserHive -Hive $hive -Classes:$split.classes -Script {
                param($HiveRoot)
                $values["$($hive.user)|$($change.path)|$($change.name)"] = Read-Value "$HiveRoot\$($split.path)" $change.name
            } | Out-Null
        }
    }
    $values
}

# Whether the key of each per-user change exists in every user hive, keyed 'user|path'.
function Read-UserKey([object[]]$Changes) {
    $keys = @{}
    foreach ($hive in @(Get-KutayUserHive)) {
        foreach ($change in $Changes) {
            $split = Split-KutayUserPath $change.path
            Use-KutayUserHive -Hive $hive -Classes:$split.classes -Script {
                param($HiveRoot)
                $keys["$($hive.user)|$($change.path)"] = Test-Path -LiteralPath (Get-ProviderPath "$HiveRoot\$($split.path)")
            } | Out-Null
        }
    }
    $keys
}

# The value as text, or $null when it doesn't exist. '(default)' is the key's default value.
function Read-Value([string]$Path, [string]$Name) {
    if ($Name -eq '(default)') { $Name = '' }
    $key = Get-Item -LiteralPath (Get-ProviderPath $Path) -ErrorAction SilentlyContinue
    if (-not $key -or $key.GetValueNames() -notcontains $Name) { return $null }
    [string]$key.GetValue($Name)
}

# What AME's !registryValue does for the types KutayTweak.psm1 lets through.
function Write-RegistryValue($Change) {
    $key = Get-ProviderPath $Change.path
    if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
    $type = 'String'
    if ($Change.type -eq 'REG_DWORD') { $type = 'DWord' }
    New-ItemProperty -LiteralPath $key -Name $Change.name -PropertyType $type -Value $Change.data -Force | Out-Null
}

function Invoke-Native([string]$What, [string[]]$Arguments) {
    & "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass @Arguments | Out-Null
    Add-Check $What ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
}

function Get-FreeSpace { (Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace }

# Puts each system kind a tweak sets into the other state first, so the tweak really changes it and
# revert has something to put back. A kind the VM can't change (hibernation: no firmware support) is
# noted and checked as it is.
function Initialize-SystemState([object[]]$Changes) {
    foreach ($change in $Changes) {
        if ((Get-KutaySystemState -Kind $change.kind) -ne $change.state) { continue }
        $other = @($script:SystemStates[$change.kind] | Where-Object { $_ -ne $change.state })[0]
        try {
            Set-KutaySystemState -Kind $change.kind -State $other
            $results.Add("INFO prepared $($change.kind)=$other")
        } catch {
            $results.Add("INFO could not prepare $($change.kind)=${other}: $($_.Exception.Message)")
        }
    }
}

function Invoke-TweakPass([object[]]$Tweaks, [int]$Pass) {
    Push-Location $executables
    try {
        foreach ($tweak in $Tweaks) {
            $free = Get-FreeSpace
            foreach ($command in @($tweak.commands)) { Invoke-Native "pass $Pass $($tweak.id) command" @('-Command', $command) }
            if ($Pass -eq 1) { $results.Add("INFO $($tweak.id) freed $([math]::Round(((Get-FreeSpace) - $free) / 1MB)) MB") }
            foreach ($change in @($tweak.system)) {
                $now = Get-KutaySystemState -Kind $change.kind
                Add-Check "pass $Pass $($tweak.id) $($change.kind)=$($change.state)" ($now -eq $change.state) "read '$now'"
            }
            foreach ($change in @($tweak.changes)) {
                Write-RegistryValue $change
                $now = Read-Value $change.path $change.name
                Add-Check "pass $Pass $($tweak.id) $($change.name)=$($change.data)" ($now -eq $change.data) "read '$now'"
            }
            $userChanges = @($tweak.userChanges)
            if (-not $userChanges.Count) { continue }
            $now = Read-UserValue $userChanges
            foreach ($key in @($now.Keys | Sort-Object)) {
                $user, $path, $name = $key -split '\|', 3
                $want = @($userChanges | Where-Object { $_.path -eq $path -and $_.name -eq $name })[0].data
                Add-Check "pass $Pass $($tweak.id) $user $name=$want" ($now[$key] -eq $want) "read '$($now[$key])'"
            }
        }
    } finally { Pop-Location }
}

# Checks that a tweak's snapshot has every user hive's original value of every per-user change.
function Test-UserSnapshot($Tweak, $Snapshot, [hashtable]$Original) {
    $users = @()
    if ($Snapshot.PSObject.Properties['users']) { $users = @($Snapshot.users) }
    foreach ($change in @($Tweak.userChanges)) {
        foreach ($key in @($Original.Keys | Where-Object { $_ -like "*|$($change.path)|$($change.name)" })) {
            $user = ($key -split '\|', 2)[0]
            $entry = @($users | Where-Object { $_.user -eq $user -and $_.path -eq $change.path -and $_.name -eq $change.name })
            if (-not $entry.Count) { Add-Check "$($Tweak.id) snapshot covers $user $($change.name)" $false; continue }
            $recorded = $null
            if ($entry[0].exists) { $recorded = [string]$entry[0].data }
            Add-Check "$($Tweak.id) snapshot holds original $user $($change.name)" ($recorded -eq $Original[$key]) "original '$($Original[$key])', recorded '$recorded'"
        }
    }
}

function Read-Snapshot([string]$Id) {
    $file = Join-Path $stateRoot "$Id.json"
    if (Test-Path -LiteralPath $file) { return Get-Content -LiteralPath $file -Raw }
    $null
}

try {
    # 5.1's ConvertFrom-Json emits the whole array as one pipeline object; assign first, then wrap.
    $parsed = Get-Content -LiteralPath (Join-Path $root 'manifest.json') -Raw | ConvertFrom-Json
    $tweaks = @($parsed)
    Invoke-Native 'Initialize-Kutay' @('-File', (Join-Path $executables 'KutayModules\Initialize-Kutay.ps1'))

    $original = @{}
    foreach ($change in @($tweaks | ForEach-Object { @($_.changes) })) {
        $original["$($change.path)|$($change.name)"] = Read-Value $change.path $change.name
    }
    Import-Module (Join-Path $executables 'KutayModules\KutayUserHive.psm1')
    Import-Module (Join-Path $executables 'KutayModules\KutaySystemState.psm1')
    $allSystemChanges = @($tweaks | ForEach-Object { @($_.system) })
    Initialize-SystemState $allSystemChanges
    $systemOriginal = @{}
    foreach ($change in $allSystemChanges) { $systemOriginal[$change.kind] = Get-KutaySystemState -Kind $change.kind }
    $results.Add("INFO free before $([math]::Round((Get-FreeSpace) / 1MB)) MB")
    $hiveUsers = @(Get-KutayUserHive | ForEach-Object { $_.user })
    # At least the signed-in guest user and the default profile, or per-user checks prove nothing.
    Add-Check 'user hives found' ($hiveUsers.Count -ge 2) ($hiveUsers -join ', ')
    $allUserChanges = @($tweaks | ForEach-Object { @($_.userChanges) })
    $userOriginal = @{}
    $keyOriginal = @{}
    if ($allUserChanges.Count) {
        $userOriginal = Read-UserValue $allUserChanges
        $keyOriginal = Read-UserKey $allUserChanges
    }

    Invoke-TweakPass $tweaks 1
    $firstSnapshots = @{}
    foreach ($tweak in $tweaks) {
        $json = Read-Snapshot $tweak.id
        $firstSnapshots[$tweak.id] = $json
        if ($tweak.oneWay) { Add-Check "$($tweak.id) one-way, no snapshot" (-not $json); continue }
        if (-not $json) { Add-Check "$($tweak.id) snapshot exists" $false; continue }
        $snapshot = $json | ConvertFrom-Json
        Test-UserSnapshot $tweak $snapshot $userOriginal
        foreach ($change in @($tweak.system)) {
            $entry = @(@($snapshot.PSObject.Properties['system'] | ForEach-Object { $_.Value }) | Where-Object { $_.kind -eq $change.kind })
            $recorded = $null
            if ($entry.Count) { $recorded = $entry[0].state }
            $was = $systemOriginal[$change.kind]
            Add-Check "$($tweak.id) snapshot holds original $($change.kind)" ($recorded -eq $was) "original '$was', recorded '$recorded'"
        }
        $items = @($snapshot.registry)
        foreach ($change in @($tweak.changes)) {
            $covered = @($items | Where-Object { $_.path -eq $change.path -and $_.name -eq $change.name }).Count -gt 0
            Add-Check "$($tweak.id) snapshot covers $($change.name)" $covered
        }
        foreach ($item in $items) {
            $was = $original["$($item.path)|$($item.name)"]
            $recorded = $null
            if ($item.exists) { $recorded = [string]$item.data }
            Add-Check "$($tweak.id) snapshot holds original $($item.name)" ($recorded -eq $was) "original '$was', recorded '$recorded'"
        }
    }

    $results.Add("INFO free after pass 1 $([math]::Round((Get-FreeSpace) / 1MB)) MB")
    Invoke-TweakPass $tweaks 2
    foreach ($tweak in $tweaks) {
        Add-Check "$($tweak.id) snapshot kept on second run" ((Read-Snapshot $tweak.id) -eq $firstSnapshots[$tweak.id])
    }

    Invoke-Native 'Revert-KutayOS -All' @('-File', $revertScript, '-All')
    foreach ($key in $original.Keys) {
        $path, $name = $key -split '\|', 2
        $now = Read-Value $path $name
        Add-Check "reverted $name" ($now -eq $original[$key]) "original '$($original[$key])', now '$now'"
    }
    foreach ($kind in @($systemOriginal.Keys | Sort-Object)) {
        $now = Get-KutaySystemState -Kind $kind
        Add-Check "reverted $kind" ($now -eq $systemOriginal[$kind]) "original '$($systemOriginal[$kind])', now '$now'"
    }
    if ($allUserChanges.Count) {
        $userNow = Read-UserValue $allUserChanges
        foreach ($key in @($userOriginal.Keys | Sort-Object)) {
            Add-Check "reverted $key" ($userNow[$key] -eq $userOriginal[$key]) "original '$($userOriginal[$key])', now '$($userNow[$key])'"
        }
        # A key KutayOS created must be gone again, or an empty CLSID key keeps changing Explorer.
        $keyNow = Read-UserKey $allUserChanges
        foreach ($key in @($keyOriginal.Keys | Sort-Object)) {
            Add-Check "key restored $key" ($keyNow[$key] -eq $keyOriginal[$key]) "existed '$($keyOriginal[$key])', now '$($keyNow[$key])'"
        }
    }
    $left = @(Get-ChildItem -LiteralPath $stateRoot -Filter *.json -ErrorAction SilentlyContinue)
    Add-Check 'no snapshots left after revert' ($left.Count -eq 0) "$($left.Count) left"
    Invoke-Native 'Revert-KutayOS -All again' @('-File', $revertScript, '-All')
} catch {
    Add-Check 'smoke run finished' $false $_.Exception.Message
}

$results | Set-Content -LiteralPath (Join-Path $root 'result.txt') -Encoding ASCII
exit 0
