BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\tools\vm\VmGuest.psm1') -Force
    $script:vmx = Join-Path $TestDrive 'test.vmx'
}

AfterAll {
    Remove-Module VmGuest -ErrorAction SilentlyContinue
}

Describe 'Set-VmxValue' {
    It 'replaces a value and keeps CRLF line endings' {
        [IO.File]::WriteAllText($vmx, "memsize = `"4096`"`r`nnumvcpus = `"2`"`r`n")

        Set-VmxValue -Vmx $vmx -Values ([ordered]@{ memsize = 8192 })

        [IO.File]::ReadAllText($vmx) | Should -BeExactly "memsize = `"8192`"`r`nnumvcpus = `"2`"`r`n"
    }

    It 'matches a key regardless of case' {
        [IO.File]::WriteAllText($vmx, "numVCPUs = `"2`"`r`n")

        Set-VmxValue -Vmx $vmx -Values ([ordered]@{ numvcpus = 4 })

        [IO.File]::ReadAllText($vmx) | Should -BeExactly "numvcpus = `"4`"`r`n"
    }

    It 'appends a missing key with the file''s line ending' {
        [IO.File]::WriteAllText($vmx, "memsize = `"4096`"`r`n")

        Set-VmxValue -Vmx $vmx -Values ([ordered]@{ 'uuid.action' = 'keep' })

        [IO.File]::ReadAllText($vmx) | Should -BeExactly "memsize = `"4096`"`r`nuuid.action = `"keep`"`r`n"
    }

    It 'does not touch a longer key that starts with the same name' {
        [IO.File]::WriteAllText($vmx, "memsize.min = `"1`"`nmemsize = `"4096`"`n")

        Set-VmxValue -Vmx $vmx -Values ([ordered]@{ memsize = 8192 })

        [IO.File]::ReadAllText($vmx) | Should -BeExactly "memsize.min = `"1`"`nmemsize = `"8192`"`n"
    }

    It 'fails when the key is in the file more than once' {
        [IO.File]::WriteAllText($vmx, "memsize = `"4096`"`nmemsize = `"2048`"`n")

        { Set-VmxValue -Vmx $vmx -Values ([ordered]@{ memsize = 8192 }) } | Should -Throw '*memsize*2 times*'
    }
}
