[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester passes these variables between its blocks')]
param()

BeforeAll {
    $modules = Join-Path $PSScriptRoot '..\src\playbook\Executables\KutayModules'
    Import-Module (Join-Path $modules 'KutaySystemState.psm1') -Force
}

AfterAll {
    Remove-Module KutaySystemState -ErrorAction SilentlyContinue
}

Describe 'Get-KutaySystemState' {
    It 'reads hibernation as <Expected> when HibernateEnabled is <Value> and hiberfil.sys exists: <File>' -ForEach @(
        @{ Value = 1; File = $true; Expected = 'On' }
        @{ Value = 0; File = $false; Expected = 'Off' }
        @{ Value = 0; File = $true; Expected = 'Off' }
        @{ Value = $null; File = $true; Expected = 'On' }
        @{ Value = $null; File = $false; Expected = 'Off' }
    ) {
        Mock -ModuleName KutaySystemState Get-KutayRegistryNumber { $Value }
        Mock -ModuleName KutaySystemState Test-Path { $File }

        Get-KutaySystemState -Kind Hibernation | Should -Be $Expected
    }

    It 'reads reserved storage from the DISM module' {
        Mock -ModuleName KutaySystemState Get-WindowsReservedStorageState { [pscustomobject]@{ ReservedStorageState = 'Enabled' } }

        Get-KutaySystemState -Kind ReservedStorage | Should -Be 'Enabled'
    }

    It 'rejects a reserved storage state it could not set back' {
        Mock -ModuleName KutaySystemState Get-WindowsReservedStorageState { [pscustomobject]@{ ReservedStorageState = 'Unknown' } }

        { Get-KutaySystemState -Kind ReservedStorage } | Should -Throw '*Unknown*'
    }

    It 'reads Compact OS as <Expected> when HKLM\SYSTEM\Setup Compact is <Value>' -ForEach @(
        @{ Value = 1; Expected = 'Always' }
        @{ Value = 0; Expected = 'Never' }
        @{ Value = $null; Expected = 'Never' }
    ) {
        Mock -ModuleName KutaySystemState Get-KutayRegistryNumber { $Value } -ParameterFilter { $Name -eq 'Compact' }

        Get-KutaySystemState -Kind CompactOS | Should -Be $Expected
    }

    It 'reads a missing registry value as null' {
        InModuleScope KutaySystemState {
            Get-KutayRegistryNumber 'HKLM:\SOFTWARE\KutayOS-Test-Missing' 'Nothing' | Should -BeNullOrEmpty
        }
    }

    It 'reads a scheduled task as <Expected> when its state is <TaskState>' -ForEach @(
        @{ TaskState = 'Ready'; Expected = 'Enabled' }
        @{ TaskState = 'Running'; Expected = 'Enabled' }
        @{ TaskState = 'Disabled'; Expected = 'Disabled' }
    ) {
        Mock -ModuleName KutaySystemState Get-ScheduledTask { [pscustomobject]@{ State = $TaskState } }

        Get-KutaySystemState -Kind ScheduledTask -Name '\Microsoft\Windows\Test\Task' | Should -Be $Expected

        Should -Invoke -ModuleName KutaySystemState Get-ScheduledTask -Times 1 -Exactly -ParameterFilter {
            $TaskPath -eq '\Microsoft\Windows\Test\' -and $TaskName -eq 'Task'
        }
    }

    It 'reads a scheduled task this Windows does not have as Absent' {
        Mock -ModuleName KutaySystemState Get-ScheduledTask { }

        Get-KutaySystemState -Kind ScheduledTask -Name '\Microsoft\Windows\Test\Gone' | Should -Be 'Absent'
    }

    It 'needs a task name for a scheduled task' {
        { Get-KutaySystemState -Kind ScheduledTask } | Should -Throw '*Name*'
    }

    It 'rejects a task name that is not a full path' {
        { Get-KutaySystemState -Kind ScheduledTask -Name 'Task' } | Should -Throw '*full path*'
    }

    It 'rejects an unknown kind' {
        { Get-KutaySystemState -Kind Pagefile } | Should -Throw
    }
}

Describe 'Set-KutaySystemState' {
    BeforeEach {
        # The state before the call and the state Windows reports after the command ran.
        $script:current = 'On'
        $script:after = 'Off'
        Mock -ModuleName KutaySystemState Get-KutaySystemState { $script:current }
        Mock -ModuleName KutaySystemState Invoke-KutayNativeCommand { $script:current = $script:after }
        Mock -ModuleName KutaySystemState Set-WindowsReservedStorageState { $script:current = $script:after }
    }

    It 'turns hibernation off with powercfg' {
        Set-KutaySystemState -Kind Hibernation -State Off

        Should -Invoke -ModuleName KutaySystemState Invoke-KutayNativeCommand -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'powercfg.exe' -and ($ArgumentList -join ' ') -eq '/hibernate off'
        }
    }

    It 'turns Compact OS on with compact.exe' {
        $script:current = 'Never'
        $script:after = 'Always'

        Set-KutaySystemState -Kind CompactOS -State Always

        Should -Invoke -ModuleName KutaySystemState Invoke-KutayNativeCommand -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'compact.exe' -and ($ArgumentList -join ' ') -eq '/CompactOS:always'
        }
    }

    It 'disables reserved storage through the DISM module' {
        $script:current = 'Enabled'
        $script:after = 'Disabled'

        Set-KutaySystemState -Kind ReservedStorage -State Disabled

        Should -Invoke -ModuleName KutaySystemState Set-WindowsReservedStorageState -Times 1 -Exactly -ParameterFilter {
            $State -eq 'Disabled'
        }
    }

    It 'does nothing when the state is already set' {
        $script:current = 'Off'

        Set-KutaySystemState -Kind Hibernation -State Off

        Should -Invoke -ModuleName KutaySystemState Invoke-KutayNativeCommand -Times 0 -Exactly
    }

    It 'disables a scheduled task' {
        $script:current = 'Enabled'
        $script:after = 'Disabled'
        Mock -ModuleName KutaySystemState Disable-ScheduledTask { $script:current = $script:after }

        Set-KutaySystemState -Kind ScheduledTask -Name '\Microsoft\Windows\Test\Task' -State Disabled

        Should -Invoke -ModuleName KutaySystemState Disable-ScheduledTask -Times 1 -Exactly -ParameterFilter {
            $TaskPath -eq '\Microsoft\Windows\Test\' -and $TaskName -eq 'Task'
        }
    }

    It 'enables a scheduled task' {
        $script:current = 'Disabled'
        $script:after = 'Enabled'
        Mock -ModuleName KutaySystemState Enable-ScheduledTask { $script:current = $script:after }

        Set-KutaySystemState -Kind ScheduledTask -Name '\Microsoft\Windows\Test\Task' -State Enabled

        Should -Invoke -ModuleName KutaySystemState Enable-ScheduledTask -Times 1 -Exactly
    }

    It 'skips a scheduled task this Windows does not have, with a warning' {
        $script:current = 'Absent'
        Mock -ModuleName KutaySystemState Disable-ScheduledTask { }

        Set-KutaySystemState -Kind ScheduledTask -Name '\Microsoft\Windows\Test\Gone' -State Disabled -WarningVariable warned -WarningAction SilentlyContinue

        Should -Invoke -ModuleName KutaySystemState Disable-ScheduledTask -Times 0 -Exactly
        "$warned" | Should -BeLike '*Gone*'
    }

    It 'leaves a task alone when the snapshot recorded it as absent' {
        $script:current = 'Disabled'
        Mock -ModuleName KutaySystemState Enable-ScheduledTask { }

        Set-KutaySystemState -Kind ScheduledTask -Name '\Microsoft\Windows\Test\New' -State Absent -WarningAction SilentlyContinue

        Should -Invoke -ModuleName KutaySystemState Enable-ScheduledTask -Times 0 -Exactly
    }

    It 'fails when the scheduled task stayed enabled' {
        $script:current = 'Enabled'
        Mock -ModuleName KutaySystemState Disable-ScheduledTask { }

        { Set-KutaySystemState -Kind ScheduledTask -Name '\Microsoft\Windows\Test\Task' -State Disabled } | Should -Throw '*still Enabled*'
    }

    It 'rejects a state that does not belong to the kind' {
        { Set-KutaySystemState -Kind Hibernation -State Always } | Should -Throw '*Hibernation*'
    }

    It 'fails when the state did not change' {
        $script:after = 'On'

        { Set-KutaySystemState -Kind Hibernation -State Off } | Should -Throw '*still On*'
    }
}

Describe 'Invoke-KutayNativeCommand' {
    It 'passes on success' {
        { InModuleScope KutaySystemState { Invoke-KutayNativeCommand -FilePath 'cmd.exe' -ArgumentList '/c', 'exit 0' } } |
            Should -Not -Throw
    }

    It 'throws with the exit code on failure' {
        { InModuleScope KutaySystemState { Invoke-KutayNativeCommand -FilePath 'cmd.exe' -ArgumentList '/c', 'exit 5' } } |
            Should -Throw '*exit code 5*'
    }

    It 'accepts an allowed non-zero exit code' {
        { InModuleScope KutaySystemState { Invoke-KutayNativeCommand -FilePath 'cmd.exe' -ArgumentList '/c', 'exit 3010' -SuccessCode 0, 3010 } } |
            Should -Not -Throw
    }
}
