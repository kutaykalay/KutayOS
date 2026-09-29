<#
Read-only inventory of privacy, advertising, suggestion and consumer-content surfaces in the guest.
Runs inside the test VM (via Invoke-GuestScript). Changes nothing. Writes a text report.
vmrun appends a blank argument, so remaining arguments are accepted and ignored.
#>
param([Parameter(ValueFromRemainingArguments)][object[]]$Rest)
$null = $Rest
$OutFile = 'C:\Users\Public\inventory.txt'
$ErrorActionPreference = 'Continue'
$lines = New-Object System.Collections.Generic.List[string]

function Add-Section([string]$Name) { $lines.Add(''); $lines.Add("== $Name ==") }

function Add-RegistryKey([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { $lines.Add("$Path : <absent>"); return }
    $item = Get-Item -LiteralPath $Path
    $names = $item.GetValueNames()
    if ($names.Count -eq 0) { $lines.Add("$Path : <no values>") }
    foreach ($n in $names) { $lines.Add("$Path\$n = $($item.GetValue($n))") }
    foreach ($sub in $item.GetSubKeyNames()) { $lines.Add("$Path -> subkey $sub") }
}

Add-Section 'OS'
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$lines.Add("$($cv.ProductName) | EditionID=$($cv.EditionID) | $($cv.DisplayVersion) | build $($cv.CurrentBuild).$($cv.UBR)")
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$lines.Add("elevated=$isAdmin user=$env:USERNAME")

Add-Section 'Policy keys (HKLM)'
$hklmPolicies = @(
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\TabletPC',
    'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting',
    'HKLM:\SOFTWARE\Policies\Microsoft\Dsh',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds',
    'HKLM:\SOFTWARE\Policies\Microsoft\Edge',
    'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'
)
foreach ($p in $hklmPolicies) { Add-RegistryKey $p }

Add-Section 'Per-user settings (HKCU)'
$hkcuKeys = @(
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search',
    'HKCU:\SOFTWARE\Microsoft\Siuf\Rules',
    'HKCU:\SOFTWARE\Microsoft\InputPersonalization',
    'HKCU:\SOFTWARE\Microsoft\Personalization\Settings',
    'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent',
    'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer',
    'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'
)
foreach ($p in $hkcuKeys) { Add-RegistryKey $p }

Add-Section 'Services'
foreach ($s in 'DiagTrack', 'dmwappushservice', 'WerSvc', 'diagsvc', 'DPS', 'PcaSvc', 'WSearch', 'MapsBroker', 'lfsvc', 'RetailDemo', 'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'XboxGipSvc', 'WpnService', 'CDPSvc', 'SysMain') {
    $svc = Get-CimInstance Win32_Service -Filter "Name='$s'"
    if ($svc) { $lines.Add("$s : $($svc.State) / $($svc.StartMode)") } else { $lines.Add("$s : <absent>") }
}

Add-Section 'Scheduled tasks (telemetry / CEIP / feedback / maps)'
$taskPaths = '\Microsoft\Windows\Application Experience\', '\Microsoft\Windows\Customer Experience Improvement Program\',
    '\Microsoft\Windows\Feedback\Siuf\', '\Microsoft\Windows\Autochk\', '\Microsoft\Windows\DiskDiagnostic\',
    '\Microsoft\Windows\Maps\', '\Microsoft\Windows\CloudExperienceHost\', '\Microsoft\Windows\Windows Error Reporting\',
    '\Microsoft\Windows\Flighting\', '\Microsoft\Windows\PI\'
foreach ($tp in $taskPaths) {
    $tasks = Get-ScheduledTask -TaskPath $tp -ErrorAction SilentlyContinue
    if (-not $tasks) { $lines.Add("$tp : <none>"); continue }
    foreach ($t in $tasks) { $lines.Add("$($t.TaskPath)$($t.TaskName) : $($t.State)") }
}

Add-Section 'AppX packages (current user)'
Get-AppxPackage | Sort-Object Name | ForEach-Object { $lines.Add("$($_.Name) | $($_.Version) | nonremovable=$($_.NonRemovable)") }

Add-Section 'AppX provisioned'
try {
    Get-AppxProvisionedPackage -Online -ErrorAction Stop | Sort-Object DisplayName | ForEach-Object { $lines.Add("$($_.DisplayName) | $($_.Version)") }
} catch { $lines.Add("<error: $($_.Exception.Message)>") }

Add-Section 'Optional features of interest'
try {
    $features = Get-WindowsOptionalFeature -Online -ErrorAction Stop
    foreach ($f in $features | Where-Object { $_.FeatureName -match 'Recall|MediaPlayback|WorkFolders|Printing-XPS|Printing-PDF|SMB1|Internet-Explorer|WindowsMediaPlayer|MicrosoftWindowsPowerShellV2' }) {
        $lines.Add("$($f.FeatureName) : $($f.State)")
    }
} catch { $lines.Add("<error: $($_.Exception.Message)>") }

Add-Section 'Capabilities installed'
try {
    Get-WindowsCapability -Online -ErrorAction Stop | Where-Object State -eq 'Installed' | ForEach-Object { $lines.Add($_.Name) }
} catch { $lines.Add("<error: $($_.Exception.Message)>") }

Add-Section 'Installed programs of interest'
foreach ($p in "$env:ProgramFiles (x86)\Microsoft\Edge\Application", "$env:ProgramFiles (x86)\Microsoft\EdgeWebView\Application", "$env:ProgramFiles\WindowsApps", "$env:LOCALAPPDATA\Microsoft\OneDrive", "$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") {
    $lines.Add("$p : $(Test-Path -LiteralPath $p)")
}

$lines | Set-Content -LiteralPath $OutFile -Encoding UTF8
exit 0
