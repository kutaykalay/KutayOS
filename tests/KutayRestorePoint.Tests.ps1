BeforeAll {
    $modules = Join-Path $PSScriptRoot '..\src\playbook\Executables\KutayModules'
    Import-Module (Join-Path $modules 'KutayState.psm1') -Force
    Import-Module (Join-Path $modules 'KutayRestorePoint.psm1') -Force
}

AfterAll {
    Remove-Module KutayRestorePoint, KutayState -ErrorAction SilentlyContinue
}

Describe 'New-KutayRestorePoint' {
    BeforeEach {
        $script:calls = [System.Collections.Generic.List[string]]::new()
        $script:sequence = 5
        Mock -ModuleName KutayRestorePoint Enable-ComputerRestore { $script:calls.Add('enable') }
        Mock -ModuleName KutayRestorePoint Get-KutayLatestRestorePoint { $script:sequence }
        Mock -ModuleName KutayRestorePoint Save-KutaySnapshot { $script:calls.Add("save:$Id") }
        Mock -ModuleName KutayRestorePoint Set-KutayRegistryValue { $script:calls.Add("set:${Name}=$Data") }
        Mock -ModuleName KutayRestorePoint Restore-KutaySnapshot { $script:calls.Add("restore:$Id") }
        Mock -ModuleName KutayRestorePoint Checkpoint-Computer {
            $script:calls.Add('checkpoint')
            $script:sequence = 6
        }
    }

    It 'returns the sequence number of the new restore point' {
        New-KutayRestorePoint -Description 'KutayOS test' | Should -Be 6
    }

    It 'enables protection, lifts the frequency limit, checkpoints, then puts the limit back' {
        New-KutayRestorePoint -Description 'KutayOS test' | Out-Null

        $script:calls | Should -Be @(
            'enable'
            'save:restore-point-frequency'
            'set:SystemRestorePointCreationFrequency=0'
            'checkpoint'
            'restore:restore-point-frequency'
        )
    }

    It 'creates a MODIFY_SETTINGS restore point with the given description' {
        New-KutayRestorePoint -Description 'KutayOS test' | Out-Null

        Should -Invoke -ModuleName KutayRestorePoint Checkpoint-Computer -Times 1 -Exactly -ParameterFilter {
            $Description -eq 'KutayOS test' -and $RestorePointType -eq 'MODIFY_SETTINGS'
        }
    }

    It 'fails when Windows silently skipped the restore point' {
        Mock -ModuleName KutayRestorePoint Checkpoint-Computer { }

        { New-KutayRestorePoint -Description 'KutayOS test' } | Should -Throw '*No new restore point*'
    }

    It 'puts the frequency limit back even when the checkpoint fails' {
        Mock -ModuleName KutayRestorePoint Checkpoint-Computer { throw 'VSS error' }

        { New-KutayRestorePoint -Description 'KutayOS test' } | Should -Throw '*VSS error*'
        Should -Invoke -ModuleName KutayRestorePoint Restore-KutaySnapshot -Times 1 -Exactly -ParameterFilter {
            $Id -eq 'restore-point-frequency'
        }
    }

    It 'works when there was no restore point before' {
        $script:sequence = 0
        Mock -ModuleName KutayRestorePoint Checkpoint-Computer { $script:sequence = 1 }

        New-KutayRestorePoint -Description 'KutayOS test' | Should -Be 1
    }
}

Describe 'Get-KutayLatestRestorePoint' {
    It 'returns the highest sequence number' {
        Mock -ModuleName KutayRestorePoint Get-ComputerRestorePoint {
            @([pscustomobject]@{ SequenceNumber = 3 }, [pscustomobject]@{ SequenceNumber = 7 })
        }

        InModuleScope KutayRestorePoint { Get-KutayLatestRestorePoint } | Should -Be 7
    }

    It 'returns 0 when there are no restore points' {
        Mock -ModuleName KutayRestorePoint Get-ComputerRestorePoint { }

        InModuleScope KutayRestorePoint { Get-KutayLatestRestorePoint } | Should -Be 0
    }
}
