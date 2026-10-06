<#
.SYNOPSIS
    Compares measure-baseline.ps1 runs: averages of the "before" and "after" runs, plus which running
    services and processes differ (from the .inventory.json files next to them).
.EXAMPLE
    powershell -NoProfile -File tools/vm/Compare-Baseline.ps1 -Before docs/measurements/slice5/clean-nologon-*.json -After docs/measurements/slice5/applied-nologon-*.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$Before,
    [Parameter(Mandatory)][string[]]$After
)
$ErrorActionPreference = 'Stop'
$metrics = 'cpuIdleAvgPct', 'ramUsedMB', 'commitMB', 'processCount', 'runningServices', 'quietWaitMin'

function Get-RunFile([string[]]$Pattern) {
    @($Pattern | ForEach-Object { Get-ChildItem -Path $_ } | Where-Object { $_.Name -notlike '*.inventory.json' })
}

function Get-Average([object[]]$Runs, [string]$Name) {
    # A missing value would count as 0 and shift the average without a sign.
    $values = @($Runs | ForEach-Object {
            if ($null -eq $_.$Name) { throw "A run has no $Name (collected $($_.collectedAt))" }
            [double]$_.$Name
        })
    [math]::Round(($values | Measure-Object -Average).Average, 1)
}

# Names seen in every run of a group, so a one-off process doesn't count as a difference.
function Get-StableName([object[]]$Inventories, [scriptblock]$Select) {
    $sets = @($Inventories | ForEach-Object { , @(& $Select $_ | Sort-Object -Unique) })
    if (-not $sets.Count) { return @() }
    @($sets[0] | Where-Object { $name = $_; @($sets | Where-Object { $_ -contains $name }).Count -eq $sets.Count })
}

function Read-Group([string[]]$Pattern) {
    $files = Get-RunFile $Pattern
    if (-not $files.Count) { throw "No runs match $($Pattern -join ', ')" }
    $runs = @($files | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json })
    $inventories = @($files | ForEach-Object {
            $inventory = [IO.Path]::ChangeExtension($_.FullName, '.inventory.json')
            # Without it the stable-name sets would cover fewer runs than the averages.
            if (-not (Test-Path -LiteralPath $inventory)) { throw "Missing $inventory" }
            Get-Content -LiteralPath $inventory -Raw | ConvertFrom-Json
        })
    [pscustomobject]@{ Files = $files; Runs = $runs; Inventories = $inventories }
}

$groups = [ordered]@{ before = Read-Group $Before; after = Read-Group $After }
foreach ($name in $groups.Keys) {
    $g = $groups[$name]
    $quiet = @($g.Runs | Where-Object { -not $_.quietReached }).Count
    "$name : $($g.Files.Count) runs ($($g.Files.Name -join ', ')); runs that never got quiet: $quiet"
}
''
'{0,-16} {1,10} {2,10} {3,10}' -f 'metric', 'before', 'after', 'change'
foreach ($metric in $metrics) {
    $b = Get-Average $groups.before.Runs $metric
    $a = Get-Average $groups.after.Runs $metric
    '{0,-16} {1,10} {2,10} {3,10}' -f $metric, $b, $a, [math]::Round($a - $b, 1)
}

$select = @{
    services  = { param($i) @($i.runningServices | ForEach-Object { $_.name }) }
    processes = { param($i) @($i.processes | ForEach-Object { $_.name }) }
}
foreach ($kind in 'services', 'processes') {
    $b = Get-StableName $groups.before.Inventories $select[$kind]
    $a = Get-StableName $groups.after.Inventories $select[$kind]
    ''
    "$kind only before: $(@($b | Where-Object { $a -notcontains $_ }) -join ', ')"
    "$kind only after:  $(@($a | Where-Object { $b -notcontains $_ }) -join ', ')"
}
