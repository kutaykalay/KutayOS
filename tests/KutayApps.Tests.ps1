[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester passes these variables between its blocks')]
param()

BeforeAll {
    $modules = Join-Path $PSScriptRoot '..\src\playbook\Executables\KutayModules'
    $script:ManifestPath = Join-Path $modules 'KutayApps.psd1'
    Import-Module (Join-Path $modules 'KutayApps.psm1') -Force
}

AfterAll {
    Remove-Module KutayApps -ErrorAction SilentlyContinue
}

Describe 'KutayApps.psd1' {
    BeforeAll {
        $manifest = Import-PowerShellDataFile -LiteralPath $script:ManifestPath
        $downloads = @(
            @{ Name = 'winget bundle'; Item = $manifest.Winget.Bundle }
            @{ Name = 'winget license'; Item = $manifest.Winget.License }
            @{ Name = 'winget dependencies'; Item = $manifest.Winget.Dependencies }
            @{ Name = 'terminal kit'; Item = $manifest.Terminal.Kit }
        )
    }

    It 'pins <Name> to a Microsoft GitHub release with a SHA256' -ForEach @(
        @{ Name = 'winget bundle'; Key = 'Bundle'; Section = 'Winget' }
        @{ Name = 'winget license'; Key = 'License'; Section = 'Winget' }
        @{ Name = 'winget dependencies'; Key = 'Dependencies'; Section = 'Winget' }
        @{ Name = 'terminal kit'; Key = 'Kit'; Section = 'Terminal' }
    ) {
        $item = (Import-PowerShellDataFile -LiteralPath $script:ManifestPath).$Section.$Key
        $item.Url | Should -Match '^https://github\.com/microsoft/(winget-cli|terminal)/releases/download/v[\d.]+/\S+$'
        $item.Sha256 | Should -Match '^[0-9a-f]{64}$'
    }

    It 'gives each package a name and a four part provisioned version' -ForEach @(
        @{ Section = 'Winget' }
        @{ Section = 'Terminal' }
    ) {
        $section = (Import-PowerShellDataFile -LiteralPath $script:ManifestPath).$Section
        $section.PackageName | Should -Match '^Microsoft\.\w+$'
        $section.ProvisionedVersion | Should -Match '^\d+\.\d+\.\d+\.\d+$'
    }
}

Describe 'Save-KutayVerifiedFile' {
    BeforeEach {
        $script:file = Join-Path ([IO.Path]::GetTempPath()) "kutay-test-$([guid]::NewGuid()).bin"
        $script:payload = 'hello'
        $script:hash = (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::ASCII.GetBytes('hello'))) -Algorithm SHA256).Hash.ToLowerInvariant()
        Mock -ModuleName KutayApps Invoke-WebRequest { [IO.File]::WriteAllText($OutFile, 'hello') }
    }
    AfterEach { Remove-Item -LiteralPath $script:file -ErrorAction SilentlyContinue }

    It 'keeps the file when the hash matches' {
        Save-KutayVerifiedFile -Url 'https://example.test/a' -Sha256 $script:hash -Path $script:file
        Test-Path -LiteralPath $script:file | Should -BeTrue
    }

    It 'accepts an upper case hash' {
        Save-KutayVerifiedFile -Url 'https://example.test/a' -Sha256 $script:hash.ToUpperInvariant() -Path $script:file
        Test-Path -LiteralPath $script:file | Should -BeTrue
    }

    It 'deletes the file and throws when the hash differs' {
        { Save-KutayVerifiedFile -Url 'https://example.test/a' -Sha256 ('0' * 64) -Path $script:file } |
            Should -Throw '*SHA256*'
        Test-Path -LiteralPath $script:file | Should -BeFalse
    }

    It 'names the url when the download fails' {
        Mock -ModuleName KutayApps Start-Sleep { }
        Mock -ModuleName KutayApps Invoke-WebRequest { throw 'no network' }
        { Save-KutayVerifiedFile -Url 'https://example.test/a' -Sha256 $script:hash -Path $script:file } |
            Should -Throw '*https://example.test/a*'
    }

    It 'retries a failed download and keeps the file once an attempt works' {
        $script:attempts = 0
        Mock -ModuleName KutayApps Start-Sleep { }
        Mock -ModuleName KutayApps Invoke-WebRequest {
            $script:attempts++
            if ($script:attempts -lt 3) { throw 'connection reset' }
            [IO.File]::WriteAllText($OutFile, 'hello')
        }

        Save-KutayVerifiedFile -Url 'https://example.test/a' -Sha256 $script:hash -Path $script:file

        $script:attempts | Should -Be 3
        Test-Path -LiteralPath $script:file | Should -BeTrue
    }

    It 'gives up after three attempts and says how many it made' {
        Mock -ModuleName KutayApps Start-Sleep { }
        Mock -ModuleName KutayApps Invoke-WebRequest { throw 'no network' }

        { Save-KutayVerifiedFile -Url 'https://example.test/a' -Sha256 $script:hash -Path $script:file } |
            Should -Throw '*3 attempts*'
        Should -Invoke -ModuleName KutayApps Invoke-WebRequest -Times 3 -Exactly
    }

    It 'sets a timeout on every attempt' {
        Save-KutayVerifiedFile -Url 'https://example.test/a' -Sha256 $script:hash -Path $script:file

        Should -Invoke -ModuleName KutayApps Invoke-WebRequest -ParameterFilter { $TimeoutSec -gt 0 }
    }

    It 'does not retry a hash mismatch' {
        Mock -ModuleName KutayApps Start-Sleep { }

        { Save-KutayVerifiedFile -Url 'https://example.test/a' -Sha256 ('0' * 64) -Path $script:file } | Should -Throw '*SHA256*'
        Should -Invoke -ModuleName KutayApps Invoke-WebRequest -Times 1 -Exactly
    }

    It 'refuses a url that is not https' {
        { Save-KutayVerifiedFile -Url 'http://example.test/a' -Sha256 $script:hash -Path $script:file } |
            Should -Throw '*https*'
        Should -Invoke -ModuleName KutayApps Invoke-WebRequest -Times 0 -Exactly
    }
}

