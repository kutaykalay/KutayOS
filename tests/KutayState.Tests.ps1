[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester passes these variables between its blocks')]
param()

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\src\playbook\Executables\KutayModules\KutayState.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module KutayState -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-KutayProviderPath' {
    It 'maps <Short> to the registry provider path' -ForEach @(
        @{ Short = 'HKLM\SOFTWARE\Foo'; Long = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Foo' }
        @{ Short = 'HKCU\Software\Foo'; Long = 'Registry::HKEY_CURRENT_USER\Software\Foo' }
        @{ Short = 'HKU\.DEFAULT\Foo'; Long = 'Registry::HKEY_USERS\.DEFAULT\Foo' }
    ) {
        InModuleScope KutayState -Parameters @{ Short = $Short; Long = $Long } {
            ConvertTo-KutayProviderPath $Short | Should -Be $Long
        }
    }

    It 'rejects an unknown hive' {
        InModuleScope KutayState {
            { ConvertTo-KutayProviderPath 'HKXX\Foo' } | Should -Throw '*hive*'
        }
    }
}

Describe 'Save-KutaySnapshot' {
    BeforeEach {
        InModuleScope KutayState -Parameters @{ Root = $TestDrive } { $script:StateRoot = $Root }
        Get-ChildItem $TestDrive -Filter *.json | Remove-Item
    }

    It 'records an existing value with its type and data' {
        Mock -ModuleName KutayState Read-KutayRegistryValue {
            [pscustomobject]@{ exists = $true; type = 'DWord'; data = 1 }
        }

        Save-KutaySnapshot -Id 'disable-telemetry' -Registry 'HKLM\SOFTWARE\Test|AllowTelemetry'

        $json = Get-Content (Join-Path $TestDrive 'disable-telemetry.json') -Raw | ConvertFrom-Json
        $json.id | Should -Be 'disable-telemetry'
        $json.registry[0].path | Should -Be 'HKLM\SOFTWARE\Test'
        $json.registry[0].name | Should -Be 'AllowTelemetry'
        $json.registry[0].exists | Should -BeTrue
        $json.registry[0].type | Should -Be 'DWord'
        $json.registry[0].data | Should -Be 1
    }

    It 'records a missing value as not existing' {
        Mock -ModuleName KutayState Read-KutayRegistryValue {
            [pscustomobject]@{ exists = $false; type = $null; data = $null }
        }

        Save-KutaySnapshot -Id 'disable-telemetry' -Registry 'HKLM\SOFTWARE\Test|AllowTelemetry'

        $json = Get-Content (Join-Path $TestDrive 'disable-telemetry.json') -Raw | ConvertFrom-Json
        $json.registry[0].exists | Should -BeFalse
    }

    It 'records several values in order' {
        Mock -ModuleName KutayState Read-KutayRegistryValue {
            [pscustomobject]@{ exists = $true; type = 'String'; data = $Name }
        }

        Save-KutaySnapshot -Id 'two-values' -Registry 'HKLM\SOFTWARE\A|First', 'HKCU\Software\B|Second'

        $json = Get-Content (Join-Path $TestDrive 'two-values.json') -Raw | ConvertFrom-Json
        @($json.registry).Count | Should -Be 2
        $json.registry[1].path | Should -Be 'HKCU\Software\B'
        $json.registry[1].data | Should -Be 'Second'
    }

    It 'keeps the first snapshot when run twice' {
        Mock -ModuleName KutayState Read-KutayRegistryValue {
            [pscustomobject]@{ exists = $false; type = $null; data = $null }
        }
        Save-KutaySnapshot -Id 'disable-telemetry' -Registry 'HKLM\SOFTWARE\Test|AllowTelemetry'

        # Second run: the value now holds what KutayOS wrote; it must not become the "original".
        Mock -ModuleName KutayState Read-KutayRegistryValue {
            [pscustomobject]@{ exists = $true; type = 'DWord'; data = 0 }
        }
        Save-KutaySnapshot -Id 'disable-telemetry' -Registry 'HKLM\SOFTWARE\Test|AllowTelemetry'

        $json = Get-Content (Join-Path $TestDrive 'disable-telemetry.json') -Raw | ConvertFrom-Json
        $json.registry[0].exists | Should -BeFalse
    }

    It 'rejects an id that is not a plain name' -ForEach @(
        @{ Id = '..\evil' }, @{ Id = 'Has Space' }, @{ Id = 'UPPER' }, @{ Id = '' }
    ) {
        { Save-KutaySnapshot -Id $Id -Registry 'HKLM\SOFTWARE\Test|X' } | Should -Throw
    }

    It 'rejects a registry item without a value name' {
        { Save-KutaySnapshot -Id 'bad-item' -Registry 'HKLM\SOFTWARE\Test' } | Should -Throw '*path|name*'
    }
}

Describe 'Restore-KutaySnapshot' {
    BeforeEach {
        InModuleScope KutayState -Parameters @{ Root = $TestDrive } { $script:StateRoot = $Root }
        Get-ChildItem $TestDrive -Filter *.json | Remove-Item
        Mock -ModuleName KutayState Set-KutayRegistryValue { }
        Mock -ModuleName KutayState Remove-KutayRegistryValue { }
    }

    It 'writes back a value that existed and removes the snapshot' {
        Mock -ModuleName KutayState Read-KutayRegistryValue {
            [pscustomobject]@{ exists = $true; type = 'DWord'; data = 3 }
        }
        Save-KutaySnapshot -Id 'disable-telemetry' -Registry 'HKLM\SOFTWARE\Test|AllowTelemetry'

        Restore-KutaySnapshot -Id 'disable-telemetry'

        Should -Invoke -ModuleName KutayState Set-KutayRegistryValue -Times 1 -Exactly -ParameterFilter {
            $Path -eq 'HKLM\SOFTWARE\Test' -and $Name -eq 'AllowTelemetry' -and $Type -eq 'DWord' -and $Data -eq 3
        }
        Should -Invoke -ModuleName KutayState Remove-KutayRegistryValue -Times 0 -Exactly
        Join-Path $TestDrive 'disable-telemetry.json' | Should -Not -Exist
    }

    It 'removes a value that did not exist before' {
        Mock -ModuleName KutayState Read-KutayRegistryValue {
            [pscustomobject]@{ exists = $false; type = $null; data = $null }
        }
        Save-KutaySnapshot -Id 'disable-telemetry' -Registry 'HKLM\SOFTWARE\Test|AllowTelemetry'

        Restore-KutaySnapshot -Id 'disable-telemetry'

        Should -Invoke -ModuleName KutayState Remove-KutayRegistryValue -Times 1 -Exactly -ParameterFilter {
            $Path -eq 'HKLM\SOFTWARE\Test' -and $Name -eq 'AllowTelemetry'
        }
        Should -Invoke -ModuleName KutayState Set-KutayRegistryValue -Times 0 -Exactly
    }

    It 'restores a multi-string value as an array' {
        Mock -ModuleName KutayState Read-KutayRegistryValue {
            [pscustomobject]@{ exists = $true; type = 'MultiString'; data = @('a', 'b') }
        }
        Save-KutaySnapshot -Id 'multi' -Registry 'HKLM\SOFTWARE\Test|List'

        Restore-KutaySnapshot -Id 'multi'

        Should -Invoke -ModuleName KutayState Set-KutayRegistryValue -Times 1 -Exactly -ParameterFilter {
            $Type -eq 'MultiString' -and @($Data).Count -eq 2 -and $Data[1] -eq 'b'
        }
    }

    It 'does nothing when there is no snapshot' {
        { Restore-KutaySnapshot -Id 'never-applied' } | Should -Not -Throw

        Should -Invoke -ModuleName KutayState Set-KutayRegistryValue -Times 0 -Exactly
        Should -Invoke -ModuleName KutayState Remove-KutayRegistryValue -Times 0 -Exactly
    }

    It 'keeps the snapshot when a value cannot be restored' {
        Mock -ModuleName KutayState Read-KutayRegistryValue {
            [pscustomobject]@{ exists = $true; type = 'DWord'; data = 1 }
        }
        Save-KutaySnapshot -Id 'disable-telemetry' -Registry 'HKLM\SOFTWARE\Test|AllowTelemetry'
        Mock -ModuleName KutayState Set-KutayRegistryValue { throw 'access denied' }

        { Restore-KutaySnapshot -Id 'disable-telemetry' } | Should -Throw '*access denied*'
        Join-Path $TestDrive 'disable-telemetry.json' | Should -Exist
    }
}

Describe 'Registry access' {
    BeforeAll {
        # A stand-in for a RegistryKey: only the members the module uses.
        function Get-FakeKey([hashtable]$Values, [hashtable]$Kinds) {
            $key = [pscustomobject]@{ Values = $Values; Kinds = $Kinds }
            $key | Add-Member ScriptMethod GetValueNames { @($this.Values.Keys) }
            $key | Add-Member ScriptMethod GetValueKind { [Microsoft.Win32.RegistryValueKind]$this.Kinds[$args[0]] }
            $key | Add-Member ScriptMethod GetValue { $this.Values[$args[0]] }
            $key
        }
    }

    Context 'Read-KutayRegistryValue' {
        It 'reports a missing key as not existing' {
            Mock -ModuleName KutayState Get-Item { }

            $r = Read-KutayRegistryValue -Path 'HKLM\SOFTWARE\Test' -Name 'X'

            $r.exists | Should -BeFalse
        }

        It 'reports a missing value as not existing' {
            $key = Get-FakeKey @{ Other = 1 } @{ Other = 'DWord' }
            Mock -ModuleName KutayState Get-Item { $key }

            (Read-KutayRegistryValue -Path 'HKLM\SOFTWARE\Test' -Name 'X').exists | Should -BeFalse
        }

        It 'reads the type and data of a value' {
            $key = Get-FakeKey @{ X = 7 } @{ X = 'DWord' }
            Mock -ModuleName KutayState Get-Item { $key }

            $r = Read-KutayRegistryValue -Path 'HKLM\SOFTWARE\Test' -Name 'X'

            $r.exists | Should -BeTrue
            $r.type | Should -Be 'DWord'
            $r.data | Should -Be 7
        }

        It 'reads the default value of a key as (default)' {
            $key = Get-FakeKey @{ '' = 'x' } @{ '' = 'String' }
            Mock -ModuleName KutayState Get-Item { $key }

            $r = Read-KutayRegistryValue -Path 'HKCU\Software\Test' -Name '(default)'

            $r.exists | Should -BeTrue
            $r.data | Should -Be 'x'
        }

        It 'stores binary data as base64 so it survives JSON' {
            $key = Get-FakeKey @{ B = [byte[]](1, 2, 3) } @{ B = 'Binary' }
            Mock -ModuleName KutayState Get-Item { $key }

            (Read-KutayRegistryValue -Path 'HKLM\SOFTWARE\Test' -Name 'B').data | Should -Be 'AQID'
        }
    }

    Context 'Set-KutayRegistryValue' {
        BeforeEach {
            Mock -ModuleName KutayState New-Item { }
            Mock -ModuleName KutayState New-ItemProperty { }
        }

        It 'does not recreate an existing key, which would wipe its values' {
            Mock -ModuleName KutayState Test-Path { $true }

            Set-KutayRegistryValue -Path 'HKLM\SOFTWARE\Test' -Name 'X' -Type DWord -Data 0

            Should -Invoke -ModuleName KutayState New-Item -Times 0 -Exactly
            Should -Invoke -ModuleName KutayState New-ItemProperty -Times 1 -Exactly -ParameterFilter {
                $LiteralPath -eq 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Test' -and $Name -eq 'X' -and
                $PropertyType -eq 'DWord' -and $Value -eq 0
            }
        }

        It 'creates a missing key first' {
            Mock -ModuleName KutayState Test-Path { $false }

            Set-KutayRegistryValue -Path 'HKLM\SOFTWARE\Test' -Name 'X' -Type String -Data 'a'

            Should -Invoke -ModuleName KutayState New-Item -Times 1 -Exactly
        }

        It 'decodes base64 back to bytes for binary values' {
            Mock -ModuleName KutayState Test-Path { $true }

            Set-KutayRegistryValue -Path 'HKLM\SOFTWARE\Test' -Name 'B' -Type Binary -Data 'AQID'

            Should -Invoke -ModuleName KutayState New-ItemProperty -Times 1 -Exactly -ParameterFilter {
                $Value -is [byte[]] -and $Value.Count -eq 3 -and $Value[2] -eq 3
            }
        }

        It 'writes a multi-string value as a string array' {
            Mock -ModuleName KutayState Test-Path { $true }

            Set-KutayRegistryValue -Path 'HKLM\SOFTWARE\Test' -Name 'M' -Type MultiString -Data @('a', 'b')

            Should -Invoke -ModuleName KutayState New-ItemProperty -Times 1 -Exactly -ParameterFilter {
                $Value -is [string[]] -and $Value.Count -eq 2
            }
        }

        It 'throws on a non-terminating write error, so a revert never looks successful' {
            Mock -ModuleName KutayState Test-Path { $true }
            Mock -ModuleName KutayState New-ItemProperty {
                # Behave like a cmdlet: honour the -ErrorAction the module passes.
                $action = 'Continue'
                if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $action = $PesterBoundParameters['ErrorAction'] }
                Write-Error 'Requested registry access is not allowed.' -ErrorAction $action
            }

            { Set-KutayRegistryValue -Path 'HKLM\SOFTWARE\Test' -Name 'X' -Type DWord -Data 0 } |
                Should -Throw '*not allowed*'
        }

        It 'changes nothing with -WhatIf' {
            Mock -ModuleName KutayState Test-Path { $false }

            Set-KutayRegistryValue -Path 'HKLM\SOFTWARE\Test' -Name 'X' -Type DWord -Data 0 -WhatIf

            Should -Invoke -ModuleName KutayState New-Item -Times 0 -Exactly
            Should -Invoke -ModuleName KutayState New-ItemProperty -Times 0 -Exactly
        }
    }

    Context 'Remove-KutayEmptyKey' {
        BeforeEach {
            Mock -ModuleName KutayState Remove-Item { }
        }

        It 'removes empty keys from the path up to and including StopAt' {
            $empty = Get-FakeKey @{} @{}
            $empty | Add-Member ScriptProperty SubKeyCount { 0 }
            Mock -ModuleName KutayState Get-Item { $empty }

            Remove-KutayEmptyKey -Path 'HKCU\Software\A\B\C' -StopAt 'HKCU\Software\A\B'

            Should -Invoke -ModuleName KutayState Remove-Item -Times 2 -Exactly
            Should -Invoke -ModuleName KutayState Remove-Item -Times 1 -Exactly -ParameterFilter {
                $LiteralPath -eq 'Registry::HKEY_CURRENT_USER\Software\A\B'
            }
        }

        It 'keeps a key that still holds values' {
            $full = Get-FakeKey @{ X = 1 } @{ X = 'DWord' }
            $full | Add-Member ScriptProperty SubKeyCount { 0 }
            Mock -ModuleName KutayState Get-Item { $full }

            Remove-KutayEmptyKey -Path 'HKCU\Software\A\B\C' -StopAt 'HKCU\Software\A\B'

            Should -Invoke -ModuleName KutayState Remove-Item -Times 0 -Exactly
        }

        It 'refuses a StopAt that is not above the path' {
            { Remove-KutayEmptyKey -Path 'HKCU\Software\A' -StopAt 'HKCU\Software\Other' } | Should -Throw '*StopAt*'
        }
    }

    Context 'Remove-KutayRegistryValue' {
        BeforeEach {
            Mock -ModuleName KutayState Remove-ItemProperty { }
        }

        It 'removes a value that exists' {
            $key = Get-FakeKey @{ X = 1 } @{ X = 'DWord' }
            Mock -ModuleName KutayState Get-Item { $key }

            Remove-KutayRegistryValue -Path 'HKLM\SOFTWARE\Test' -Name 'X'

            Should -Invoke -ModuleName KutayState Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
                $LiteralPath -eq 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Test' -and $Name -eq 'X'
            }
        }

        It 'throws on a non-terminating remove error' {
            $key = Get-FakeKey @{ X = 1 } @{ X = 'DWord' }
            Mock -ModuleName KutayState Get-Item { $key }
            Mock -ModuleName KutayState Remove-ItemProperty {
                # Behave like a cmdlet: honour the -ErrorAction the module passes.
                $action = 'Continue'
                if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $action = $PesterBoundParameters['ErrorAction'] }
                Write-Error 'Requested registry access is not allowed.' -ErrorAction $action
            }

            { Remove-KutayRegistryValue -Path 'HKLM\SOFTWARE\Test' -Name 'X' } | Should -Throw '*not allowed*'
        }

        It 'removes the default value of a key' {
            $key = Get-FakeKey @{ '' = 'x' } @{ '' = 'String' }
            Mock -ModuleName KutayState Get-Item { $key }

            Remove-KutayRegistryValue -Path 'HKLM\SOFTWARE\Test' -Name '(default)'

            Should -Invoke -ModuleName KutayState Remove-ItemProperty -Times 1 -Exactly -ParameterFilter { $Name -eq '(default)' }
        }

        It 'does nothing when the value or key is already gone' {
            Mock -ModuleName KutayState Get-Item { }

            Remove-KutayRegistryValue -Path 'HKLM\SOFTWARE\Test' -Name 'X'

            Should -Invoke -ModuleName KutayState Remove-ItemProperty -Times 0 -Exactly
        }
    }
}

