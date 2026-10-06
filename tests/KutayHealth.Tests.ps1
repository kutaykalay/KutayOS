BeforeAll {
    $modules = Join-Path $PSScriptRoot '..\src\playbook\Executables\KutayModules'
    Import-Module (Join-Path $modules 'KutayState.psm1') -Force
    Import-Module (Join-Path $modules 'KutayHealth.psm1') -Force

    $script:WebView2Machine = 'HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    $script:WebView2User = 'HKCU\Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'

    function New-RegistryResult($Data) {
        if ($null -eq $Data) { return [pscustomobject]@{ exists = $false; type = $null; data = $null } }
        [pscustomobject]@{ exists = $true; type = 'String'; data = $Data }
    }
    function New-Service([string]$Name, [string]$Status = 'Running', [string]$StartType = 'Manual') {
        [pscustomobject]@{ Name = $Name; Status = $Status; StartType = $StartType }
    }
}

AfterAll {
    Remove-Module KutayHealth, KutayState -ErrorAction SilentlyContinue
}

Describe 'Test-KutayWebView2' {
    It 'passes with the per-machine runtime version' {
        Mock -ModuleName KutayHealth Read-KutayRegistryValue { New-RegistryResult '141.0.3537.57' } -ParameterFilter { $Path -eq $script:WebView2Machine }
        Mock -ModuleName KutayHealth Read-KutayRegistryValue { New-RegistryResult $null } -ParameterFilter { $Path -eq $script:WebView2User }

        $check = Test-KutayWebView2

        $check.status | Should -Be 'Pass'
        $check.detail | Should -BeLike '*141.0.3537.57*'
    }

    It 'passes with only a per-user runtime' {
        Mock -ModuleName KutayHealth Read-KutayRegistryValue { New-RegistryResult $null } -ParameterFilter { $Path -eq $script:WebView2Machine }
        Mock -ModuleName KutayHealth Read-KutayRegistryValue { New-RegistryResult '140.0.1.2' } -ParameterFilter { $Path -eq $script:WebView2User }

        (Test-KutayWebView2).status | Should -Be 'Pass'
    }

    It 'fails when pv is <Case>' -TestCases @(
        @{ Case = 'missing'; Data = $null }
        @{ Case = 'empty'; Data = '' }
        @{ Case = '0.0.0.0'; Data = '0.0.0.0' }
        @{ Case = 'not a version'; Data = 'abc' }
    ) {
        param($Data)
        Mock -ModuleName KutayHealth Read-KutayRegistryValue { New-RegistryResult $Data }

        (Test-KutayWebView2).status | Should -Be 'Fail'
    }
}

Describe 'Test-KutayDefender' {
    BeforeEach {
        $script:defender = [pscustomobject]@{
            AMServiceEnabled          = $true
            AntivirusEnabled          = $true
            RealTimeProtectionEnabled = $true
            AntivirusSignatureAge     = 1
        }
        Mock -ModuleName KutayHealth Get-KutayDefenderStatus { $script:defender }
    }

    It 'passes when the engine, antivirus and real-time protection are on' {
        (Test-KutayDefender).status | Should -Be 'Pass'
    }

    It 'fails when <Property> is off' -TestCases @(
        @{ Property = 'AMServiceEnabled' }
        @{ Property = 'AntivirusEnabled' }
        @{ Property = 'RealTimeProtectionEnabled' }
    ) {
        param($Property)
        $script:defender.$Property = $false

        $check = Test-KutayDefender

        $check.status | Should -Be 'Fail'
        $check.detail | Should -BeLike "*$Property*"
    }

    It 'warns when signatures are older than a week' {
        $script:defender.AntivirusSignatureAge = 8

        $check = Test-KutayDefender

        $check.status | Should -Be 'Warn'
        $check.detail | Should -BeLike '*8 days*'
    }

    It 'warns when the signature age is unknown' {
        $script:defender.AntivirusSignatureAge = $null

        (Test-KutayDefender).status | Should -Be 'Warn'
    }

    It 'reads a never-updated signature age without overflow' {
        $script:defender.AntivirusSignatureAge = [uint32]::MaxValue

        (Test-KutayDefender).status | Should -Be 'Warn'
    }

    It 'warns when Defender runs in <Mode> mode next to another antivirus' -TestCases @(
        @{ Mode = 'Passive' }
        @{ Mode = 'SxS Passive Mode' }
    ) {
        param($Mode)
        $script:defender | Add-Member -NotePropertyName AMRunningMode -NotePropertyValue $Mode
        $script:defender.RealTimeProtectionEnabled = $false

        $check = Test-KutayDefender

        $check.status | Should -Be 'Warn'
        $check.detail | Should -BeLike "*$Mode*"
    }

    It 'fails instead of throwing when the status lacks a property' {
        Mock -ModuleName KutayHealth Get-KutayDefenderStatus { [pscustomobject]@{ AMServiceEnabled = $true } }

        (Test-KutayDefender).status | Should -Be 'Fail'
    }

    It 'fails when Defender returns no status' {
        Mock -ModuleName KutayHealth Get-KutayDefenderStatus { }

        (Test-KutayDefender).status | Should -Be 'Fail'
    }

    It 'fails when Defender cannot be queried' {
        Mock -ModuleName KutayHealth Get-KutayDefenderStatus { throw 'Invalid class' }

        $check = Test-KutayDefender

        $check.status | Should -Be 'Fail'
        $check.detail | Should -BeLike '*Invalid class*'
    }
}

