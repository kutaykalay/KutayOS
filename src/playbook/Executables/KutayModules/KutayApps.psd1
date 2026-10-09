@{
    # Pinned downloads for the optional "winget + Windows Terminal" step. Everything comes from
    # Microsoft's own GitHub releases; the SHA256 values below were computed from the downloaded files
    # and match the digests GitHub shows for the release assets (2026-10-09). KutayApps.psm1 checks the
    # hash AND the Microsoft Authenticode signature before anything is installed.
    # To update: take the new release, recompute every hash, change ProvisionedVersion (what Get-AppxProvisionedPackage reports in the VM) and the URLs together.
    Winget   = @{
        PackageName  = 'Microsoft.DesktopAppInstaller'
        # Version of the provisioned bundle (Get-AppxProvisionedPackage), not of the package users see (1.29.380.0).
        ProvisionedVersion = '2026.917.151.0'
        Bundle       = @{
            Url    = 'https://github.com/microsoft/winget-cli/releases/download/v1.29.380/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
            Sha256 = '65dea9c01ce08ee7b763366b27c0e651f97db857c11ca9b9c301826c10092f2e'
        }
        License      = @{
            Url    = 'https://github.com/microsoft/winget-cli/releases/download/v1.29.380/e53e159d00e04f729cc2180cffd1c02e_License1.xml'
            Sha256 = 'bcb15118ec47df24e3e6013a7006147c3a15b3a8104ed660fe87c8b4ed01f485'
        }
        Dependencies = @{
            Url    = 'https://github.com/microsoft/winget-cli/releases/download/v1.29.380/DesktopAppInstaller_Dependencies.zip'
            Sha256 = 'ba875afe9d190f61218985ac0292a99d1db710bf93e13c68944ca9d89f0d82d1'
        }
    }
    Terminal = @{
        PackageName = 'Microsoft.WindowsTerminal'
        # Provisioned bundle version, not the package version users see (1.25.2733.0). Seen in the VM 2026-10-09.
        ProvisionedVersion = '3001.25.2733.0'
        Kit         = @{
            Url    = 'https://github.com/microsoft/terminal/releases/download/v1.25.2733.0/Microsoft.WindowsTerminal_1.25.2733.0_8wekyb3d8bbwe.msixbundle_Windows10_PreinstallKit.zip'
            Sha256 = '151cb3ee9a93ba41ad7c412c0efd165a1e47eda6ef47d15a154c33af1e1cec9c'
        }
    }
}
