#Requires -Version 5.1
# The optional "winget + Windows Terminal" step. LTSC 2024 has no Microsoft Store, so neither App
# Installer (winget) nor Windows Terminal is there. Both are downloaded from Microsoft's GitHub
# releases, checked against a pinned SHA256 and the Microsoft signature, and provisioned for all users.
# Nothing is installed until every download and signature check has passed. Terminal updates through
# a per-user scheduled task that runs winget (the winget CLI is not supported as SYSTEM, see
# docs/research/winget-ltsc.md).

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'KutayLog.psm1')

$script:ManifestPath = Join-Path $PSScriptRoot 'KutayApps.psd1'
# Checked on the Microsoft packages in the VM (2026-10-09): subject CN=Microsoft Corporation, issuer
# CN=Microsoft Marketplace CA G 0nn, O=Microsoft Corporation, code signing EKU 1.3.6.1.5.5.7.3.3.
$script:SignerPattern = '^CN=Microsoft Corporation, O=Microsoft Corporation(,|$)'
$script:IssuerPattern = '^CN=Microsoft [^,]+, (.+, )?O=Microsoft Corporation(,|$)'
$script:CodeSigningEku = '1.3.6.1.5.5.7.3.3'
$script:UpdateTaskPath = '\KutayOS\'
$script:UpdateTaskName = 'Update Windows Terminal'
$script:UsersGroupSid = 'S-1-5-32-545'
$script:DownloadAttempts = 3
$script:DownloadTimeoutSeconds = 1800
# winget exit codes (winget returnCodes.md): 0x8A15002B no applicable update; 0x8A150014 no installed
# package found for this user. The first is fine, the second means the task cannot do its job.
$script:WingetNoUpdate = -1978335189
$script:WingetNotInstalled = -1978335212
# Exit codes of Invoke-KutayTerminalUpdate that are not winget's own.
$script:ExitNotInstalledForUser = 2
$script:ExitWingetNotStarted = 3

function Get-KutayAppManifest { Import-PowerShellDataFile -LiteralPath $script:ManifestPath }

function Get-KutayUpdateTaskName { "$script:UpdateTaskPath$script:UpdateTaskName" }

# A 32-bit host on 64-bit Windows reports x86 in PROCESSOR_ARCHITECTURE; the real one is in PROCESSOR_ARCHITEW6432.
function Get-KutayArchitecture {
    param([string]$ProcessorArchitecture = $env:PROCESSOR_ARCHITECTURE, [string]$Wow64Architecture = $env:PROCESSOR_ARCHITEW6432)
    $real = $ProcessorArchitecture
    if ($Wow64Architecture) { $real = $Wow64Architecture }
    switch ($real) {
        'AMD64' { return 'x64' }
        'ARM64' { return 'arm64' }
        default { throw "Processor architecture '$real' is not supported" }
    }
}

# Downloads Url to Path and keeps it only when its SHA256 matches. A bad file never stays on disk.
# A failed or stalled download is tried again; a hash mismatch is not (the file itself is wrong).
function Save-KutayVerifiedFile {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Sha256,
        [Parameter(Mandatory)][string]$Path
    )
    if ($Url -notlike 'https://*') { throw "Refusing to download over a connection that is not https: $Url" }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    # The progress bar makes Invoke-WebRequest several times slower in Windows PowerShell 5.1.
    $ProgressPreference = 'SilentlyContinue'
    $failure = ''
    for ($attempt = 1; $attempt -le $script:DownloadAttempts; $attempt++) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -TimeoutSec $script:DownloadTimeoutSeconds
            $failure = ''
            break
        } catch {
            $failure = $_.Exception.Message
            Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
            if ($attempt -lt $script:DownloadAttempts) { Start-Sleep -Seconds (5 * $attempt) }
        }
    }
    if ($failure) { throw "Download of $Url failed after $script:DownloadAttempts attempts: $failure" }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Sha256.ToLowerInvariant()) {
        Remove-Item -LiteralPath $Path -Force
        throw "SHA256 of $Url is $actual, expected $($Sha256.ToLowerInvariant())"
    }
}

