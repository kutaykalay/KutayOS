# winget on Windows 11 IoT Enterprise LTSC 2024 (research)

Time-boxed research, 2026-10-09. Tags: [primary] = learn.microsoft.com or github.com/microsoft; [community] = anything else.
Nothing was installed or run on the dev host; only GitHub API metadata and docs were read.

## 1. Official ways to get winget without the Store

- [primary] Microsoft Learn: winget is part of App Installer, delivered by the Store on desktop Windows. Store-less path given: GitHub releases of winget-cli. https://learn.microsoft.com/en-us/windows/package-manager/winget/
- [primary] Same page, "Install WinGet on Windows Sandbox" (Store also absent there): `Install-PackageProvider -Name NuGet -Force`, `Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery`, `Repair-WinGetPackageManager -AllUsers`. Same URL as above.
- [primary] Microsoft Learn troubleshooting: `Install-PackageProvider NuGet`, `Install-Module Microsoft.WinGet.Client -Repository PSGallery`, `Repair-WinGetPackageManager -Force -Latest`. https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting
- [primary] winget-cli troubleshooting doc: "Customers may install the latest stable release directly from the GitHub repository. These packages are signed." https://github.com/microsoft/winget-cli/blob/master/doc/troubleshooting/README.md
- [primary] Same doc, "Machine-wide Provisioning": `Add-AppxProvisionedPackage -online -PackagePath <msixbundle> -LicensePath <license> -DependencyPackagePath <VCLibs>`. Same URL.
- [primary] `-AllUsers` and `-IncludePrerelease` are named in the Sandbox section; `Get-Help Repair-WinGetPackageManager -Full` is the reference. The learn.microsoft.com cmdlet page returned 404 when fetched, so its exact parameter list is UNVERIFIED.

Latest stable release (GitHub API, checked 2026-10-09): **v1.29.380**, published 2026-09-21. https://github.com/microsoft/winget-cli/releases/tag/v1.29.380
Assets (exact names):
- `Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle` (217,276,577 bytes)
- `Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.txt` (64 bytes; likely SHA256 of the bundle, NOT verified by download)
- `e53e159d00e04f729cc2180cffd1c02e_License1.xml` (license, 2,686 bytes)
- `DesktopAppInstaller_Dependencies.zip` (97,760,717 bytes)
- `DesktopAppInstaller_Dependencies.json` and `.txt` (64 bytes)
- `DesktopAppInstallerPolicies.zip`

## 2. Dependencies for v1.29.380

- [primary] `DesktopAppInstaller_Dependencies.json` (same release):
  - `Microsoft.VCLibs.140.00` 14.0.33519.0
  - `Microsoft.VCLibs.140.00.UWPDesktop` 14.0.33728.0
  - `Microsoft.WindowsAppRuntime.1.8` 8000.616.304.0
  
  https://github.com/microsoft/winget-cli/releases/download/v1.29.380/DesktopAppInstaller_Dependencies.json
- Note: the brief assumed Microsoft.UI.Xaml 2.8. The current release manifest lists Windows App Runtime 1.8 instead. Architecture per package is not stated in the JSON; check the zip contents (UNKNOWN for the exact x64 file names).

## 3. All-users install

- [primary] Add-AppxProvisionedPackage: "adds an app package (.appx) that will install for each new user to a Windows image." Online mode: "The package will be installed for the current user and any new user account created on the computer." Usage requires `-Online`, `-PackagePath`, `-DependencyPackagePath`, `-LicensePath`. https://learn.microsoft.com/en-us/powershell/module/dism/add-appxprovisionedpackage
- [primary] winget-cli doc: "After the package is provisioned, the users need to log into their Windows account to get the package registered and use it." Same troubleshooting URL as above.
- [primary] Microsoft Learn winget page: "WinGet will not be available until you have logged into Windows as a user for the first time." Fallback: `Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe` (run as the user). https://learn.microsoft.com/en-us/windows/package-manager/winget/
- Conclusion: provisioning covers new users and users at next logon. Existing profiles may need logon or the RegisterByFamilyName call (run in that user's context). Whether an already-logged-on user gets it immediately is UNKNOWN.
- `Add-AppxPackage` (non-provisioned) only installs for the current user; it is not all-users.
- [primary] System context: "As packages can be registered for any user except NT AUTHORITY\SYSTEM ... the WinGet CLI is not supported in the system context. The Microsoft.WinGet.Client PowerShell module can be used in the system context with applications that are installed machine wide." https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting
  - So: do NOT rely on running `winget.exe` as SYSTEM. Use Microsoft.WinGet.Client for machine-wide installs, or run winget per user.

## 4. Self-update / msstore on LTSC

- [primary] winget-cli doc: "Customers will receive automatic updates if IT Policy does not block the Microsoft Store." https://github.com/microsoft/winget-cli/blob/master/doc/troubleshooting/README.md
- [primary] Same doc: "There is a known problem restoring the client to the latest stable App Installer release." (Old note; current state UNKNOWN.)
- `winget upgrade Microsoft.AppInstaller`: UNKNOWN, not verified. Assume re-running the provisioning script with a newer bundle is the only Store-free update path.
- [primary] Learn source page: default sources are `msstore` (Store catalog, endpoint `https://storeedgefd.dsx.mp.microsoft.com/v9.0`), `winget`, `winget-font`. https://learn.microsoft.com/en-us/windows/package-manager/winget/source
- msstore on LTSC without the Store app: UNKNOWN. Docs do not say it requires the Store app. Safer to treat `winget` (community source, `https://cdn.winget.microsoft.com/cache`) as the one to use and leave msstore alone.
- Source agreements: `--accept-source-agreements` avoids the interactive prompt (same source page). Needed for unattended runs.

## 5. Signature check

- [primary] `Get-AuthenticodeSignature` docs: returns signature info for a file; check `Status` ("Valid" expected). https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-authenticodesignature
- [primary] Microsoft SignTool docs: when signing a bundle, all packages inside are signed recursively. https://learn.microsoft.com/windows/msix/package/sign-app-package-using-signtool
- [community] Get-AuthenticodeSignature on .msixbundle works in practice (a PSGallery module does exactly this check). Not verified on this LTSC image. Also `signtool verify /pa /v <file>` as an alternative. Source: https://www.powershellgallery.com/packages/MSIXForcelets/1.0.5/Content/Public%5CTest-MSIXSignature.ps1
- Expected publisher subject: `CN=Microsoft Corporation, ...` (community/UNVERIFIED; check the actual `SignerCertificate.Subject` on a downloaded bundle before pinning it).
- SHA256 publication: [primary] the release has `.txt` assets with 64 hex chars. Fetched contents: `Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.txt` = `65DEA9C01CE08EE7B763366B27C0E651F97DB857C11CA9B9C301826C10092F2E`; `DesktopAppInstaller_Dependencies.txt` = `BA875AFE9D190F61218985AC0292A99D1DB710BF93E13C68944CA9D89F0D82D1`. Presumed SHA256 of each file, NOT verified by download. Verify with `Get-FileHash -Algorithm SHA256` before trusting it.

## Unknowns (not verified)
- Learn cmdlet page for Repair-WinGetPackageManager (404 during fetch). Parameters and SYSTEM behavior of `-AllUsers`.
- Whether an already-logged-on user sees a provisioned winget without logon.
- msstore source behavior on LTSC.
- Store-less self-update path.
- Exact x64 dependency file names inside DesktopAppInstaller_Dependencies.zip.
- Actual SHA256 of the msixbundle and whether the `.txt` file matches it.
- Publisher subject string of the signed bundle.
