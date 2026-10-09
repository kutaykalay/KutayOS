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

    It 'reads a scheduled task as Absent when the Task Scheduler reports it not found' {
        Mock -ModuleName KutaySystemState Get-ScheduledTask {
            throw [Management.Automation.ErrorRecord]::new([Exception]::new('No MSFT_ScheduledTask objects found'),
                'CmdletizationQuery_NotFound_TaskName,Get-ScheduledTask', 'ObjectNotFound', $null)
        }

        Get-KutaySystemState -Kind ScheduledTask -Name '\Microsoft\Windows\Test\Gone' | Should -Be 'Absent'
    }

    It 'fails instead of reading Absent when the Task Scheduler cannot be read' {
        Mock -ModuleName KutaySystemState Get-ScheduledTask {
            throw [Management.Automation.ErrorRecord]::new([UnauthorizedAccessException]::new('Access is denied'),
                'HRESULT 0x80070005,Get-ScheduledTask', 'PermissionDenied', $null)
        }

        { Get-KutaySystemState -Kind ScheduledTask -Name '\Microsoft\Windows\Test\Task' } | Should -Throw '*Access is denied*'
    }

    It 'fails when a task name matches more than one task' {
        Mock -ModuleName KutaySystemState Get-ScheduledTask { [pscustomobject]@{ State = 'Ready' }; [pscustomobject]@{ State = 'Disabled' } }

        { Get-KutaySystemState -Kind ScheduledTask -Name '\Microsoft\Windows\Test\Task*' } | Should -Throw '*more than one*'
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

    It 'returns <Expected> when the state before is <Before>' -ForEach @(
        @{ Before = 'Enabled'; Expected = $true }
        @{ Before = 'Disabled'; Expected = $true }
        @{ Before = 'Absent'; Expected = $false }
    ) {
        $script:current = $Before
        $script:after = 'Disabled'
        Mock -ModuleName KutaySystemState Disable-ScheduledTask { $script:current = $script:after }

        $result = Set-KutaySystemState -Kind ScheduledTask -Name '\Microsoft\Windows\Test\Task' -State Disabled -WarningAction SilentlyContinue

        $result | Should -BeExactly $Expected
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

Describe 'AppPackage state' {
    BeforeEach {
        $script:provisioned = @()
        $script:installed = @()
        Mock -ModuleName KutaySystemState Get-AppxProvisionedPackage { $script:provisioned }
        Mock -ModuleName KutaySystemState Get-AppxPackage { $script:installed }
        Mock -ModuleName KutaySystemState Remove-AppxProvisionedPackage { $script:provisioned = @() }
        Mock -ModuleName KutaySystemState Remove-AppxPackage { $script:installed = @() }
    }

    It 'reads Absent when no user has the package and it is not provisioned' {
        Get-KutaySystemState -Kind AppPackage -Name 'Microsoft.WindowsTerminal' | Should -Be 'Absent'
    }

    It 'reads Installed when the package is provisioned' {
        $script:provisioned = @([pscustomobject]@{ DisplayName = 'Microsoft.WindowsTerminal'; PackageName = 'Microsoft.WindowsTerminal_1.0.0.0_neutral_~_8wekyb3d8bbwe' })
        Get-KutaySystemState -Kind AppPackage -Name 'Microsoft.WindowsTerminal' | Should -Be 'Installed'
    }

    It 'reads Installed when only a user has the package' {
        $script:installed = @([pscustomobject]@{ Name = 'Microsoft.WindowsTerminal'; PackageFullName = 'Microsoft.WindowsTerminal_1.0.0.0_x64__8wekyb3d8bbwe' })
        Get-KutaySystemState -Kind AppPackage -Name 'Microsoft.WindowsTerminal' | Should -Be 'Installed'
    }

    It 'does not match another package that only starts with the same name' {
        $script:provisioned = @([pscustomobject]@{ DisplayName = 'Microsoft.WindowsTerminalPreview'; PackageName = 'x' })
        Get-KutaySystemState -Kind AppPackage -Name 'Microsoft.WindowsTerminal' | Should -Be 'Absent'
    }

    It 'needs a package name' {
        { Get-KutaySystemState -Kind AppPackage } | Should -Throw '*Name*'
    }

    It 'removes the provisioned copy and every user copy to set Absent' {
        $script:provisioned = @([pscustomobject]@{ DisplayName = 'Microsoft.WindowsTerminal'; PackageName = 'Microsoft.WindowsTerminal_1.0.0.0_neutral_~_8wekyb3d8bbwe' })
        $script:installed = @([pscustomobject]@{ Name = 'Microsoft.WindowsTerminal'; PackageFullName = 'Microsoft.WindowsTerminal_1.0.0.0_x64__8wekyb3d8bbwe' })

        Set-KutaySystemState -Kind AppPackage -Name 'Microsoft.WindowsTerminal' -State Absent | Should -BeTrue

        Should -Invoke -ModuleName KutaySystemState Remove-AppxProvisionedPackage -Times 1 -Exactly -ParameterFilter {
            $PackageName -eq 'Microsoft.WindowsTerminal_1.0.0.0_neutral_~_8wekyb3d8bbwe' -and $Online
        }
        Should -Invoke -ModuleName KutaySystemState Remove-AppxPackage -Times 1 -Exactly -ParameterFilter {
            $Package -eq 'Microsoft.WindowsTerminal_1.0.0.0_x64__8wekyb3d8bbwe' -and $AllUsers
        }
    }

    It 'fails when the package is still there after the removal' {
        $script:installed = @([pscustomobject]@{ Name = 'Microsoft.WindowsTerminal'; PackageFullName = 'p' })
        Mock -ModuleName KutaySystemState Remove-AppxPackage { }

        { Set-KutaySystemState -Kind AppPackage -Name 'Microsoft.WindowsTerminal' -State Absent } | Should -Throw '*still Installed*'
    }

    It 'does nothing when the package is already absent' {
        Set-KutaySystemState -Kind AppPackage -Name 'Microsoft.WindowsTerminal' -State Absent

        Should -Invoke -ModuleName KutaySystemState Remove-AppxPackage -Times 0 -Exactly
    }

    It 'leaves a package alone that was installed before KutayOS and is gone now, with a warning' {
        Set-KutaySystemState -Kind AppPackage -Name 'Microsoft.WindowsTerminal' -State Installed -WarningVariable warned -WarningAction SilentlyContinue | Should -BeFalse

        "$warned" | Should -BeLike '*cannot install*'
        Should -Invoke -ModuleName KutaySystemState Remove-AppxPackage -Times 0 -Exactly
    }

    It 'refuses to remove a package KutayOS does not install' {
        $script:installed = @([pscustomobject]@{ Name = 'Microsoft.WindowsStore'; PackageFullName = 'p' })

        { Set-KutaySystemState -Kind AppPackage -Name 'Microsoft.WindowsStore' -State Absent } | Should -Throw '*not a package KutayOS installs*'
        Should -Invoke -ModuleName KutaySystemState Remove-AppxPackage -Times 0 -Exactly
    }
}

Describe 'KutayTask state' {
    BeforeEach {
        $script:task = $null
        Mock -ModuleName KutaySystemState Get-ScheduledTask { if ($script:task) { $script:task } }
        Mock -ModuleName KutaySystemState Unregister-ScheduledTask { $script:task = $null }
    }

    It 'reads Absent when the task does not exist' {
        Get-KutaySystemState -Kind KutayTask -Name '\KutayOS\Update Windows Terminal' | Should -Be 'Absent'
    }

    It 'reads Present for an existing task, enabled or not' {
        $script:task = [pscustomobject]@{ State = 'Disabled' }
        Get-KutaySystemState -Kind KutayTask -Name '\KutayOS\Update Windows Terminal' | Should -Be 'Present'
    }

    It 'unregisters the task to set Absent' {
        $script:task = [pscustomobject]@{ State = 'Ready' }

        Set-KutaySystemState -Kind KutayTask -Name '\KutayOS\Update Windows Terminal' -State Absent | Should -BeTrue

        Should -Invoke -ModuleName KutaySystemState Unregister-ScheduledTask -Times 1 -Exactly -ParameterFilter {
            $TaskPath -eq '\KutayOS\' -and $TaskName -eq 'Update Windows Terminal' -and $Confirm -eq $false
        }
    }

    It 'leaves a task alone that existed before KutayOS and is gone now, with a warning' {
        Set-KutaySystemState -Kind KutayTask -Name '\KutayOS\Update Windows Terminal' -State Present -WarningVariable warned -WarningAction SilentlyContinue | Should -BeFalse

        "$warned" | Should -BeLike '*cannot create*'
    }

    It 'refuses to remove a task outside the KutayOS folder' {
        $script:task = [pscustomobject]@{ State = 'Ready' }

        { Set-KutaySystemState -Kind KutayTask -Name '\Microsoft\Windows\Defrag\ScheduledDefrag' -State Absent } | Should -Throw '*not a KutayOS task*'
        Should -Invoke -ModuleName KutaySystemState Unregister-ScheduledTask -Times 0 -Exactly
    }
}