Describe 'Assert-KutayMicrosoftSignature' {
    # Signers like the real ones (subject, issuer and EKU checked on the Microsoft packages in the VM, 2026-10-09).
    It 'accepts a valid Microsoft Corporation signature' {
        Mock -ModuleName KutayApps Get-AuthenticodeSignature {
            [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{
                    Subject = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'
                    Issuer = 'CN=Microsoft Marketplace CA G 024, OU=AOC, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'
                    EnhancedKeyUsageList = @([pscustomobject]@{ ObjectId = '1.3.6.1.5.5.7.3.3' })
                }
            }
        }
        { Assert-KutayMicrosoftSignature -Path 'C:\x.msix' } | Should -Not -Throw
    }

    It 'rejects a Microsoft subject issued by another CA: <Issuer>' -ForEach @(
        @{ Issuer = 'CN=Evil Root CA, O=Evil Corp, C=US' }
        @{ Issuer = 'CN=Microsoft Fake, O=Evil Corp, C=US' }
        @{ Issuer = '' }
    ) {
        Mock -ModuleName KutayApps Get-AuthenticodeSignature {
            [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{
                    Subject = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'; Issuer = $Issuer
                    EnhancedKeyUsageList = @([pscustomobject]@{ ObjectId = '1.3.6.1.5.5.7.3.3' })
                }
            }
        }
        { Assert-KutayMicrosoftSignature -Path 'C:\x.msix' } | Should -Throw '*issuer*'
    }

    It 'rejects a certificate that is not for code signing' {
        Mock -ModuleName KutayApps Get-AuthenticodeSignature {
            [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{
                    Subject = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'
                    Issuer = 'CN=Microsoft Marketplace CA G 024, OU=AOC, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'
                    EnhancedKeyUsageList = @([pscustomobject]@{ ObjectId = '1.3.6.1.5.5.7.3.2' })
                }
            }
        }
        { Assert-KutayMicrosoftSignature -Path 'C:\x.msix' } | Should -Throw '*code signing*'
    }

    It 'rejects status <Status>' -ForEach @(
        @{ Status = 'NotSigned' }
        @{ Status = 'HashMismatch' }
        @{ Status = 'UnknownError' }
    ) {
        Mock -ModuleName KutayApps Get-AuthenticodeSignature {
            [pscustomobject]@{ Status = $Status; SignerCertificate = $null }
        }
        { Assert-KutayMicrosoftSignature -Path 'C:\x.msix' } | Should -Throw "*$Status*"
    }

    It 'rejects a valid signature from another publisher: <Subject>' -ForEach @(
        @{ Subject = 'CN=Evil Corp, O=Evil Corp, C=US' }
        @{ Subject = 'CN=Microsoft Corporation Evil, O=Evil Corp, C=US' }
        @{ Subject = 'CN=Evil, O=Microsoft Corporation, C=US' }
    ) {
        Mock -ModuleName KutayApps Get-AuthenticodeSignature {
            [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{
                    Subject = $Subject; Issuer = 'CN=Microsoft Marketplace CA G 024, O=Microsoft Corporation, C=US'
                    EnhancedKeyUsageList = @([pscustomobject]@{ ObjectId = '1.3.6.1.5.5.7.3.3' })
                }
            }
        }
        { Assert-KutayMicrosoftSignature -Path 'C:\x.msix' } | Should -Throw '*publisher*'
    }
}

