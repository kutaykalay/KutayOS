#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
try {
    $path = ([Console]::In.ReadToEnd() | ConvertFrom-Json).tool_input.file_path
} catch {
    exit 0
}
if (-not $path -or $path -notmatch '\.ps[md]?1$' -or -not (Test-Path -LiteralPath $path)) { exit 0 }

$problems = New-Object System.Collections.Generic.List[string]

$tokens = $null; $errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
foreach ($e in $errors) { $problems.Add("Parse error line $($e.Extent.StartLineNumber): $($e.Message)") }

$bytes = [IO.File]::ReadAllBytes($path)
$hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
if (-not $hasBom) {
    foreach ($b in $bytes) {
        if ($b -gt 0x7F) {
            $problems.Add('Non-ASCII characters without a UTF-8 BOM: Windows PowerShell 5.1 will misread this file. Use ASCII or save with BOM.')
            break
        }
    }
}

if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
    $params = @{ Path = $path; Severity = 'Warning', 'Error' }
    if ($env:CLAUDE_PROJECT_DIR) {
        $settings = Join-Path $env:CLAUDE_PROJECT_DIR 'PSScriptAnalyzerSettings.psd1'
        if (Test-Path -LiteralPath $settings) { $params.Settings = $settings }
    }
    Invoke-ScriptAnalyzer @params | ForEach-Object {
        $problems.Add("PSScriptAnalyzer $($_.RuleName) line $($_.Line): $($_.Message)")
    }
}

if ($problems.Count -gt 0) {
    [Console]::Error.WriteLine("KutayOS ps-lint: $path`n" + ($problems -join "`n"))
    exit 2
}
exit 0