# Valid Authenticode signature, made by Microsoft Corporation with a code signing certificate that a
# Microsoft CA issued. The hash pin on the downloads is what proves the files; this proves that what is
# about to be installed is still a Microsoft package.
function Assert-KutayMicrosoftSignature {
    param([Parameter(Mandatory)][string]$Path)
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ([string]$signature.Status -ne 'Valid') {
        throw "$Path has signature status $($signature.Status), expected Valid"
    }
    $certificate = $signature.SignerCertificate
    if ([string]$certificate.Subject -notmatch $script:SignerPattern) {
        throw "$Path is signed by an unexpected publisher: $($certificate.Subject)"
    }
    if ([string]$certificate.Issuer -notmatch $script:IssuerPattern) {
        throw "$Path has a signing certificate from an unexpected issuer: $($certificate.Issuer)"
    }
    if (@($certificate.EnhancedKeyUsageList | ForEach-Object { $_.ObjectId }) -notcontains $script:CodeSigningEku) {
        throw "$Path has a signing certificate that is not for code signing"
    }
}

# Extracts a zip, refusing any entry that would land outside the destination (Expand-Archive in
# Windows PowerShell 5.1 does not reliably do that).
function Expand-KutayArchive {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Destination)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $root = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Path).ProviderPath)
    try {
        $targets = foreach ($entry in $archive.Entries) {
            $target = [IO.Path]::GetFullPath((Join-Path $root $entry.FullName))
            if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Archive entry '$($entry.FullName)' would be written outside $Destination"
            }
            [pscustomobject]@{ Entry = $entry; Target = $target }
        }
        foreach ($item in $targets) {
            if ($item.Entry.FullName.EndsWith('/') -or $item.Entry.FullName.EndsWith('\')) {
                New-Item -ItemType Directory -Force -Path $item.Target | Out-Null
                continue
            }
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $item.Target) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($item.Entry, $item.Target, $true)
        }
    } finally {
        $archive.Dispose()
    }
}

# Under %windir%\KutayOS, not in a temp folder the signed-in user can write to: a swap between the
# signature check and the install would otherwise be possible, and the final delete runs elevated.
function Get-KutayDefaultWorkDirectory { Join-Path $env:windir "KutayOS\Work\KutayApps-$([guid]::NewGuid())" }

function New-KutayWorkDirectory {
    param([Parameter(Mandatory)][string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in 'S-1-5-18', 'S-1-5-32-544') {
        $identity = New-Object Security.Principal.SecurityIdentifier $sid
        $rule = New-Object Security.AccessControl.FileSystemAccessRule $identity, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow'
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}

# Version of a package already provisioned for new users, or $null.
function Get-KutayProvisionedVersion([string]$PackageName) {
    $found = @(Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $PackageName })
    if ($found.Count -eq 0) { return $null }
    ($found | ForEach-Object { [version]$_.Version } | Sort-Object -Descending | Select-Object -First 1)
}

# Provisions a package for all users. $true when it installed something, $false when the same or a
# newer version was already there.
function Install-KutayAppPackage {
    param(
        [Parameter(Mandatory)][string]$PackageName,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$PackagePath,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$DependencyPath,
        [Parameter(Mandatory)][string]$LicensePath
    )
    $have = Get-KutayProvisionedVersion $PackageName
    if ($have -and $have -ge [version]$Version) {
        $null = Write-KutayLog "$PackageName $have is already provisioned, nothing to install"
        return $false
    }
    $arguments = @{ Online = $true; PackagePath = $PackagePath; LicensePath = $LicensePath }
    if ($DependencyPath.Count) { $arguments.DependencyPackagePath = $DependencyPath }
    $result = Add-AppxProvisionedPackage @arguments
    $now = Get-KutayProvisionedVersion $PackageName
    if (-not $now) { throw "$PackageName is not provisioned after the install" }
    $null = Write-KutayLog "Provisioned $PackageName $now"
    if ($result -and $result.PSObject.Properties['RestartNeeded'] -and $result.RestartNeeded) {
        $null = Write-KutayLog "$PackageName asks for a restart"
    }
    return $true
}

function Get-KutayChildPath([string]$Root, [string]$Filter) {
    $found = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter $Filter)
    if ($found.Count -ne 1) { throw "Expected one $Filter in $Root, found $($found.Count)" }
    $found[0].FullName
}

