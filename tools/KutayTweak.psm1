#Requires -Version 5.1
# Reads what the playbook YAML does, so host tools (tests, VM smoke runs) can check it without AME.
# Only the one-line flow forms KutayOS writes are understood; anything else is ignored.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:RegistryValuePattern = "!registryValue:\s*\{\s*path:\s*'([^']+)',\s*value:\s*'([^']+)',\s*type:\s*(\w+),\s*data:\s*'([^']*)'"
$script:TaskPattern = "!task:\s*\{\s*path:\s*'([^']+)'"
# A single-quoted YAML scalar: '' inside it stands for one quote.
$script:CommandPattern = "(?m)^\s*command:\s*'((?:[^']|'')*)'\s*$"
# Set-KutayUserSetting.ps1 -Setting 'path|name|type|data','...' (after YAML quote escapes are undone).
$script:UserSettingPattern = "Set-KutayUserSetting\.ps1\b.*?-Setting\s+((?:'[^']*'\s*,?\s*)+)"
$script:SystemStatePattern = 'Set-KutaySystemState\.ps1\b.*?-Kind\s+(\w+)\s+-State\s+(\w+)'
# Set-KutaySystemState.ps1 ... -Name '\Task\One','\Task\Two' (after YAML quote escapes are undone).
$script:SystemNamePattern = "\s-Name\s+((?:'[^']*'\s*,?\s*)+)"
$script:OneWayPattern = '(?m)^\s*# Revert: none\b'
$script:OptionPattern = "(?m)^\s*option:\s*'"
# Types a smoke run can compare as plain text. Add more when a tweak needs them.
$script:CheckableTypes = 'REG_DWORD', 'REG_SZ'

function Get-KutayTweakChange {
    param([Parameter(Mandatory)][string]$Path)
    $id = [IO.Path]::GetFileNameWithoutExtension($Path)
    $text = Get-Content -LiteralPath $Path -Raw
    foreach ($match in [regex]::Matches($text, $script:RegistryValuePattern)) {
        $type = $match.Groups[3].Value
        if ($script:CheckableTypes -notcontains $type) { throw "$id uses $type, which smoke runs can't check yet" }
        [pscustomobject]@{
            id   = $id
            path = $match.Groups[1].Value
            name = $match.Groups[2].Value
            type = $type
            data = $match.Groups[4].Value
        }
    }
}

function Get-KutayTweakCommand {
    param([Parameter(Mandatory)][string]$Path)
    $text = Get-Content -LiteralPath $Path -Raw
    foreach ($match in [regex]::Matches($text, $script:CommandPattern)) { $match.Groups[1].Value -replace "''", "'" }
}

function Get-KutayTweakUserChange {
    param([Parameter(Mandatory)][string]$Path)
    $id = [IO.Path]::GetFileNameWithoutExtension($Path)
    foreach ($command in @(Get-KutayTweakCommand -Path $Path)) {
        if ($command -notmatch $script:UserSettingPattern) { continue }
        foreach ($quoted in [regex]::Matches($Matches[1], "'([^']*)'")) {
            $settingPath, $name, $type, $data = $quoted.Groups[1].Value -split '\|', 4
            [pscustomobject]@{ id = $id; path = $settingPath; name = $name; type = $type; data = $data }
        }
    }
}

function Get-KutayTweakSystemChange {
    param([Parameter(Mandatory)][string]$Path)
    $id = [IO.Path]::GetFileNameWithoutExtension($Path)
    foreach ($command in @(Get-KutayTweakCommand -Path $Path)) {
        if ($command -notmatch $script:SystemStatePattern) { continue }
        $kind = $Matches[1]
        $state = $Matches[2]
        $names = @('')
        if ($command -match $script:SystemNamePattern) {
            $names = @([regex]::Matches($Matches[1], "'([^']*)'") | ForEach-Object { $_.Groups[1].Value })
        }
        foreach ($name in $names) { [pscustomobject]@{ id = $id; kind = $kind; state = $state; name = $name } }
    }
}

# A one-way tweak (its revert line says "none") keeps no snapshot.
function Test-KutayTweakOneWay {
    param([Parameter(Mandatory)][string]$Path)
    (Get-Content -LiteralPath $Path -Raw) -match $script:OneWayPattern
}

# A tweak behind a FeaturePages checkbox: its actions carry option: '<name>'.
function Test-KutayTweakOption {
    param([Parameter(Mandatory)][string]$Path)
    (Get-Content -LiteralPath $Path -Raw) -match $script:OptionPattern
}

function Get-KutayTaskPath {
    param([Parameter(Mandatory)][string]$Path)
    $text = Get-Content -LiteralPath $Path -Raw
    foreach ($match in [regex]::Matches($text, $script:TaskPattern)) { $match.Groups[1].Value }
}

Export-ModuleMember -Function Get-KutayTweakChange, Get-KutayTweakUserChange, Get-KutayTweakSystemChange,
    Test-KutayTweakOneWay, Test-KutayTweakOption, Get-KutayTweakCommand, Get-KutayTaskPath
