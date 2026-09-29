#Requires -Version 5.1
# Reads what the playbook YAML does, so host tools (tests, VM smoke runs) can check it without AME.
# Only the one-line flow forms KutayOS writes are understood; anything else is ignored.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:RegistryValuePattern = "!registryValue:\s*\{\s*path:\s*'([^']+)',\s*value:\s*'([^']+)',\s*type:\s*(\w+),\s*data:\s*'([^']*)'"
$script:TaskPattern = "!task:\s*\{\s*path:\s*'([^']+)'"
# A single-quoted YAML scalar: '' inside it stands for one quote.
$script:CommandPattern = "(?m)^\s*command:\s*'((?:[^']|'')*)'\s*$"
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

function Get-KutayTaskPath {
    param([Parameter(Mandatory)][string]$Path)
    $text = Get-Content -LiteralPath $Path -Raw
    foreach ($match in [regex]::Matches($text, $script:TaskPattern)) { $match.Groups[1].Value }
}

Export-ModuleMember -Function Get-KutayTweakChange, Get-KutayTweakCommand, Get-KutayTaskPath