# Downloads, verifies, then installs winget and Windows Terminal. Everything is checked before the first
# install, so a bad download or signature leaves Windows untouched, and each package is checked again
# right before it goes in.
function Install-KutayWingetAndTerminal {
    param([string]$WorkDirectory = (Get-KutayDefaultWorkDirectory))
    $manifest = Get-KutayAppManifest
    $architecture = Get-KutayArchitecture
    New-KutayWorkDirectory -Path $WorkDirectory
    try {
        $winget = $manifest.Winget
        $bundle = Join-Path $WorkDirectory (Split-Path -Leaf $winget.Bundle.Url)
        $license = Join-Path $WorkDirectory (Split-Path -Leaf $winget.License.Url)
        $dependencyZip = Join-Path $WorkDirectory (Split-Path -Leaf $winget.Dependencies.Url)
        $kitZip = Join-Path $WorkDirectory (Split-Path -Leaf $manifest.Terminal.Kit.Url)
        foreach ($download in @(
                @($winget.Bundle, $bundle), @($winget.License, $license),
                @($winget.Dependencies, $dependencyZip), @($manifest.Terminal.Kit, $kitZip))) {
            $null = Write-KutayLog "Downloading $(Split-Path -Leaf $download[1])"
            Save-KutayVerifiedFile -Url $download[0].Url -Sha256 $download[0].Sha256 -Path $download[1]
        }
        $dependencyDir = Join-Path $WorkDirectory 'winget-dependencies'
        $kitDir = Join-Path $WorkDirectory 'terminal-kit'
        Expand-KutayArchive -Path $dependencyZip -Destination $dependencyDir
        Expand-KutayArchive -Path $kitZip -Destination $kitDir

        $wingetDependencies = @(Get-ChildItem -LiteralPath (Join-Path $dependencyDir $architecture) -File -Filter *.appx |
                ForEach-Object { $_.FullName })
        if ($wingetDependencies.Count -eq 0) { throw "No winget dependencies for $architecture" }
        $terminalBundle = Get-KutayChildPath $kitDir '*.msixbundle'
        $terminalLicense = Get-KutayChildPath $kitDir '*License1.xml'
        $terminalDependencies = @(Get-ChildItem -LiteralPath $kitDir -File -Filter "Microsoft.UI.Xaml*_${architecture}_*.appx" |
                ForEach-Object { $_.FullName })
        if ($terminalDependencies.Count -eq 0) { throw "No Terminal dependencies for $architecture" }

        $wingetFiles = @($bundle) + $wingetDependencies
        $terminalFiles = @($terminalBundle) + $terminalDependencies
        foreach ($file in $wingetFiles + $terminalFiles) { Assert-KutayMicrosoftSignature -Path $file }

        # winget first: its dependency packages (VCLibs, Windows App Runtime) are shared frameworks.
        foreach ($file in $wingetFiles) { Assert-KutayMicrosoftSignature -Path $file }
        $null = Install-KutayAppPackage -PackageName $winget.PackageName -Version $winget.ProvisionedVersion `
            -PackagePath $bundle -DependencyPath $wingetDependencies -LicensePath $license
        foreach ($file in $terminalFiles) { Assert-KutayMicrosoftSignature -Path $file }
        $null = Install-KutayAppPackage -PackageName $manifest.Terminal.PackageName -Version $manifest.Terminal.ProvisionedVersion `
            -PackagePath $terminalBundle -DependencyPath $terminalDependencies -LicensePath $terminalLicense
    } finally {
        try {
            Remove-Item -LiteralPath $WorkDirectory -Recurse -Force -ErrorAction Stop
        } catch {
            $null = Write-KutayLog "Could not remove $WorkDirectory ($($_.Exception.Message)); delete it by hand"
        }
    }
}

function Get-KutayDesktopPath { Join-Path $env:windir 'KutayOS\KutayDesktop' }

