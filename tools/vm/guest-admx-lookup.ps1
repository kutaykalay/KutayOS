<#
Read-only lookup of policy definitions in the guest's C:\Windows\PolicyDefinitions: for each value
name below, prints the ADMX file, policy name, class (User/Machine/Both), key, enabled/disabled
values, supportedOn and the English title. Runs inside the test VM (via Invoke-GuestScript).
vmrun appends a blank argument, so remaining arguments are accepted and ignored.
#>
param([Parameter(ValueFromRemainingArguments)][object[]]$Rest)
$null = $Rest
$OutFile = 'C:\Users\Public\admx-lookup.txt'
$ErrorActionPreference = 'Continue'
$valueNames = @(
    'DisableTailoredExperiencesWithDiagnosticData'
    'DisableThirdPartySuggestions'
    'DisableSearchBoxSuggestions'
    'ConnectedSearchUseWeb'
    'HideRecommendedSection'
    'HideTaskViewButton'
    'SearchOnTaskbarMode'
)
$definitions = Join-Path $env:windir 'PolicyDefinitions'
$lines = New-Object System.Collections.Generic.List[string]

function Get-Title([string]$File, [string]$Ref) {
    $adml = Join-Path $definitions ('en-US\' + [IO.Path]::GetFileNameWithoutExtension($File) + '.adml')
    if (-not (Test-Path -LiteralPath $adml)) { return '<no en-US adml>' }
    $id = $Ref -replace '^\$\(string\.(.+)\)$', '$1'
    $node = ([xml](Get-Content -LiteralPath $adml -Raw)).policyDefinitionResources.resources.stringTable.string |
        Where-Object { $_.id -eq $id } | Select-Object -First 1
    if ($node) { return $node.'#text' }
    '<title not found>'
}

function Get-ValueText($Node) {
    if (-not $Node) { return '-' }
    if ($Node.decimal) { return "decimal $($Node.decimal.value)" }
    if ($Node.string) { return "string '$($Node.string)'" }
    if ($Node.delete) { return 'delete' }
    $Node.InnerXml
}

foreach ($file in Get-ChildItem -LiteralPath $definitions -Filter *.admx) {
    $xml = [xml](Get-Content -LiteralPath $file.FullName -Raw)
    foreach ($policy in @($xml.policyDefinitions.policies.policy)) {
        if (-not $policy) { continue }
        $inner = $policy.OuterXml
        foreach ($name in $valueNames) {
            if ($inner -notmatch "valueName=""$name""") { continue }
            $lines.Add("== $name ==")
            $lines.Add("file: $($file.Name)  policy: $($policy.name)  class: $($policy.class)")
            $lines.Add("key: $($policy.key)  valueName (policy): $($policy.valueName)")
            $lines.Add("enabled: $(Get-ValueText $policy.enabledValue)  disabled: $(Get-ValueText $policy.disabledValue)")
            $lines.Add("supportedOn: $($policy.supportedOn.ref)")
            $lines.Add("title: $(Get-Title $file.Name $policy.displayName)")
            if ($policy.elements) { $lines.Add("elements: $($policy.elements.InnerXml)") }
            $lines.Add('')
        }
    }
}
foreach ($name in $valueNames) {
    if (-not ($lines -match "^== $name ==$")) { $lines.Add("== $name == <not in any ADMX>") }
}
$lines | Set-Content -LiteralPath $OutFile -Encoding ASCII
exit 0
