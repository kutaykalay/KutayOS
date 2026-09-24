<#
.SYNOPSIS
    Updates the ECC files vendored in .claude/ from the upstream ECC repo.
.DESCRIPTION
    Reads the file list from .claude/ecc-sync.txt, shallow-clones ECC, copies
    each entry into .claude/ and writes the new commit to .claude/ecc-sync.lock.
    Review the result with `git diff .claude` before committing.
    -Check only compares the pinned commit with upstream and changes nothing.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/sync-ecc.ps1 -Check
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/sync-ecc.ps1
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [string]$Repo = 'https://github.com/affaan-m/ECC.git',
    [string]$Branch = 'main'
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$claudeDir = Join-Path $root '.claude'
$listFile = Join-Path $claudeDir 'ecc-sync.txt'
$lockFile = Join-Path $claudeDir 'ecc-sync.lock'

function Get-SyncEntry {
    param([string]$Path)
    Get-Content -LiteralPath $Path |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') }
}

function Get-TargetPath {
    param([string]$Entry)
    $relative = $Entry -replace '^rules/', 'rules/ecc/'
    Join-Path $claudeDir ($relative -replace '/', '\')
}

function Get-PinnedCommit {
    if (-not (Test-Path -LiteralPath $lockFile)) { return '' }
    (Get-Content -LiteralPath $lockFile -TotalCount 1).Trim()
}

function Get-UpstreamCommit {
    $line = git ls-remote $Repo "refs/heads/$Branch"
    if ($LASTEXITCODE -ne 0 -or -not $line) { throw "git ls-remote failed for $Repo $Branch" }
    ($line -split '\s+')[0]
}

try {
    $pinned = Get-PinnedCommit
    $upstream = Get-UpstreamCommit

    if ($Check) {
        if ($pinned -eq $upstream) {
            Write-Output "ECC up to date ($($upstream.Substring(0, 7)))."
        } else {
            Write-Output "ECC update available: $pinned -> $($upstream.Substring(0, 7)). Run tools/sync-ecc.ps1, then review git diff .claude."
        }
        exit 0
    }

    $tmp = Join-Path $env:TEMP 'kutayos-ecc-sync'
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
    git clone --quiet --depth 1 --branch $Branch $Repo $tmp
    if ($LASTEXITCODE -ne 0) { throw "git clone failed for $Repo" }
    $commit = (git -C $tmp rev-parse HEAD).Trim()

    foreach ($entry in Get-SyncEntry -Path $listFile) {
        $source = Join-Path $tmp ($entry -replace '/', '\')
        if (-not (Test-Path -LiteralPath $source)) {
            throw "Upstream no longer has '$entry'. Update .claude/ecc-sync.txt."
        }
        $target = Get-TargetPath -Entry $entry
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        $parent = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
        Copy-Item -LiteralPath $source -Destination $target -Recurse
    }

    Set-Content -LiteralPath $lockFile -Value $commit -Encoding Ascii
    Remove-Item -LiteralPath $tmp -Recurse -Force
    Write-Output "Synced ECC $pinned -> $($commit.Substring(0, 7)). Changed files:"
    git -C $root status --short -- .claude
    exit 0
} catch {
    Write-Error "sync-ecc failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
