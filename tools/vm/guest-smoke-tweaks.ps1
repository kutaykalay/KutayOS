<#
Guest side of Invoke-TweakSmoke.ps1. Runs inside the test VM, never on the dev host.
Applies every tweak from manifest.json twice the way AME would (snapshot command, then the registry
values), checks the values and snapshots, reverts everything with Revert-KutayOS.ps1 -All and
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

function Add-Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    $verdict = 'FAIL'
    if ($Ok) { $verdict = 'PASS' }
    $line = "$verdict $Name"
    if ($Detail) { $line = "$line ($Detail)" }
    $results.Add($line)
}

function Get-ProviderPath([string]$Path) { 'Registry::' + ($Path -replace '^HKLM\\', 'HKEY_LOCAL_MACHINE\') }

# The value as text, or $null when it doesn't exist.
function Read-Value([string]$Path, [string]$Name) {
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

function Invoke-TweakPass([object[]]$Tweaks, [int]$Pass) {
    Push-Location $executables
    try {
        foreach ($tweak in $Tweaks) {
            foreach ($command in @($tweak.commands)) { Invoke-Native "pass $Pass $($tweak.id) command" @('-Command', $command) }
            foreach ($change in @($tweak.changes)) {
                Write-RegistryValue $change
                $now = Read-Value $change.path $change.name
                Add-Check "pass $Pass $($tweak.id) $($change.name)=$($change.data)" ($now -eq $change.data) "read '$now'"
            }
        }
    } finally { Pop-Location }
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

    Invoke-TweakPass $tweaks 1
    $firstSnapshots = @{}
    foreach ($tweak in $tweaks) {
        $json = Read-Snapshot $tweak.id
        $firstSnapshots[$tweak.id] = $json
        if (-not $json) { Add-Check "$($tweak.id) snapshot exists" $false; continue }
        $items = @(($json | ConvertFrom-Json).registry)
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
    $left = @(Get-ChildItem -LiteralPath $stateRoot -Filter *.json -ErrorAction SilentlyContinue)
    Add-Check 'no snapshots left after revert' ($left.Count -eq 0) "$($left.Count) left"
    Invoke-Native 'Revert-KutayOS -All again' @('-File', $revertScript, '-All')
} catch {
    Add-Check 'smoke run finished' $false $_.Exception.Message
}

$results | Set-Content -LiteralPath (Join-Path $root 'result.txt') -Encoding ASCII
exit 0
