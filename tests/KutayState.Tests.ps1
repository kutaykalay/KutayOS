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
