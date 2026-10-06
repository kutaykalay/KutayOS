[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester passes these variables between its blocks')]
param()

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\src\playbook\Executables\KutayModules\KutayState.psm1'
    Import-Module $modulePath -Force

    function Write-Snapshot([hashtable]$Snapshot) {
        $file = Join-Path $TestDrive "$($Snapshot.id).json"
        [IO.File]::WriteAllText($file, (ConvertTo-Json -InputObject $Snapshot -Depth 5))
        $file
    }
    function New-Value($Type, $Data) { [pscustomobject]@{ exists = $true; type = $Type; data = $Data } }
    function New-Missing { [pscustomobject]@{ exists = $false; type = $null; data = $null } }
}

AfterAll {
    Remove-Module KutayState -ErrorAction SilentlyContinue
}

Describe 'Compare-KutaySnapshot' {
    BeforeEach {
        Get-ChildItem $TestDrive -Filter *.json | Remove-Item
        Mock -ModuleName KutayState Get-KutayUserHive {
            [pscustomobject]@{ user = 'S-1-5-21-100-1001'; file = 'C:\Users\PC\NTUSER.DAT'; classes = $null }
        }
        Mock -ModuleName KutayState Use-KutayUserHive {
            if (-not $Classes) { & $Script "HKU\mount-$($Hive.user)" }
        }
        Mock -ModuleName KutayState Test-KutayRegistryKey { $false }
        Mock -ModuleName KutayState Get-KutaySystemState { 'Enabled' }
    }

    Context 'machine registry values' {
        BeforeEach {
            $script:file = Write-Snapshot @{
                id = 'disable-telemetry'; createdAt = '2026-10-06T10:00:00'
                registry = @(
                    @{ path = 'HKLM\SOFTWARE\Policies\Test'; name = 'AllowTelemetry'; exists = $true; type = 'DWord'; data = 1 }
                    @{ path = 'HKLM\SOFTWARE\Policies\Test'; name = 'Gone'; exists = $false; type = $null; data = $null }
                )
            }
        }

        It 'finds no difference when every value is back' {
            Mock -ModuleName KutayState Read-KutayRegistryValue { New-Value 'DWord' 1 } -ParameterFilter { $Name -eq 'AllowTelemetry' }
            Mock -ModuleName KutayState Read-KutayRegistryValue { New-Missing } -ParameterFilter { $Name -eq 'Gone' }

            @(Compare-KutaySnapshot -Path $script:file).Count | Should -Be 0
        }

        It 'reports a value whose data differs' {
            Mock -ModuleName KutayState Read-KutayRegistryValue { New-Value 'DWord' 0 } -ParameterFilter { $Name -eq 'AllowTelemetry' }
            Mock -ModuleName KutayState Read-KutayRegistryValue { New-Missing } -ParameterFilter { $Name -eq 'Gone' }

            $diff = @(Compare-KutaySnapshot -Path $script:file)

            $diff.Count | Should -Be 1
            $diff[0].id | Should -Be 'disable-telemetry'
            $diff[0].item | Should -Be 'HKLM\SOFTWARE\Policies\Test|AllowTelemetry'
            $diff[0].expected | Should -Be 'DWord [1]'
            $diff[0].actual | Should -Be 'DWord [0]'
        }

        It 'reports a value whose type differs' {
            Mock -ModuleName KutayState Read-KutayRegistryValue { New-Value 'String' '1' } -ParameterFilter { $Name -eq 'AllowTelemetry' }
            Mock -ModuleName KutayState Read-KutayRegistryValue { New-Missing } -ParameterFilter { $Name -eq 'Gone' }

            @(Compare-KutaySnapshot -Path $script:file).Count | Should -Be 1
        }

        It 'reports a value that should be gone but is still there' {
            Mock -ModuleName KutayState Read-KutayRegistryValue { New-Value 'DWord' 1 }

            $diff = @(Compare-KutaySnapshot -Path $script:file)

            $diff.Count | Should -Be 1
            $diff[0].expected | Should -Be 'absent'
        }
    }

    It 'compares multi-string data item by item' {
        $file = Write-Snapshot @{
            id = 'multi'; createdAt = '2026-10-06T10:00:00'
            registry = @(@{ path = 'HKLM\SOFTWARE\Test'; name = 'List'; exists = $true; type = 'MultiString'; data = @('a', 'b') })
        }
        Mock -ModuleName KutayState Read-KutayRegistryValue { New-Value 'MultiString' ([string[]]@('a', 'b')) }

        @(Compare-KutaySnapshot -Path $file).Count | Should -Be 0
    }

    It 'tells a comma inside a multi-string item from two items' {
        $file = Write-Snapshot @{
            id = 'multi'; createdAt = '2026-10-06T10:00:00'
            registry = @(@{ path = 'HKLM\SOFTWARE\Test'; name = 'List'; exists = $true; type = 'MultiString'; data = @('a,b') })
        }
        Mock -ModuleName KutayState Read-KutayRegistryValue { New-Value 'MultiString' ([string[]]@('a', 'b')) }

        @(Compare-KutaySnapshot -Path $file).Count | Should -Be 1
    }

    It 'tells an empty string from an empty multi-string' {
        $file = Write-Snapshot @{
            id = 'multi'; createdAt = '2026-10-06T10:00:00'
            registry = @(@{ path = 'HKLM\SOFTWARE\Test'; name = 'List'; exists = $true; type = 'MultiString'; data = @('') })
        }
        Mock -ModuleName KutayState Read-KutayRegistryValue { New-Value 'MultiString' ([string[]]@()) }

        @(Compare-KutaySnapshot -Path $file).Count | Should -Be 1
    }

    Context 'per-user values' {
        It 'reads each value inside the user hive' {
            $file = Write-Snapshot @{
                id = 'hide-task-view'; createdAt = '2026-10-06T10:00:00'; registry = @()
                users = @(@{ user = 'S-1-5-21-100-1001'; path = 'Software\Test'; name = 'ShowTaskViewButton'; exists = $true; type = 'DWord'; data = 1; createdKey = $null })
            }
            Mock -ModuleName KutayState Read-KutayRegistryValue { New-Value 'DWord' 1 }

            @(Compare-KutaySnapshot -Path $file).Count | Should -Be 0
            Should -Invoke -ModuleName KutayState Read-KutayRegistryValue -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'HKU\mount-S-1-5-21-100-1001\Software\Test' -and $Name -eq 'ShowTaskViewButton'
            }
        }

        It 'reports a key KutayOS created that is still there' {
            $file = Write-Snapshot @{
                id = 'classic-menu'; createdAt = '2026-10-06T10:00:00'; registry = @()
                users = @(@{ user = 'S-1-5-21-100-1001'; path = 'Software\Test\Inner'; name = '(default)'; exists = $false; type = $null; data = $null; createdKey = 'Software\Test' })
            }
            Mock -ModuleName KutayState Read-KutayRegistryValue { New-Missing }
            Mock -ModuleName KutayState Test-KutayRegistryKey { $true } -ParameterFilter { $Path -eq 'HKU\mount-S-1-5-21-100-1001\Software\Test' }

            $diff = @(Compare-KutaySnapshot -Path $file)

            $diff.Count | Should -Be 1
            $diff[0].item | Should -Be 'S-1-5-21-100-1001\Software\Test'
            $diff[0].actual | Should -Be 'key exists'
        }

        It 'reports a profile that no longer exists' {
            $file = Write-Snapshot @{
                id = 'hide-task-view'; createdAt = '2026-10-06T10:00:00'; registry = @()
                users = @(@{ user = 'S-1-5-21-100-2002'; path = 'Software\Test'; name = 'ShowTaskViewButton'; exists = $true; type = 'DWord'; data = 1; createdKey = $null })
            }

            $diff = @(Compare-KutaySnapshot -Path $file)

            $diff.Count | Should -Be 1
            $diff[0].actual | Should -Be 'profile missing'
        }
    }

    Context 'system state' {
        BeforeEach {
            $script:file = Write-Snapshot @{
                id = 'disable-ceip-tasks'; createdAt = '2026-10-06T10:00:00'; registry = @()
                system = @(@{ kind = 'ScheduledTask'; state = 'Enabled'; name = '\Microsoft\Windows\Test\Task' })
            }
        }

        It 'finds no difference when the state is back' {
            @(Compare-KutaySnapshot -Path $script:file).Count | Should -Be 0
            Should -Invoke -ModuleName KutayState Get-KutaySystemState -Times 1 -Exactly -ParameterFilter {
                $Kind -eq 'ScheduledTask' -and $Name -eq '\Microsoft\Windows\Test\Task'
            }
        }

        It 'reports a state that is not back' {
            Mock -ModuleName KutayState Get-KutaySystemState { 'Disabled' }

            $diff = @(Compare-KutaySnapshot -Path $script:file)

            $diff.Count | Should -Be 1
            $diff[0].expected | Should -Be 'Enabled'
            $diff[0].actual | Should -Be 'Disabled'
        }

        It 'reads kinds without a name with an empty name' {
            $file = Write-Snapshot @{
                id = 'disable-hibernation'; createdAt = '2026-10-06T10:00:00'; registry = @()
                system = @(@{ kind = 'Hibernation'; state = 'On' })
            }
            Mock -ModuleName KutayState Get-KutaySystemState { 'On' }

            @(Compare-KutaySnapshot -Path $file).Count | Should -Be 0
            Should -Invoke -ModuleName KutayState Get-KutaySystemState -ParameterFilter { $Kind -eq 'Hibernation' -and $Name -eq '' }
        }
    }

    It 'throws for a file that does not exist' {
        { Compare-KutaySnapshot -Path (Join-Path $TestDrive 'missing.json') } | Should -Throw
    }
}