Describe 'Get-KutaySnapshotId' {
    It 'lists the ids of saved snapshots' {
        InModuleScope KutayState -Parameters @{ Root = $TestDrive } { $script:StateRoot = $Root }
        Get-ChildItem $TestDrive -Filter *.json | Remove-Item
        Mock -ModuleName KutayState Read-KutayRegistryValue {
            [pscustomobject]@{ exists = $false; type = $null; data = $null }
        }
        Save-KutaySnapshot -Id 'b-second' -Registry 'HKLM\SOFTWARE\Test|B'
        Save-KutaySnapshot -Id 'a-first' -Registry 'HKLM\SOFTWARE\Test|A'

        Get-KutaySnapshotId | Should -Be @('a-first', 'b-second')
    }

    It 'returns nothing when the state folder does not exist' {
        InModuleScope KutayState -Parameters @{ Root = (Join-Path $TestDrive 'missing') } { $script:StateRoot = $Root }

        @(Get-KutaySnapshotId).Count | Should -Be 0
    }
}

Describe 'Per-user snapshots' {
    BeforeEach {
        InModuleScope KutayState -Parameters @{ Root = $TestDrive } { $script:StateRoot = $Root }
        Get-ChildItem $TestDrive -Filter *.json | Remove-Item
        Mock -ModuleName KutayState Get-KutayUserHive {
            [pscustomobject]@{ user = 'S-1-5-21-100-1001'; file = 'C:\Users\PC\NTUSER.DAT'; classes = 'C:\Users\PC\UsrClass.dat' }
            [pscustomobject]@{ user = 'default'; file = 'C:\Users\Default\NTUSER.DAT'; classes = $null }
        }
        # Stands in for mounting: each hive gets a root named after its user. Like the real one,
        # -Classes skips a hive without a classes file.
        Mock -ModuleName KutayState Use-KutayUserHive {
            if (-not $Classes) { return & $Script "HKU\mount-$($Hive.user)" }
            if ($Hive.classes) { & $Script "HKU\mount-$($Hive.user)_Classes" }
        }
        Mock -ModuleName KutayState Set-KutayRegistryValue { }
        Mock -ModuleName KutayState Remove-KutayRegistryValue { }
        Mock -ModuleName KutayState Test-KutayRegistryKey { $true }
        Mock -ModuleName KutayState Remove-KutayEmptyKey { }
    }

    Context 'Software\Classes items' {
        BeforeEach {
            Mock -ModuleName KutayState Read-KutayRegistryValue { [pscustomobject]@{ exists = $false; type = $null; data = $null } }
            $item = 'Software\Classes\CLSID\{X}\InprocServer32'
        }

        It 'writes them to the classes hive of each user that has one' {
            Set-KutayUserSetting -Id 'classic-menu' -Setting "$item|(default)|String|"

            Should -Invoke -ModuleName KutayState Set-KutayRegistryValue -Times 1 -Exactly
            Should -Invoke -ModuleName KutayState Set-KutayRegistryValue -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'HKU\mount-S-1-5-21-100-1001_Classes\CLSID\{X}\InprocServer32' -and $Name -eq '(default)' -and
                $Type -eq 'String' -and $Data -eq ''
            }
        }

        It 'snapshots them under the path the tweak gave' {
            Save-KutayUserSnapshot -Id 'classic-menu' -Registry "$item|(default)"

            $json = Get-Content (Join-Path $TestDrive 'classic-menu.json') -Raw | ConvertFrom-Json
            @($json.users).Count | Should -Be 1
            $json.users[0].path | Should -Be $item
            Should -Invoke -ModuleName KutayState Read-KutayRegistryValue -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'HKU\mount-S-1-5-21-100-1001_Classes\CLSID\{X}\InprocServer32'
            }
        }

        It 'records the first key KutayOS has to create' {
            Mock -ModuleName KutayState Test-KutayRegistryKey { $Path -notlike '*\{X}*' }

            Save-KutayUserSnapshot -Id 'classic-menu' -Registry "$item|(default)"

            $json = Get-Content (Join-Path $TestDrive 'classic-menu.json') -Raw | ConvertFrom-Json
            $json.users[0].createdKey | Should -Be 'Software\Classes\CLSID\{X}'
        }

        It 'records no created key when the key exists' {
            Mock -ModuleName KutayState Test-KutayRegistryKey { $true }

            Save-KutayUserSnapshot -Id 'classic-menu' -Registry "$item|(default)"

            $json = Get-Content (Join-Path $TestDrive 'classic-menu.json') -Raw | ConvertFrom-Json
            $json.users[0].createdKey | Should -BeNullOrEmpty
        }

        It 'removes the keys it created on restore, up to the first one' {
            Mock -ModuleName KutayState Test-KutayRegistryKey { $Path -notlike '*\{X}*' }
            Mock -ModuleName KutayState Remove-KutayEmptyKey { }
            Save-KutayUserSnapshot -Id 'classic-menu' -Registry "$item|(default)"

            Restore-KutaySnapshot -Id 'classic-menu'

            Should -Invoke -ModuleName KutayState Remove-KutayEmptyKey -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'HKU\mount-S-1-5-21-100-1001_Classes\CLSID\{X}\InprocServer32' -and
                $StopAt -eq 'HKU\mount-S-1-5-21-100-1001_Classes\CLSID\{X}'
            }
        }

        It 'restores them in the classes hive' {
            Save-KutayUserSnapshot -Id 'classic-menu' -Registry "$item|(default)"

            Restore-KutaySnapshot -Id 'classic-menu'

            Should -Invoke -ModuleName KutayState Remove-KutayRegistryValue -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'HKU\mount-S-1-5-21-100-1001_Classes\CLSID\{X}\InprocServer32' -and $Name -eq '(default)'
            }
        }
    }

    Context 'Save-KutayUserSnapshot' {
        It 'records the value of every user hive, by user and relative path' {
            Mock -ModuleName KutayState Read-KutayRegistryValue {
                if ($Path -like 'HKU\mount-default\*') { return [pscustomobject]@{ exists = $false; type = $null; data = $null } }
                [pscustomobject]@{ exists = $true; type = 'DWord'; data = 1 }
            }

            Save-KutayUserSnapshot -Id 'hide-task-view' -Registry 'Software\Explorer\Advanced|ShowTaskViewButton'

            $json = Get-Content (Join-Path $TestDrive 'hide-task-view.json') -Raw | ConvertFrom-Json
            @($json.registry).Count | Should -Be 0
            @($json.users).Count | Should -Be 2
            $json.users[0].user | Should -Be 'S-1-5-21-100-1001'
            $json.users[0].path | Should -Be 'Software\Explorer\Advanced'
            $json.users[0].name | Should -Be 'ShowTaskViewButton'
            $json.users[0].exists | Should -BeTrue
            $json.users[0].data | Should -Be 1
            $json.users[1].user | Should -Be 'default'
            $json.users[1].exists | Should -BeFalse
        }

        It 'keeps the first snapshot when run twice' {
            Mock -ModuleName KutayState Read-KutayRegistryValue { [pscustomobject]@{ exists = $false; type = $null; data = $null } }
            Save-KutayUserSnapshot -Id 'hide-task-view' -Registry 'Software\A|B'
            Mock -ModuleName KutayState Read-KutayRegistryValue { [pscustomobject]@{ exists = $true; type = 'DWord'; data = 0 } }

            Save-KutayUserSnapshot -Id 'hide-task-view' -Registry 'Software\A|B'

            $json = Get-Content (Join-Path $TestDrive 'hide-task-view.json') -Raw | ConvertFrom-Json
            $json.users[0].exists | Should -BeFalse
        }

        It 'adds users that are not in an existing snapshot yet, keeping the recorded ones' {
            Mock -ModuleName KutayState Get-KutayUserHive {
                [pscustomobject]@{ user = 'default'; file = 'C:\Users\Default\NTUSER.DAT'; classes = $null }
            }
            Mock -ModuleName KutayState Read-KutayRegistryValue { [pscustomobject]@{ exists = $false; type = $null; data = $null } }
            Save-KutayUserSnapshot -Id 'hide-task-view' -Registry 'Software\A|B'
            # A second run: a new account exists now, and the default profile holds KutayOS's value.
            Mock -ModuleName KutayState Get-KutayUserHive {
                [pscustomobject]@{ user = 'S-1-5-21-100-1001'; file = 'C:\Users\PC\NTUSER.DAT'; classes = $null }
                [pscustomobject]@{ user = 'default'; file = 'C:\Users\Default\NTUSER.DAT'; classes = $null }
            }
            Mock -ModuleName KutayState Read-KutayRegistryValue { [pscustomobject]@{ exists = $true; type = 'DWord'; data = 1 } }

            Save-KutayUserSnapshot -Id 'hide-task-view' -Registry 'Software\A|B'

            $json = Get-Content (Join-Path $TestDrive 'hide-task-view.json') -Raw | ConvertFrom-Json
            @($json.users).Count | Should -Be 2
            ($json.users | Where-Object user -eq 'default').exists | Should -BeFalse
            ($json.users | Where-Object user -eq 'S-1-5-21-100-1001').data | Should -Be 1
        }

        It 'rejects a path that names a hive, since the user hive is implied' {
            { Save-KutayUserSnapshot -Id 'bad' -Registry 'HKCU\Software\A|B' } | Should -Throw '*relative*'
        }
    }

    Context 'Set-KutayUserSetting' {
        It 'snapshots first, then writes the value to every user hive' {
            Mock -ModuleName KutayState Read-KutayRegistryValue { [pscustomobject]@{ exists = $false; type = $null; data = $null } }
            Mock -ModuleName KutayState Set-KutayRegistryValue {
                # The original must already be on disk when the first value changes.
                if (-not (Test-Path (Join-Path $TestDrive 'hide-task-view.json'))) { throw 'wrote before the snapshot' }
            }

            Set-KutayUserSetting -Id 'hide-task-view' -Setting 'Software\Explorer\Advanced|ShowTaskViewButton|DWord|0'

            Should -Invoke -ModuleName KutayState Set-KutayRegistryValue -Times 2 -Exactly
            foreach ($user in 'S-1-5-21-100-1001', 'default') {
                Should -Invoke -ModuleName KutayState Set-KutayRegistryValue -Times 1 -Exactly -ParameterFilter {
                    $Path -eq "HKU\mount-$user\Software\Explorer\Advanced" -and $Name -eq 'ShowTaskViewButton' -and
                    $Type -eq 'DWord' -and $Data -eq '0'
                }
            }
        }

        It 'skips, with a warning, a user hive that cannot be loaded and still writes the others' {
            Mock -ModuleName KutayState Read-KutayRegistryValue { [pscustomobject]@{ exists = $false; type = $null; data = $null } }
            Mock -ModuleName KutayState Write-Warning { }
            Mock -ModuleName KutayState Use-KutayUserHive {
                if ($Hive.user -ne 'default') { throw [KutayHiveUnavailableException]::new('reg load failed: in use') }
                & $Script "HKU\mount-$($Hive.user)"
            }

            Set-KutayUserSetting -Id 'hide-task-view' -Setting 'Software\A|B|DWord|0'

            Should -Invoke -ModuleName KutayState Set-KutayRegistryValue -Times 1 -Exactly -ParameterFilter { $Path -like 'HKU\mount-default\*' }
            Should -Invoke -ModuleName KutayState Write-Warning -ParameterFilter { $Message -like '*S-1-5-21-100-1001*' }
            $json = Get-Content (Join-Path $TestDrive 'hide-task-view.json') -Raw | ConvertFrom-Json
            @($json.users).user | Should -Be @('default')
        }

        It 'does not skip a hive when a value write fails' {
            Mock -ModuleName KutayState Read-KutayRegistryValue { [pscustomobject]@{ exists = $false; type = $null; data = $null } }
            Mock -ModuleName KutayState Set-KutayRegistryValue { throw 'access denied' }

            { Set-KutayUserSetting -Id 'hide-task-view' -Setting 'Software\A|B|DWord|0' } | Should -Throw '*access denied*'
        }

        It 'writes a string value' {
            Mock -ModuleName KutayState Read-KutayRegistryValue { [pscustomobject]@{ exists = $false; type = $null; data = $null } }

            Set-KutayUserSetting -Id 'dark' -Setting 'Software\A|Mode|String|x y'

            Should -Invoke -ModuleName KutayState Set-KutayRegistryValue -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'HKU\mount-default\Software\A' -and $Type -eq 'String' -and $Data -eq 'x y'
            }
        }

        It 'rejects a setting that is not path|name|type|data' -ForEach @(
            @{ Setting = 'Software\A|B|DWord' }, @{ Setting = 'Software\A|B|Binary|00' }, @{ Setting = 'HKCU\A|B|DWord|0' }
        ) {
            { Set-KutayUserSetting -Id 'bad' -Setting $Setting } | Should -Throw
            Should -Invoke -ModuleName KutayState Set-KutayRegistryValue -Times 0 -Exactly
        }
    }

    Context 'Restore-KutaySnapshot with user values' {
        It 'puts each user value back in its own hive' {
            Mock -ModuleName KutayState Read-KutayRegistryValue {
                if ($Path -like 'HKU\mount-default\*') { return [pscustomobject]@{ exists = $false; type = $null; data = $null } }
                [pscustomobject]@{ exists = $true; type = 'DWord'; data = 1 }
            }
            Save-KutayUserSnapshot -Id 'hide-task-view' -Registry 'Software\Explorer\Advanced|ShowTaskViewButton'

            Restore-KutaySnapshot -Id 'hide-task-view'

            Should -Invoke -ModuleName KutayState Set-KutayRegistryValue -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'HKU\mount-S-1-5-21-100-1001\Software\Explorer\Advanced' -and $Data -eq 1
            }
            Should -Invoke -ModuleName KutayState Remove-KutayRegistryValue -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'HKU\mount-default\Software\Explorer\Advanced' -and $Name -eq 'ShowTaskViewButton'
            }
            Join-Path $TestDrive 'hide-task-view.json' | Should -Not -Exist
        }

        It 'skips a user whose profile was deleted since the snapshot' {
            Mock -ModuleName KutayState Read-KutayRegistryValue { [pscustomobject]@{ exists = $true; type = 'DWord'; data = 1 } }
            Save-KutayUserSnapshot -Id 'hide-task-view' -Registry 'Software\A|B'
            Mock -ModuleName KutayState Get-KutayUserHive {
                [pscustomobject]@{ user = 'default'; file = 'C:\Users\Default\NTUSER.DAT' }
            }

            Restore-KutaySnapshot -Id 'hide-task-view'

            Should -Invoke -ModuleName KutayState Set-KutayRegistryValue -Times 1 -Exactly -ParameterFilter {
                $Path -like 'HKU\mount-default\*'
            }
            Join-Path $TestDrive 'hide-task-view.json' | Should -Not -Exist
        }

        It 'keeps the snapshot when a user value cannot be restored' {
            Mock -ModuleName KutayState Read-KutayRegistryValue { [pscustomobject]@{ exists = $true; type = 'DWord'; data = 1 } }
            Save-KutayUserSnapshot -Id 'hide-task-view' -Registry 'Software\A|B'
            Mock -ModuleName KutayState Set-KutayRegistryValue { throw 'access denied' }

            { Restore-KutaySnapshot -Id 'hide-task-view' } | Should -Throw '*access denied*'
            Join-Path $TestDrive 'hide-task-view.json' | Should -Exist
        }
    }
}
