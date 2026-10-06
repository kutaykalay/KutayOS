<#
Runs inside the test VM after a real AME run of KutayOS, never on the dev host.
Copies every snapshot in %windir%\KutayOS\State aside, runs Revert-KutayOS.ps1 -All, then compares
each saved snapshot with the current state (Compare-KutaySnapshot). PRD success criterion: revert-all
brings every snapshotted value back. Writes PASS/FAIL lines to result.txt; exit code 1 on any FAIL.
vmrun appends a blank argument, so remaining arguments are accepted and ignored.
#>
param([Parameter(ValueFromRemainingArguments)][object[]]$Rest)
$null = $Rest
$ErrorActionPreference = 'Stop'

$root = 'C:\Users\Public\KutayRevertCheck'
$saved = Join-Path $root 'snapshots'
$resultFile = Join-Path $root 'result.txt'
$kutay = Join-Path $env:windir 'KutayOS'
$stateRoot = Join-Path $kutay 'State'
$revertScript = Join-Path $kutay 'KutayDesktop\Revert-KutayOS.ps1'
$results = New-Object System.Collections.Generic.List[string]

function Add-Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    $verdict = 'FAIL'
    if ($Ok) { $verdict = 'PASS' }
    $line = "$verdict $Name"
    if ($Detail) { $line = "$line ($Detail)" }
    $results.Add($line)
}

try {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $saved | Out-Null

    $snapshots = @(Get-ChildItem -LiteralPath $stateRoot -Filter *.json -ErrorAction SilentlyContinue)
    Add-Check 'snapshots present after the AME run' ($snapshots.Count -gt 0) "$($snapshots.Count) files"
    $snapshots | Copy-Item -Destination $saved

    # 5.1 turns redirected stderr into a terminating error under 'Stop'; keep the lines as output.
    $ErrorActionPreference = 'Continue'
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $revertScript -All 2>&1
    $ErrorActionPreference = 'Stop'
    Add-Check 'Revert-KutayOS -All exit code 0' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
    $output | ForEach-Object { $results.Add("  revert: $_") }

    Import-Module (Join-Path $kutay 'KutayModules\KutayState.psm1') -Force
    foreach ($file in @(Get-ChildItem -LiteralPath $saved -Filter *.json)) {
        $diff = @(Compare-KutaySnapshot -Path $file.FullName)
        Add-Check "$($file.BaseName) back to its snapshot" ($diff.Count -eq 0) "$($diff.Count) differences"
        $diff | ForEach-Object { $results.Add("  $($_.item): expected '$($_.expected)', now '$($_.actual)'") }
    }

    $left = @(Get-ChildItem -LiteralPath $stateRoot -Filter *.json -ErrorAction SilentlyContinue)
    Add-Check 'no snapshots left after revert' ($left.Count -eq 0) "$($left.Count) left"
} catch {
    Add-Check 'revert check ran to the end' $false $_.Exception.Message
}

[IO.File]::WriteAllLines($resultFile, $results)
$results
if (@($results | Where-Object { $_ -like 'FAIL *' }).Count) { exit 1 }
exit 0
