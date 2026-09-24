#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutDir
)
$ErrorActionPreference = 'Stop'
# $PSScriptRoot is empty inside param defaults on Windows PowerShell 5.1 with -File.
if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot '..\dist' }

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\src\playbook')).Path
$configDir = Join-Path $root 'Configuration'

[xml]$conf = Get-Content -LiteralPath (Join-Path $root 'playbook.conf') -Raw -Encoding UTF8
$version = $conf.Playbook.Version
if (-not $version) { throw 'playbook.conf: <Version> is missing' }
if (-not (Test-Path (Join-Path $configDir 'custom.yml'))) { throw 'Configuration\custom.yml is missing' }

# AME resolves !task paths relative to Configuration\; a typo only surfaces mid-install otherwise.
$taskPattern = "!task:\s*\{\s*path:\s*['""]([^'""]+)['""]"
Get-ChildItem -LiteralPath $configDir -Recurse -Filter *.yml | ForEach-Object {
    $file = $_
    Select-String -LiteralPath $file.FullName -Pattern $taskPattern -AllMatches |
        ForEach-Object { $_.Matches } |
        ForEach-Object {
            $rel = $_.Groups[1].Value
            if (-not (Test-Path (Join-Path $configDir $rel))) {
                throw "$($file.Name): task path not found: $rel"
            }
        }
}

$sevenZip = @(
    (Get-Command 7z.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
    (Join-Path $env:ProgramFiles '7-Zip\7z.exe')
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $sevenZip) { throw '7-Zip not found. Install it with: winget install 7zip.7zip' }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$out = Join-Path (Resolve-Path $OutDir).Path "KutayOS-$version.apbx"
if (Test-Path $out) { Remove-Item -LiteralPath $out }

# AME Wizard expects a ZIP encrypted with the fixed password 'malte', renamed to .apbx.
Push-Location $root
try {
    & $sevenZip a -tzip -pmalte -mx=9 -r '-xr!.gitkeep' $out '*' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "7-Zip failed with exit code $LASTEXITCODE" }
} finally {
    Pop-Location
}
Write-Host "Built $out"
