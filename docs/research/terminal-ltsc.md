# Windows Terminal on Windows 11 LTSC 2024 without the Store (research)

Time-boxed research, 2026-10-09. Tags: [primary] = learn.microsoft.com or github.com/microsoft;
[community] = anything else. Items marked UNKNOWN were not verified.

## 1. Install sources

- Latest stable release: v1.25.2733.0, published 2026-10-02.
  [primary] https://api.github.com/repos/microsoft/terminal/releases/latest
- Release assets (relevant):
  - Microsoft.WindowsTerminal_1.25.2733.0_8wekyb3d8bbwe.msixbundle (23,809,353 bytes; one bundle for all archs)
  - Microsoft.WindowsTerminal_1.25.2733.0_8wekyb3d8bbwe.msixbundle_Windows10_PreinstallKit.zip (42,869,026 bytes)
  - Microsoft.WindowsTerminal_1.25.2733.0_x64.zip / _x86 / _arm64 (portable, unpackaged, no auto-update)
  - GroupPolicyTemplates_1.25.2733.0.zip (ADMX/ADML)
  - Microsoft.Windows.Console.ConPTY.1.25.260930003.nupkg
  - Source: same API call as above.
- Asset name says "Windows10" for the PreinstallKit. There is no separate Win11 bundle in the
  release list. Whether the same bundle is the Win11 build is UNKNOWN; the single msixbundle is
  the one winget uses.
- PreinstallKit zip contents (license XML, dependency appx files): UNKNOWN, not opened.
- Learn install page: "If you don't have access to the Microsoft Store, you can find builds on the
  GitHub releases page. If you install from GitHub, Windows Terminal doesn't automatically update."
  [primary] https://learn.microsoft.com/en-us/windows/terminal/install
- Release body text does not mention PreinstallKit, VCLibs or UI.Xaml.
  [primary] https://api.github.com/repos/microsoft/terminal/releases/latest

## 2. winget package

- Manifest path for this version:
  https://github.com/microsoft/winget-pkgs/tree/master/manifests/m/Microsoft/WindowsTerminal/1.25.2733.0
  [primary]
- InstallerType: msix. Scope: user. No InstallerSwitches.
  [primary] https://raw.githubusercontent.com/microsoft/winget-pkgs/master/manifests/m/Microsoft/WindowsTerminal/1.25.2733.0/Microsoft.WindowsTerminal.installer.yaml
- InstallerUrl for x86, x64 and arm64 is the same msixbundle on the GitHub release.
  InstallerSha256: CCE6E9CC3C8457FA11CED1D2A7354888C7D6DB83C5ACE5D5891A52C95E3B21DA
  SignatureSha256: 90F4FEDC8F2327C278CAD2624FAF41FB9743858049E1D9A6F3B78264810CF516
  [primary] same installer.yaml URL as above
- Winget does not list VCLibs in this manifest. Only Microsoft.UI.Xaml.2.8, MinimumVersion
  8.2306.22001.0. VCLibs requirement: UNKNOWN (may be inside the bundle or the dependency zip).
- winget installs as the user. Upgrade is `winget upgrade --id Microsoft.WindowsTerminal --exact`
  with `--silent --accept-package-agreements --accept-source-agreements`.
  [primary] https://learn.microsoft.com/en-us/windows/package-manager/winget/upgrade
- winget itself is part of App Installer, delivered by the Store. winget is not available until a
  user has logged on once; the registration command is
  `Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe`.
  [primary] https://learn.microsoft.com/en-us/windows/package-manager/winget/
- Winget in SYSTEM context is unreliable. No Microsoft statement found; sources are community:
  winget is tied to the user profile; full-path call to the App Installer exe is a reported
  workaround. [community] https://medium.com/@karthik.in04/why-winget-fails-in-intune-system-context-and-how-proper-resolution-enables-enterprise-grade-0d61980ec03f
  [community] https://github.com/microsoft/winget-cli/issues/4271
- Note: the winget upgrade doc does not say whether upgrading a provisioned MSIX updates the
  provisioned copy. UNKNOWN.

## 3. Dependencies

- Microsoft.UI.Xaml.2.8 >= 8.2306.22001.0 (from the winget manifest, primary as above).
- VCLibs Desktop 14.00: UNKNOWN for this version.
- The winget manifest version of the dependency is a hint, not a complete list. Check with
  Get-AppxPackageManifest on the bundle before provisioning (not done here).

