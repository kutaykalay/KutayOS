[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester passes these variables between its blocks')]
param()

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\tools\KutayTweak.psm1') -Force
}

AfterAll {
    Remove-Module KutayTweak -ErrorAction SilentlyContinue
}

Describe 'Get-KutayTweakChange' {
    It 'returns every registry value a tweak sets, with the tweak id' {
        $file = Join-Path $TestDrive 'disable-thing.yml'
        Set-Content -LiteralPath $file -Value @(
            'title: Thing off'
            'actions:'
            "  - !registryValue: {path: 'HKLM\SOFTWARE\Policies\A', value: 'One', type: REG_DWORD, data: '0'}"
            "  - !registryValue: {path: 'HKLM\SOFTWARE\Policies\B C', value: 'Two', type: REG_SZ, data: 'x y'}"
        )

        $changes = @(Get-KutayTweakChange -Path $file)

        $changes.Count | Should -Be 2
        $changes[0].id | Should -Be 'disable-thing'
        $changes[0].path | Should -Be 'HKLM\SOFTWARE\Policies\A'
        $changes[0].name | Should -Be 'One'
        $changes[0].type | Should -Be 'REG_DWORD'
        $changes[0].data | Should -Be '0'
        $changes[1].path | Should -Be 'HKLM\SOFTWARE\Policies\B C'
        $changes[1].data | Should -Be 'x y'
    }

    It 'returns nothing for a tweak without registry values' {
        $file = Join-Path $TestDrive 'empty.yml'
        Set-Content -LiteralPath $file -Value @('title: Empty', 'actions: []')

        @(Get-KutayTweakChange -Path $file).Count | Should -Be 0
    }

    It 'rejects a registry value whose type it cannot check' {
        $file = Join-Path $TestDrive 'odd.yml'
        Set-Content -LiteralPath $file -Value "  - !registryValue: {path: 'HKLM\X', value: 'V', type: REG_BINARY, data: '00'}"

        { Get-KutayTweakChange -Path $file } | Should -Throw '*REG_BINARY*'
    }
}

Describe 'Get-KutayTweakCommand' {
    It 'returns each PowerShell command as AME runs it, with YAML quote escapes undone' {
        $file = Join-Path $TestDrive 'cmd.yml'
        Set-Content -LiteralPath $file -Value @(
            '  - !powerShell:'
            "    command: '.\KutayModules\Save-KutayState.ps1 -Id x -Registry ''HKLM\A|B'',''HKLM\C D|E'''"
            '    exeDir: true'
            "  - !registryValue: {path: 'HKLM\A', value: 'B', type: REG_DWORD, data: '1'}"
        )

        Get-KutayTweakCommand -Path $file |
            Should -Be ".\KutayModules\Save-KutayState.ps1 -Id x -Registry 'HKLM\A|B','HKLM\C D|E'"
    }
}

Describe 'Get-KutayTweakUserChange' {
    It 'returns every per-user setting a tweak writes, with the tweak id' {
        $file = Join-Path $TestDrive 'hide-thing.yml'
        Set-Content -LiteralPath $file -Value @(
            '  - !powerShell:'
            "    command: '.\KutayModules\Set-KutayUserSetting.ps1 -Id hide-thing -Setting ''Software\A B|One|DWord|0'',''Software\C|Two|String|x y'''"
        )

        $changes = @(Get-KutayTweakUserChange -Path $file)

        $changes.Count | Should -Be 2
        $changes[0].id | Should -Be 'hide-thing'
        $changes[0].path | Should -Be 'Software\A B'
        $changes[0].name | Should -Be 'One'
        $changes[0].type | Should -Be 'DWord'
        $changes[0].data | Should -Be '0'
        $changes[1].type | Should -Be 'String'
        $changes[1].data | Should -Be 'x y'
    }

    It 'ignores commands that are not Set-KutayUserSetting' {
        $file = Join-Path $TestDrive 'other.yml'
        Set-Content -LiteralPath $file -Value "    command: '.\KutayModules\Save-KutayState.ps1 -Id x -Registry ''HKLM\A|B'''"

        @(Get-KutayTweakUserChange -Path $file).Count | Should -Be 0
    }
}

Describe 'Get-KutayTaskPath' {
    It 'lists the task files a root task runs, in order' {
        $file = Join-Path $TestDrive 'custom.yml'
        Set-Content -LiteralPath $file -Value @(
            'actions:'
            "  - !task: {path: 'tweaks\privacy\b.yml'}"
            "  - !writeStatus: {status: 'x'}"
            "  - !task: {path: 'tweaks\privacy\a.yml'}"
        )

        Get-KutayTaskPath -Path $file | Should -Be @('tweaks\privacy\b.yml', 'tweaks\privacy\a.yml')
    }
}

Describe 'Playbook wiring' {
    It 'runs every tweak file from the root task' {
        $config = Join-Path $PSScriptRoot '..\src\playbook\Configuration'
        $wired = @(Get-KutayTaskPath -Path (Join-Path $config 'custom.yml'))
        $tweaks = @(Get-ChildItem -LiteralPath (Join-Path $config 'tweaks') -Recurse -Filter *.yml |
                ForEach-Object { 'tweaks\{0}\{1}' -f $_.Directory.Name, $_.Name })

        foreach ($tweak in $tweaks) { $wired | Should -Contain $tweak }
    }

    It 'offers every option a tweak uses on a FeaturePage, at most 4 per page' {
        $playbook = Join-Path $PSScriptRoot '..\src\playbook'
        $conf = [xml](Get-Content -LiteralPath (Join-Path $playbook 'playbook.conf') -Raw)
        $pages = @($conf.Playbook.FeaturePages.ChildNodes | Where-Object { $_.NodeType -eq 'Element' })
        $offered = @($pages | ForEach-Object { @($_.Options.ChildNodes | Where-Object { $_.NodeType -eq 'Element' }) } |
                ForEach-Object { $_.Name })
        $used = @(Get-ChildItem -LiteralPath (Join-Path $playbook 'Configuration\tweaks') -Recurse -Filter *.yml |
                ForEach-Object { [regex]::Matches((Get-Content -LiteralPath $_.FullName -Raw), "(?m)^\s*option:\s*'([^']+)'") } |
                ForEach-Object { $_.Groups[1].Value })

        foreach ($page in $pages) { @($page.Options.ChildNodes | Where-Object { $_.NodeType -eq 'Element' }).Count | Should -BeLessOrEqual 4 }
        foreach ($option in $used) { $offered | Should -Contain $option }
        foreach ($option in $offered) { $used | Should -Contain $option -Because 'an option nothing uses does nothing' }
    }
}