Describe 'Get-KutayArchitecture' {
    It 'maps <Value> to <Expected>' -ForEach @(
        @{ Value = 'AMD64'; Expected = 'x64' }
        @{ Value = 'ARM64'; Expected = 'arm64' }
    ) {
        Get-KutayArchitecture -ProcessorArchitecture $Value | Should -Be $Expected
    }

    It 'uses the real architecture when a 32-bit host runs on 64-bit Windows' {
        Get-KutayArchitecture -ProcessorArchitecture 'x86' -Wow64Architecture 'AMD64' | Should -Be 'x64'
    }

    It 'rejects <Value>' -ForEach @(@{ Value = 'x86' }, @{ Value = 'IA64' }) {
        { Get-KutayArchitecture -ProcessorArchitecture $Value } | Should -Throw '*not supported*'
    }
}

Describe 'Install-KutayAppPackage' {
    BeforeEach {
        Mock -ModuleName KutayApps Write-KutayLog { }
        Mock -ModuleName KutayApps Add-AppxProvisionedPackage { }
        Mock -ModuleName KutayApps Get-KutayProvisionedVersion { $null }
    }

    It 'provisions the package with its dependencies and license when it is absent' {
        # After the install the package must be there, or the step failed silently.
        $script:calls = 0
        Mock -ModuleName KutayApps Get-KutayProvisionedVersion { $script:calls++; if ($script:calls -gt 1) { [version]'1.2.3.0' } }

        Install-KutayAppPackage -PackageName 'Microsoft.Test' -Version '1.2.3.0' -PackagePath 'C:\p.msix' `
            -DependencyPath 'C:\d1.appx', 'C:\d2.appx' -LicensePath 'C:\l.xml' | Should -BeTrue

        Should -Invoke -ModuleName KutayApps Add-AppxProvisionedPackage -Times 1 -Exactly -ParameterFilter {
            $PackagePath -eq 'C:\p.msix' -and $LicensePath -eq 'C:\l.xml' -and @($DependencyPackagePath).Count -eq 2
        }
    }

    It 'skips the install when the same or a newer version is already provisioned: <Have>' -ForEach @(
        @{ Have = '1.2.3.0' }
        @{ Have = '1.3.0.0' }
    ) {
        Mock -ModuleName KutayApps Get-KutayProvisionedVersion { [version]$Have }

        Install-KutayAppPackage -PackageName 'Microsoft.Test' -Version '1.2.3.0' -PackagePath 'C:\p.msix' `
            -DependencyPath @() -LicensePath 'C:\l.xml' | Should -BeFalse

        Should -Invoke -ModuleName KutayApps Add-AppxProvisionedPackage -Times 0 -Exactly
    }

    It 'installs over an older version' {
        $script:calls = 0
        Mock -ModuleName KutayApps Get-KutayProvisionedVersion { $script:calls++; if ($script:calls -eq 1) { [version]'1.0.0.0' } else { [version]'1.2.3.0' } }

        Install-KutayAppPackage -PackageName 'Microsoft.Test' -Version '1.2.3.0' -PackagePath 'C:\p.msix' `
            -DependencyPath @() -LicensePath 'C:\l.xml' | Should -BeTrue
    }

    It 'throws when the package is not provisioned afterwards' {
        { Install-KutayAppPackage -PackageName 'Microsoft.Test' -Version '1.2.3.0' -PackagePath 'C:\p.msix' `
                -DependencyPath @() -LicensePath 'C:\l.xml' } | Should -Throw '*Microsoft.Test*'
    }

    It 'lets an install error through' {
        Mock -ModuleName KutayApps Add-AppxProvisionedPackage { throw 'deployment failed' }
        { Install-KutayAppPackage -PackageName 'Microsoft.Test' -Version '1.2.3.0' -PackagePath 'C:\p.msix' `
                -DependencyPath @() -LicensePath 'C:\l.xml' } | Should -Throw '*deployment failed*'
    }
}

Describe 'Install-KutayWingetAndTerminal' {
    BeforeEach {
        $script:work = Join-Path ([IO.Path]::GetTempPath()) "kutay-apps-$([guid]::NewGuid())"
        $script:order = [Collections.Generic.List[string]]::new()
        Mock -ModuleName KutayApps Get-KutayArchitecture { 'x64' }
        Mock -ModuleName KutayApps Save-KutayVerifiedFile {
            $script:order.Add("download $(Split-Path -Leaf $Url)")
            New-Item -ItemType File -Force -Path $Path | Out-Null
        }
        Mock -ModuleName KutayApps Expand-KutayArchive {
            $script:order.Add("expand $(Split-Path -Leaf $Path)")
            New-Item -ItemType Directory -Force -Path $Destination | Out-Null
            foreach ($name in 'x64\Microsoft.VCLibs.140.00_1_x64.appx', 'x64\Microsoft.WindowsAppRuntime.1.8_1_x64.appx',
                'x64\Microsoft.VCLibs.140.00.UWPDesktop_1_x64.appx', 'a.msixbundle', 'a_License1.xml', 'Microsoft.UI.Xaml.2.8_1_x64__8wekyb3d8bbwe.appx') {
                $file = Join-Path $Destination $name
                New-Item -ItemType File -Force -Path $file | Out-Null
            }
        }
        Mock -ModuleName KutayApps Assert-KutayMicrosoftSignature { $script:order.Add("sign $(Split-Path -Leaf $Path)") }
        Mock -ModuleName KutayApps Install-KutayAppPackage { $script:order.Add("install $PackageName"); $true }
        Mock -ModuleName KutayApps Write-KutayLog { }
        # The real one locks the folder to SYSTEM and Administrators, which would lock the test out too.
        Mock -ModuleName KutayApps New-KutayWorkDirectory { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
    }
    AfterEach { Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction SilentlyContinue }

    It 'downloads and verifies everything before it installs anything' {
        Install-KutayWingetAndTerminal -WorkDirectory $script:work

        $firstInstall = $script:order.FindIndex({ param($line) $line -like 'install *' })
        $lastDownload = $script:order.FindLastIndex({ param($line) $line -like 'download *' })
        $terminalSignedUpFront = $script:order.IndexOf('sign a.msixbundle')
        $firstInstall | Should -BeGreaterThan $lastDownload
        # The first check of the Terminal files, which are installed last, already happened.
        $firstInstall | Should -BeGreaterThan $terminalSignedUpFront
    }

    It 'installs winget before Terminal, so the shared frameworks are there' {
        Install-KutayWingetAndTerminal -WorkDirectory $script:work

        $installs = @($script:order | Where-Object { $_ -like 'install *' })
        $installs | Should -Be @('install Microsoft.DesktopAppInstaller', 'install Microsoft.WindowsTerminal')
    }

    It 'checks the signature of the bundle, the dependencies and the Terminal kit files' {
        Install-KutayWingetAndTerminal -WorkDirectory $script:work

        $signed = @($script:order | Where-Object { $_ -like 'sign *' })
        $signed | Should -Contain 'sign Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
        $signed | Should -Contain 'sign Microsoft.VCLibs.140.00_1_x64.appx'
        $signed | Should -Contain 'sign a.msixbundle'
        $signed | Should -Contain 'sign Microsoft.UI.Xaml.2.8_1_x64__8wekyb3d8bbwe.appx'
    }

    It 'installs nothing when a download fails' {
        Mock -ModuleName KutayApps Save-KutayVerifiedFile {
            if ($Url -like '*terminal*') { throw 'SHA256 mismatch' }
            New-Item -ItemType File -Force -Path $Path | Out-Null
        }
        { Install-KutayWingetAndTerminal -WorkDirectory $script:work } | Should -Throw '*SHA256*'
        Should -Invoke -ModuleName KutayApps Install-KutayAppPackage -Times 0 -Exactly
    }

    It 'checks the signatures again right before each install' {
        Install-KutayWingetAndTerminal -WorkDirectory $script:work

        # Each file is signed once in the up front pass and once before its package goes in.
        $signedBundle = @($script:order | Where-Object { $_ -eq 'sign a.msixbundle' })
        $signedBundle.Count | Should -Be 2
        $lastTerminalSign = $script:order.FindLastIndex({ param($line) $line -eq 'sign a.msixbundle' })
        $terminalInstall = $script:order.IndexOf('install Microsoft.WindowsTerminal')
        $lastTerminalSign | Should -BeLessThan $terminalInstall
    }

    It 'does not install Terminal when its files were swapped after the first check' {
        $script:signs = 0
        Mock -ModuleName KutayApps Assert-KutayMicrosoftSignature {
            if ($Path -like '*a.msixbundle') { $script:signs++; if ($script:signs -gt 1) { throw 'unexpected publisher' } }
        }

        { Install-KutayWingetAndTerminal -WorkDirectory $script:work } | Should -Throw '*publisher*'
        Should -Invoke -ModuleName KutayApps Install-KutayAppPackage -Times 1 -Exactly -ParameterFilter { $PackageName -eq 'Microsoft.DesktopAppInstaller' }
        Should -Invoke -ModuleName KutayApps Install-KutayAppPackage -Times 0 -Exactly -ParameterFilter { $PackageName -eq 'Microsoft.WindowsTerminal' }
    }

    It 'installs nothing when a signature is wrong' {
        Mock -ModuleName KutayApps Assert-KutayMicrosoftSignature { throw 'unexpected publisher' }
        { Install-KutayWingetAndTerminal -WorkDirectory $script:work } | Should -Throw '*publisher*'
        Should -Invoke -ModuleName KutayApps Install-KutayAppPackage -Times 0 -Exactly
    }

    It 'removes its work directory afterwards, also after a failure' {
        Mock -ModuleName KutayApps Assert-KutayMicrosoftSignature { throw 'unexpected publisher' }
        { Install-KutayWingetAndTerminal -WorkDirectory $script:work } | Should -Throw
        Test-Path -LiteralPath $script:work | Should -BeFalse
    }
}

Describe 'Invoke-KutayTerminalUpdate' {
    BeforeEach {
        Mock -ModuleName KutayApps Write-KutayUserLog { }
    }

    It 'does nothing and succeeds when winget is not installed yet' {
        Mock -ModuleName KutayApps Get-KutayWingetPath { $null }
        Mock -ModuleName KutayApps Invoke-KutayWinget { 0 }

        Invoke-KutayTerminalUpdate | Should -Be 0
        Should -Invoke -ModuleName KutayApps Invoke-KutayWinget -Times 0 -Exactly
    }

    It 'asks winget to upgrade only Windows Terminal, silently, from the winget source' {
        Mock -ModuleName KutayApps Get-KutayWingetPath { 'C:\winget.exe' }
        Mock -ModuleName KutayApps Invoke-KutayWinget { 0 }

        Invoke-KutayTerminalUpdate | Should -Be 0

        Should -Invoke -ModuleName KutayApps Invoke-KutayWinget -Times 1 -Exactly -ParameterFilter {
            $WingetPath -eq 'C:\winget.exe' -and
            ($ArgumentList -join ' ') -eq 'upgrade --id Microsoft.WindowsTerminal --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity'
        }
    }

    It 'treats "no applicable update" as success' {
        Mock -ModuleName KutayApps Get-KutayWingetPath { 'C:\winget.exe' }
        Mock -ModuleName KutayApps Invoke-KutayWinget { -1978335189 }

        Invoke-KutayTerminalUpdate | Should -Be 0
    }

    It 'does not hide that winget cannot see Terminal as installed for this user' {
        Mock -ModuleName KutayApps Get-KutayWingetPath { 'C:\winget.exe' }
        Mock -ModuleName KutayApps Invoke-KutayWinget { -1978335212 }

        Invoke-KutayTerminalUpdate | Should -Be 2
        Should -Invoke -ModuleName KutayApps Write-KutayUserLog -ParameterFilter { $Message -like '*as installed*' }
    }

    It 'fails with 3 and logs the reason when winget cannot be started' {
        Mock -ModuleName KutayApps Get-KutayWingetPath { 'C:\winget.exe' }
        Mock -ModuleName KutayApps Invoke-KutayWinget { throw 'The term winget.exe is not recognized' }

        Invoke-KutayTerminalUpdate | Should -Be 3
        Should -Invoke -ModuleName KutayApps Write-KutayUserLog -ParameterFilter { $Message -like '*not recognized*' }
    }

    It 'returns winget''s exit code when the upgrade fails' {
        Mock -ModuleName KutayApps Get-KutayWingetPath { 'C:\winget.exe' }
        Mock -ModuleName KutayApps Invoke-KutayWinget { 1603 }

        Invoke-KutayTerminalUpdate | Should -Be 1603
    }
}

Describe 'Invoke-KutayWinget' {
    It 'returns the exit code of the program' {
        InModuleScope KutayApps {
            Invoke-KutayWinget -WingetPath 'cmd.exe' -ArgumentList '/c', 'exit 5' | Should -Be 5
        }
    }

    It 'throws when the program cannot be started, instead of returning a stale exit code' {
        InModuleScope KutayApps {
            $global:LASTEXITCODE = 0
            { Invoke-KutayWinget -WingetPath 'C:\kutay-test-missing\winget.exe' -ArgumentList 'x' } | Should -Throw
        }
    }

    It 'logs the last output lines when the program fails' {
        InModuleScope KutayApps {
            Mock Write-KutayUserLog { }
            Invoke-KutayWinget -WingetPath 'cmd.exe' -ArgumentList '/c', 'echo source unreachable& exit 7' | Should -Be 7
            Should -Invoke Write-KutayUserLog -ParameterFilter { $Message -like '*source unreachable*' }
        }
    }
}

Describe 'Get-KutayUpdateTaskName' {
    It 'is the task the snapshot, the revert and the registration all use' {
        Get-KutayUpdateTaskName | Should -Be '\KutayOS\Update Windows Terminal'
    }
}

Describe 'Expand-KutayArchive' {
    BeforeEach {
        $script:root = Join-Path ([IO.Path]::GetTempPath()) "kutay-zip-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $script:root | Out-Null
        $script:zip = Join-Path $script:root 'a.zip'
        $script:out = Join-Path $script:root 'out'
    }
    AfterEach { Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    BeforeAll {
        $script:newZip = {
            param([string]$Path, [string[]]$EntryName)
            Add-Type -AssemblyName System.IO.Compression
            $stream = [IO.File]::Create($Path)
            $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
            foreach ($name in $EntryName) {
                $writer = [IO.StreamWriter]::new($archive.CreateEntry($name).Open())
                $writer.Write('x')
                $writer.Dispose()
            }
            $archive.Dispose()
            $stream.Dispose()
        }
    }

    It 'extracts files and sub folders' {
        & $script:newZip $script:zip @('a.txt', 'sub/b.txt')

        Expand-KutayArchive -Path $script:zip -Destination $script:out

        Test-Path (Join-Path $script:out 'a.txt') | Should -BeTrue
        Test-Path (Join-Path $script:out 'sub\b.txt') | Should -BeTrue
    }

    It 'refuses an entry that would be written outside the destination: <Entry>' -ForEach @(
        @{ Entry = '../evil.txt' }
        @{ Entry = '..\evil.txt' }
        @{ Entry = 'sub/../../evil.txt' }
    ) {
        & $script:newZip $script:zip @($Entry)

        { Expand-KutayArchive -Path $script:zip -Destination $script:out } | Should -Throw '*outside*'
        Test-Path (Join-Path $script:root 'evil.txt') | Should -BeFalse
    }
}

Describe 'New-KutayWorkDirectory' {
    It 'lives under the KutayOS folder, not in a user writable temp folder' {
        InModuleScope KutayApps {
            (Get-KutayDefaultWorkDirectory) | Should -BeLike (Join-Path $env:windir 'KutayOS\Work\*')
        }
    }
}

Describe 'Register-KutayUpdateTask' {
    BeforeEach {
        Mock -ModuleName KutayApps Register-ScheduledTask { }
        Mock -ModuleName KutayApps Get-KutayDesktopPath { 'C:\Windows\KutayOS\KutayDesktop' }
        Mock -ModuleName KutayApps Test-Path { $true }
    }

    It 'refuses to register a task whose script is not there' {
        Mock -ModuleName KutayApps Test-Path { $false }

        { Register-KutayUpdateTask } | Should -Throw '*Update-KutayTerminal.ps1*'
        Should -Invoke -ModuleName KutayApps Register-ScheduledTask -Times 0 -Exactly
    }

    It 'starts the task with the full path of Windows PowerShell' {
        Register-KutayUpdateTask

        Should -Invoke -ModuleName KutayApps Register-ScheduledTask -Times 1 -Exactly -ParameterFilter {
            $Action.Execute -eq (Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe')
        }
    }

    It 'registers one task under \KutayOS that runs the update script for every user, without elevation' {
        Register-KutayUpdateTask

        Should -Invoke -ModuleName KutayApps Register-ScheduledTask -Times 1 -Exactly -ParameterFilter {
            $TaskPath -eq '\KutayOS\' -and $TaskName -eq 'Update Windows Terminal' -and
            $Principal.LogonType -eq 'Group' -and $Principal.RunLevel -eq 'Limited' -and
            $Action.Arguments -like '*Update-KutayTerminal.ps1*' -and $Action.Arguments -like '*-WindowStyle Hidden*'
        }
    }

    It 'runs at logon and once a day' {
        Register-KutayUpdateTask

        Should -Invoke -ModuleName KutayApps Register-ScheduledTask -Times 1 -Exactly -ParameterFilter {
            @($Trigger).Count -eq 2 -and
            (@($Trigger | ForEach-Object { $_.CimClass.CimClassName }) -contains 'MSFT_TaskLogonTrigger') -and
            (@($Trigger | ForEach-Object { $_.CimClass.CimClassName }) -contains 'MSFT_TaskDailyTrigger')
        }
    }
}