## 4. Provisioning for all users

- Add-AppxProvisionedPackage "adds an app package (.appx) that will install for each new user to a
  Windows image." It has -LicensePath, -SkipLicense and -DependencyPackagePath.
  [primary] https://learn.microsoft.com/en-us/powershell/module/dism/add-appxprovisionedpackage
- The docs say the package "will be installed for the current user and any new user account" for
  -Online with -FolderPath. Behavior for users that already exist: the page says provisioning is for
  new users; for existing users it is not stated here. UNKNOWN from primary docs.
- The docs say "Use the PackagePath, DependencyPackagePath, and LicensePath parameters ... Use these
  parameters to provision line-of-business apps." A PreinstallKit license is needed for a non-Store
  package to provision without -SkipLicense. -SkipLicense docs warn: use only where no license is
  required on Enterprise or Server.
  [primary] same page above. Whether the PreinstallKit license must be passed for this bundle: UNKNOWN (not verified).
- Provisioning on a system that already has a per-user install may fail or skip; UNKNOWN.

## 5. Auto-update without the Store

- Terminal has no built-in updater for GitHub or winget installs. [primary]
  https://learn.microsoft.com/en-us/windows/terminal/install
  (only the Store version updates automatically).
- The GitHub README "other install methods" section (winget, Chocolatey, Scoop) was fetched, but the
  page content returned did not include winget-specific upgrade text. Chocolatey and Scoop have
  upgrade commands per the README. [primary] https://github.com/microsoft/terminal
- Scheduled winget upgrade: the command is in the winget upgrade doc. Account context (user logon
  task vs SYSTEM) is not settled by primary docs. Community evidence says SYSTEM is unreliable for
  winget. Suggested approach to test in the VM: a per-user logon or daily task, plus a check for the
  installed version. UNKNOWN until tested.
- Does a per-user upgrade leave the provisioned copy old: UNKNOWN. Needs a VM test (Get-AppxPackage
  and Get-AppxProvisionedPackage versions after upgrade).
- Microsoft-documented approach for updating a provisioned MSIX: not found in the pages read.

## 6. Default terminal application (Win11 24H2)

- Registry: HKCU\Console\%%Startup, values DelegationTerminal and DelegationConsole (REG_SZ).
  [primary] https://learn.microsoft.com/en-us/windows/terminal/group-policy
- GUIDs (primary, same page):
  - Automatic: {00000000-0000-0000-0000-000000000000} (both values)
  - Windows Console Host: {B23D10C0-E52E-411E-9D5B-C09FDF709C7D} (both values)
  - Windows Terminal: DelegationTerminal {E12CFF52-A866-4C77-9A90-F570A7AA2C6B},
    DelegationConsole {2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}
  - Windows Terminal Preview: DelegationTerminal {86633F1F-6454-40EC-89CE-DA4EBA977EE2},
    DelegationConsole {06EC847C-C0A5-46B8-92CB-7C92F6E35CD5}
- Policy scope: User only. Supported on Win11 22H2+ with Terminal 1.17+. Acts as a preference (not
  removed when unset). [primary] same group-policy page.
- Is Terminal the default host on 24H2 when installed: the "Automatic" value means "Windows Terminal,
  if available" per the group-policy doc, but the factory default on a fresh 24H2 image is UNKNOWN.
  Set the Windows Terminal values explicitly to be sure.
- Note: writing the values in HKCU applies per user. For all users, use HKU\<SID> or a logon
  script / default user hive. Not verified.

## 7. Signature and hashes

- Installer SHA256 and the signature SHA256 are published in the winget manifest (see section 2).
  [primary] installer.yaml URL above.
- Publisher subject of the msixbundle signature: UNKNOWN, not checked. Check with
  Get-AuthenticodeSignature or the appx signature on the downloaded file before provisioning.
- The release page does not publish hashes in the body (only assets). [primary] releases API.

## Unknowns (to test in the VM)

1. VCLibs requirement and the exact dependency list in the PreinstallKit zip.
2. Contents of the PreinstallKit license XML and whether it is needed for provisioning.
3. Publisher subject of the signature; verify against the downloaded bundle.
4. Whether an existing per-user install is updated or blocked by provisioning.
5. Scheduled-task account (user vs SYSTEM) that can run winget upgrade for Terminal.
6. Whether an upgraded per-user copy leaves the provisioned copy old.
7. Default host on a fresh 24H2 LTSC image without any registry write.
