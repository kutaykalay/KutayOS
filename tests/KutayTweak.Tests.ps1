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
}