# winget lives in the user's WindowsApps alias folder, which is on PATH for a normal logon.
function Get-KutayWingetPath {
    $command = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    return $null
}

# A normal user cannot write under %windir%, so the update task logs in the user's own profile.
function Write-KutayUserLog([string]$Message) {
    $directory = Join-Path $env:LOCALAPPDATA 'KutayOS'
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message
    Add-Content -LiteralPath (Join-Path $directory 'terminal-update.log') -Value $line -Encoding UTF8
}

# Runs winget and returns its exit code. Throws when the program could not be started at all, so a stale
# or missing exit code is never taken for a result. On failure the last output lines go to the log.
function Invoke-KutayWinget {
    param([Parameter(Mandatory)][string]$WingetPath, [Parameter(Mandatory)][string[]]$ArgumentList)
    $ErrorActionPreference = 'Continue'
    $global:LASTEXITCODE = $null
    $output = @(& $WingetPath @ArgumentList 2>&1)
    if ($null -eq $global:LASTEXITCODE) { throw "$WingetPath did not start" }
    $code = [int]$global:LASTEXITCODE
    if ($code -ne 0) {
        $tail = @($output | ForEach-Object { "$_".Trim() } | Where-Object { $_ } | Select-Object -Last 10)
        if ($tail.Count) { Write-KutayUserLog "winget output: $($tail -join ' | ')" }
    }
    return $code
}

# Returns the exit code the update task should end with: 0 when Terminal is up to date or was upgraded,
# winget's own code when it failed, 2 when winget cannot see Terminal for this user, 3 when winget
# could not be started. "winget not installed yet" is 0: the task also exists on PCs where it is not
# registered for the user yet.
function Invoke-KutayTerminalUpdate {
    $winget = Get-KutayWingetPath
    if (-not $winget) {
        Write-KutayUserLog 'winget is not available for this user yet; nothing to update'
        return 0
    }
    $arguments = 'upgrade', '--id', 'Microsoft.WindowsTerminal', '--exact', '--source', 'winget', '--silent',
    '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
    try {
        $code = [int](Invoke-KutayWinget -WingetPath $winget -ArgumentList $arguments)
    } catch {
        Write-KutayUserLog "winget could not be started: $($_.Exception.Message)"
        return $script:ExitWingetNotStarted
    }
    if ($code -eq 0 -or $code -eq $script:WingetNoUpdate) {
        Write-KutayUserLog "winget upgrade finished with $code"
        return 0
    }
    if ($code -eq $script:WingetNotInstalled) {
        Write-KutayUserLog 'winget does not see Windows Terminal as installed for this user; it cannot be updated until it is registered for them'
        return $script:ExitNotInstalledForUser
    }
    Write-KutayUserLog "winget upgrade failed with $code"
    return $code
}

function Register-KutayUpdateTask {
    $script = Join-Path (Get-KutayDesktopPath) 'Update-KutayTerminal.ps1'
    if (-not (Test-Path -LiteralPath $script)) { throw "Cannot register the update task: $script is missing" }
    $powershell = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $action = New-ScheduledTaskAction -Execute $powershell `
        -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
    $logon = New-ScheduledTaskTrigger -AtLogOn
    $logon.Delay = 'PT5M'
    $daily = New-ScheduledTaskTrigger -Daily -At '12:00'
    $principal = New-ScheduledTaskPrincipal -GroupId $script:UsersGroupSid -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
    $null = Register-ScheduledTask -TaskPath $script:UpdateTaskPath -TaskName $script:UpdateTaskName -Action $action `
        -Trigger @($logon, $daily) -Principal $principal -Settings $settings -Force
    $null = Write-KutayLog "Registered the scheduled task $(Get-KutayUpdateTaskName)"
}

Export-ModuleMember -Function Get-KutayAppManifest, Get-KutayUpdateTaskName, Install-KutayWingetAndTerminal,
    Register-KutayUpdateTask, Invoke-KutayTerminalUpdate, Save-KutayVerifiedFile, Assert-KutayMicrosoftSignature,
    Get-KutayArchitecture, Install-KutayAppPackage, Expand-KutayArchive, Invoke-KutayWinget, New-KutayWorkDirectory
