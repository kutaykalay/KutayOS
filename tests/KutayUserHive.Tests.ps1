[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester passes these variables between its blocks')]
param()

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\playbook\Executables\KutayModules\KutayUserHive.psm1') -Force
}

AfterAll {
    Remove-Module KutayUserHive -ErrorAction SilentlyContinue
}

Describe 'Get-KutayUserHive' {
    BeforeEach {
        Mock -ModuleName KutayUserHive Get-KutayProfile {
            [pscustomobject]@{ sid = 'S-1-5-21-100-1001'; path = 'C:\Users\PC' }
            [pscustomobject]@{ sid = 'S-1-5-18'; path = 'C:\Windows\system32\config\systemprofile' }
            [pscustomobject]@{ sid = 'S-1-5-21-100-1002'; path = 'C:\Users\Gone' }
        }
        Mock -ModuleName KutayUserHive Get-KutayDefaultProfilePath { 'C:\Users\Default' }
        Mock -ModuleName KutayUserHive Test-Path { $LiteralPath -notlike 'C:\Users\Gone\*' }
    }

    It 'lists real user profiles and the default profile' {
        $hives = @(Get-KutayUserHive)

        $hives.user | Should -Be @('S-1-5-21-100-1001', 'default')
        $hives[0].file | Should -Be 'C:\Users\PC\NTUSER.DAT'
        $hives[1].file | Should -Be 'C:\Users\Default\NTUSER.DAT'
    }

    It 'skips service accounts and profiles whose hive file is gone' {
        $users = @(Get-KutayUserHive).user

        $users | Should -Not -Contain 'S-1-5-18'
        $users | Should -Not -Contain 'S-1-5-21-100-1002'
    }

    It 'adds the classes hive of a user profile, and none for the default profile' {
        Mock -ModuleName KutayUserHive Test-Path { $LiteralPath -notlike 'C:\Users\Gone\*' -and $LiteralPath -notlike 'C:\Users\Default\AppData\*' }

        $hives = @(Get-KutayUserHive)

        $hives[0].classes | Should -Be 'C:\Users\PC\AppData\Local\Microsoft\Windows\UsrClass.dat'
        $hives[1].classes | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-KutayRegExe' {
    It 'returns the exit code of a failing reg.exe instead of throwing on its error output' {
        # Read-only: queries a key that does not exist.
        InModuleScope KutayUserHive {
            $code = Invoke-KutayRegExe -Arguments @('query', 'HKLM\SOFTWARE\KutayOS-Test-NoSuchKey-7f3a')
            $code | Should -Not -Be 0
        }
    }
}

Describe 'Get-KutayUserHive with a broken profile entry' {
    It 'skips a profile without a ProfileImagePath' {
        Mock -ModuleName KutayUserHive Get-KutayProfile {
            [pscustomobject]@{ sid = 'S-1-5-21-100-1003'; path = '' }
            [pscustomobject]@{ sid = 'S-1-5-21-100-1001'; path = 'C:\Users\PC' }
        }
        Mock -ModuleName KutayUserHive Get-KutayDefaultProfilePath { 'C:\Users\Default' }
        Mock -ModuleName KutayUserHive Test-Path { $true }

        @(Get-KutayUserHive).user | Should -Be @('S-1-5-21-100-1001', 'default')
    }
}

Describe 'Split-KutayUserPath' {
    It 'sends <Path> to the <Where> hive as <Rest>' -ForEach @(
        @{ Path = 'Software\Classes\CLSID\{X}\InprocServer32'; Where = 'classes'; Rest = 'CLSID\{X}\InprocServer32' }
        @{ Path = 'SOFTWARE\classes\CLSID\{X}'; Where = 'classes'; Rest = 'CLSID\{X}' }
        @{ Path = 'Software\Microsoft\Windows'; Where = 'user'; Rest = 'Software\Microsoft\Windows' }
        @{ Path = 'Software\ClassesExtra\A'; Where = 'user'; Rest = 'Software\ClassesExtra\A' }
    ) {
        $split = Split-KutayUserPath $Path

        $split.classes | Should -Be ($Where -eq 'classes')
        $split.path | Should -Be $Rest
    }
}

Describe 'Find-KutayLoadedHive' {
    BeforeEach {
        Mock -ModuleName KutayUserHive Get-KutayHiveList {
            @{
                '\REGISTRY\MACHINE\SYSTEM'             = '\Device\HarddiskVolume3\Windows\System32\config\SYSTEM'
                '\REGISTRY\USER\S-1-5-21-100-1001'     = '\Device\HarddiskVolume3\Users\PC\NTUSER.DAT'
                '\REGISTRY\USER\AME_UserHive_Default'  = '\Device\HarddiskVolume3\Users\Default\NTUSER.DAT'
            }
        }
    }

    It 'finds the HKU key a hive file is loaded under, ignoring case' {
        InModuleScope KutayUserHive {
            Find-KutayLoadedHive 'c:\users\pc\ntuser.dat' | Should -Be 'S-1-5-21-100-1001'
            Find-KutayLoadedHive 'C:\Users\Default\NTUSER.DAT' | Should -Be 'AME_UserHive_Default'
        }
    }

    It 'returns nothing for a hive file that is not loaded' {
        InModuleScope KutayUserHive {
            Find-KutayLoadedHive 'C:\Users\Other\NTUSER.DAT' | Should -BeNullOrEmpty
        }
    }
}

Describe 'Mount-KutayUserHive' {
    BeforeEach {
        Mock -ModuleName KutayUserHive Invoke-KutayRegExe { 0 }
    }

    It 'reuses a hive that is already loaded' {
        Mock -ModuleName KutayUserHive Find-KutayLoadedHive { 'S-1-5-21-100-1001' }

        $mount = Mount-KutayUserHive ([pscustomobject]@{ user = 'S-1-5-21-100-1001'; file = 'C:\Users\PC\NTUSER.DAT' })

        $mount.root | Should -Be 'HKU\S-1-5-21-100-1001'
        $mount.mounted | Should -BeFalse
        Should -Invoke -ModuleName KutayUserHive Invoke-KutayRegExe -Times 0 -Exactly
    }

    It 'loads a hive that is not loaded under a KutayOS name' {
        Mock -ModuleName KutayUserHive Find-KutayLoadedHive { }

        $mount = Mount-KutayUserHive ([pscustomobject]@{ user = 'default'; file = 'C:\Users\Default\NTUSER.DAT' })

        $mount.root | Should -Be 'HKU\KutayOS_default'
        $mount.mounted | Should -BeTrue
        Should -Invoke -ModuleName KutayUserHive Invoke-KutayRegExe -Times 1 -Exactly -ParameterFilter {
            $Arguments[0] -eq 'load' -and $Arguments[1] -eq 'HKU\KutayOS_default' -and
            $Arguments[2] -eq 'C:\Users\Default\NTUSER.DAT'
        }
    }

    It 'throws when reg load fails' {
        Mock -ModuleName KutayUserHive Find-KutayLoadedHive { }
        Mock -ModuleName KutayUserHive Invoke-KutayRegExe { 1 }

        { Mount-KutayUserHive ([pscustomobject]@{ user = 'default'; file = 'C:\Users\Default\NTUSER.DAT' }) } |
            Should -Throw '*load*'
    }
}

Describe 'Use-KutayUserHive' {
    BeforeEach {
        Mock -ModuleName KutayUserHive Invoke-KutayRegExe { 0 }
        Mock -ModuleName KutayUserHive Find-KutayLoadedHive { }
        $hive = [pscustomobject]@{ user = 'default'; file = 'C:\Users\Default\NTUSER.DAT'; classes = $null }
    }

    It 'passes the hive root to the script and unloads a hive it loaded' {
        $root = Use-KutayUserHive -Hive $hive -Script { param($Root) $Root }

        $root | Should -Be 'HKU\KutayOS_default'
        Should -Invoke -ModuleName KutayUserHive Invoke-KutayRegExe -Times 1 -Exactly -ParameterFilter {
            $Arguments[0] -eq 'unload' -and $Arguments[1] -eq 'HKU\KutayOS_default'
        }
    }

    It 'unloads the hive even when the script fails' {
        { Use-KutayUserHive -Hive $hive -Script { throw 'boom' } } | Should -Throw '*boom*'

        Should -Invoke -ModuleName KutayUserHive Invoke-KutayRegExe -Times 1 -Exactly -ParameterFilter {
            $Arguments[0] -eq 'unload'
        }
    }

    It 'leaves a hive loaded by someone else alone' {
        Mock -ModuleName KutayUserHive Find-KutayLoadedHive { 'S-1-5-21-100-1001' }

        Use-KutayUserHive -Hive $hive -Script { } | Out-Null

        Should -Invoke -ModuleName KutayUserHive Invoke-KutayRegExe -Times 0 -Exactly
    }

    It 'opens the classes hive with -Classes' {
        $withClasses = [pscustomobject]@{ user = 'S-1-5-21-100-1001'; file = 'C:\Users\PC\NTUSER.DAT'; classes = 'C:\Users\PC\AppData\Local\Microsoft\Windows\UsrClass.dat' }

        $root = Use-KutayUserHive -Hive $withClasses -Classes -Script { param($Root) $Root }

        $root | Should -Be 'HKU\KutayOS_S-1-5-21-100-1001_Classes'
        Should -Invoke -ModuleName KutayUserHive Invoke-KutayRegExe -Times 1 -Exactly -ParameterFilter {
            $Arguments[0] -eq 'load' -and $Arguments[2] -like '*\UsrClass.dat'
        }
    }

    It 'skips the script with -Classes when the hive has no classes file' {
        $ran = Use-KutayUserHive -Hive $hive -Classes -Script { 'ran' }

        $ran | Should -BeNullOrEmpty
        Should -Invoke -ModuleName KutayUserHive Invoke-KutayRegExe -Times 0 -Exactly
    }

    It 'throws when reg unload keeps failing' {
        Mock -ModuleName KutayUserHive Invoke-KutayRegExe { if ($Arguments[0] -eq 'unload') { 1 } else { 0 } }
        Mock -ModuleName KutayUserHive Start-Sleep { }

        { Use-KutayUserHive -Hive $hive -Script { } } | Should -Throw '*unload*'
    }
}