Describe 'Test-KutayWindowsUpdate' {
    BeforeEach {
        Mock -ModuleName KutayHealth Get-Service {
            @('wuauserv', 'BITS', 'UsoSvc', 'CryptSvc') | ForEach-Object { New-Service $_ }
        }
        Mock -ModuleName KutayHealth Invoke-KutayUpdateSearch { [pscustomobject]@{ resultCode = 2; pending = 3 } }
    }

    It 'passes when the services can start and the update search succeeds' {
        $check = Test-KutayWindowsUpdate

        $check.status | Should -Be 'Pass'
        $check.detail | Should -BeLike '*3 *'
    }

    It 'fails when an update service is disabled' {
        Mock -ModuleName KutayHealth Get-Service {
            New-Service 'wuauserv' -StartType 'Disabled'
            @('BITS', 'UsoSvc', 'CryptSvc') | ForEach-Object { New-Service $_ }
        }

        $check = Test-KutayWindowsUpdate

        $check.status | Should -Be 'Fail'
        $check.detail | Should -BeLike '*wuauserv*'
        Should -Invoke -ModuleName KutayHealth Invoke-KutayUpdateSearch -Times 0
    }

    It 'fails when an update service is missing' {
        Mock -ModuleName KutayHealth Get-Service { @('wuauserv', 'BITS', 'CryptSvc') | ForEach-Object { New-Service $_ } }

        (Test-KutayWindowsUpdate).detail | Should -BeLike '*UsoSvc*'
    }

    It 'warns when the search succeeded with errors' {
        Mock -ModuleName KutayHealth Invoke-KutayUpdateSearch { [pscustomobject]@{ resultCode = 3; pending = 0 } }

        (Test-KutayWindowsUpdate).status | Should -Be 'Warn'
    }

    It 'fails when the search result is <Code>' -TestCases @(@{ Code = 4 }, @{ Code = 5 }) {
        param($Code)
        Mock -ModuleName KutayHealth Invoke-KutayUpdateSearch { [pscustomobject]@{ resultCode = $Code; pending = 0 } }

        (Test-KutayWindowsUpdate).status | Should -Be 'Fail'
    }

    It 'fails with the error when the search throws' {
        Mock -ModuleName KutayHealth Invoke-KutayUpdateSearch { throw 'Exception from HRESULT: 0x8024402C' }

        $check = Test-KutayWindowsUpdate

        $check.status | Should -Be 'Fail'
        $check.detail | Should -BeLike '*0x8024402C*'
    }
}

Describe 'Test-KutaySearch' {
    BeforeEach {
        Mock -ModuleName KutayHealth Get-Service { New-Service 'WSearch' -StartType 'Automatic' }
        Mock -ModuleName KutayHealth Invoke-KutaySearchQuery { 1 }
    }

    It 'passes when the indexer runs and the index returns results' {
        (Test-KutaySearch).status | Should -Be 'Pass'
    }

    It 'fails when the indexer is <Case>' -TestCases @(
        @{ Case = 'stopped'; Status = 'Stopped'; StartType = 'Automatic' }
        @{ Case = 'disabled'; Status = 'Stopped'; StartType = 'Disabled' }
    ) {
        param($Status, $StartType)
        Mock -ModuleName KutayHealth Get-Service { New-Service 'WSearch' -Status $Status -StartType $StartType }

        (Test-KutaySearch).status | Should -Be 'Fail'
        Should -Invoke -ModuleName KutayHealth Invoke-KutaySearchQuery -Times 0
    }

    It 'fails when the indexer service is missing' {
        Mock -ModuleName KutayHealth Get-Service { }

        (Test-KutaySearch).status | Should -Be 'Fail'
    }

    It 'warns when the index is still empty' {
        Mock -ModuleName KutayHealth Invoke-KutaySearchQuery { 0 }

        (Test-KutaySearch).status | Should -Be 'Warn'
    }

    It 'fails with the error when the query throws' {
        Mock -ModuleName KutayHealth Invoke-KutaySearchQuery { throw 'Provider cannot be found' }

        $check = Test-KutaySearch

        $check.status | Should -Be 'Fail'
        $check.detail | Should -BeLike '*Provider cannot be found*'
    }
}

Describe 'Invoke-KutayHealthCheck' {
    It 'runs every check in a fixed order' {
        Mock -ModuleName KutayHealth Test-KutayWindowsUpdate { [pscustomobject]@{ name = 'Windows Update'; status = 'Pass'; detail = '' } }
        Mock -ModuleName KutayHealth Test-KutayDefender { [pscustomobject]@{ name = 'Defender'; status = 'Fail'; detail = '' } }
        Mock -ModuleName KutayHealth Test-KutaySearch { [pscustomobject]@{ name = 'Search'; status = 'Warn'; detail = '' } }
        Mock -ModuleName KutayHealth Test-KutayWebView2 { [pscustomobject]@{ name = 'WebView2'; status = 'Pass'; detail = '' } }

        $checks = @(Invoke-KutayHealthCheck)

        $checks.name | Should -Be @('Windows Update', 'Defender', 'Search', 'WebView2')
    }

    It 'turns a check that throws into a failed check and runs the rest' {
        Mock -ModuleName KutayHealth Test-KutayWindowsUpdate { throw 'boom' }
        Mock -ModuleName KutayHealth Test-KutayDefender { [pscustomobject]@{ name = 'Defender'; status = 'Pass'; detail = '' } }
        Mock -ModuleName KutayHealth Test-KutaySearch { [pscustomobject]@{ name = 'Search'; status = 'Pass'; detail = '' } }
        Mock -ModuleName KutayHealth Test-KutayWebView2 { [pscustomobject]@{ name = 'WebView2'; status = 'Pass'; detail = '' } }

        $checks = @(Invoke-KutayHealthCheck)

        $checks.Count | Should -Be 4
        $checks[0].status | Should -Be 'Fail'
        $checks[0].detail | Should -BeLike '*boom*'
    }
}
