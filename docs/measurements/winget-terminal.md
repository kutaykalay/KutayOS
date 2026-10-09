# winget and Windows Terminal (option `install-winget-terminal`)

Run on 2026-10-09 in the test VM (Windows 11 IoT Enterprise LTSC 2024, 26100.9550, snapshot `clean`,
8 GB RAM, 4 vCPU, internet through the host). The modules were copied to `%windir%\KutayOS` and
`Install-KutayApps.ps1` ran from there, the same way AME runs it after `Initialize-Kutay.ps1`. The
step has not yet been run through AME Wizard itself.

## What was checked

| Check | Result |
| --- | --- |
| Clean LTSC has neither App Installer nor Terminal | confirmed (`Get-AppxPackage -AllUsers`, `Get-AppxProvisionedPackage`) |
| `wsreset -i` installs the Microsoft Store | yes, in about 1 minute (Store 22608.1401), but it brought no App Installer and the Store did not update anything in 6 minutes (MDM UpdateScan, nobody signed in). Not used: no proof that it keeps Terminal updated, and it adds a consumer app |
| Download and install, first run | worked; about 3 minutes for the 217 MB App Installer bundle, 1.5 minutes for the dependencies zip, a few seconds to provision |
| Hash and signature | all four pinned SHA256 values match GitHub's digests; bundle, dependencies and Terminal kit files are `Valid`, signer `CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US` |
| Second run (idempotent) | skipped both packages ("already provisioned"), task re-registered, snapshots unchanged |
| winget for the signed-in user | `winget --version` = v1.29.380, `wt.exe` on PATH, both right after provisioning, without a new logon |
| Update task | task `\KutayOS\Update Windows Terminal` runs as the logged-on user (Users group principal, limited), `winget upgrade` ended with "no applicable update" and the task result was 0 |
| Real upgrade | Terminal 1.24.10921.0 provisioned, task started: winget upgraded it to 1.25.2733.0 (exit 0, new version staged, the old one stays until Terminal is closed) |
| Triggers | at logon with a 5 minute delay, and daily at 12:00 |
| Revert | the task is removed; Terminal (provisioned copy and every user copy, also the upgraded one) is removed |

## Findings that changed the design

- **Provisioned version is not the package version.** `Get-AppxProvisionedPackage` reports
  `2026.917.151.0` for App Installer 1.29.380.0 and `3001.25.2733.0` for Terminal 1.25.2733.0. The
  skip-if-installed check compares provisioned versions, so `KutayApps.psd1` carries
  `ProvisionedVersion`.
- **App Installer cannot be uninstalled.** `Remove-AppxPackage` fails with 0x80070032 ("part of
  Windows and cannot be uninstalled") and `Remove-AppxProvisionedPackage` with "Removal failed".
  The revert therefore only removes Terminal and the task; winget stays.
- **The provisioned Terminal copy does not follow upgrades.** After winget upgraded the signed-in
  user to 1.25, the provisioned copy was still 1.24. A new user gets the old build first and the
  logon task upgrades it five minutes after sign-in.
- **winget is not supported as SYSTEM** (Microsoft Learn), so the task runs per user instead.
- `Revert-KutayOS.ps1 -Id a, b` through `powershell -File` is read as one value; use `-All`, or a
  PowerShell session, for several ids.

## After the review fixes (same day, fresh `clean` snapshot)

The code review, security review and silent-failure review (all three ran on the first version)
led to: a work folder under `%windir%\KutayOS\Work` that only SYSTEM and Administrators can write,
the signatures checked again right before each package is installed, an issuer and code signing
EKU check on top of the subject, a zip extraction that refuses entries outside the target folder,
download retries (3 attempts, timeout), winget launch failures reported as such, "package not
installed for this user" no longer counted as success (the task ends with 2), a revert that
leaves a package or task alone that was removed by hand (instead of failing for ever), and an
explicit ACL on `%windir%\KutayOS`.

Run on a fresh `clean` snapshot with `Initialize-Kutay.ps1` then `Install-KutayApps.ps1`:

| Check | Result |
| --- | --- |
| `icacls C:\Windows\KutayOS` | SYSTEM and Administrators full control, Users read and execute, nothing else |
| Install | exit 0 in 351 s (download of 360 MB over the host's connection is most of it) |
| Work folder afterwards | gone |
| winget, `wt.exe`, task | present for the signed-in user, task `Ready`, Users group principal, logon (+5 min) and daily triggers |
| Task run | result 0; winget's output ("No available upgrade found") is logged because its exit code is not 0 |
| `Revert-KutayOS.ps1 -All` | exit 0: task and Terminal gone, winget stays |

## Accepted trade-offs

- After the first update, Terminal's trust depends on Microsoft's winget package repository (its
  manifests carry hashes), not on the SHA256 pinned in `KutayApps.psd1`.
- App Installer is only updated when KutayOS ships a new pinned version. A very old winget client
  may eventually be rejected by the winget source; the task then ends non-zero and the reason is in
  `%LOCALAPPDATA%\KutayOS\terminal-update.log`.
- A run that fails after winget was installed leaves winget in place (Windows will not remove it).
  Running KutayOS again skips it and carries on.
- No internet means the run stops, before anything else is changed. Untick the option to install
  offline.
- ARM64 is supported in the code (dependency folders exist) but untested.

## Not checked yet

- A run through AME Wizard with the option ticked (cleanup, restart).
- A second user signing in for the first time (does the logon task upgrade the provisioned copy?).
- App Installer's own updates (`winget upgrade Microsoft.AppInstaller`); it stays at the pinned
  version until KutayOS ships a new one.
- Terminal as the default terminal application on 24H2 (not changed by KutayOS).
