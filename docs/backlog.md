# Backlog: requested settings

Settings Kutay asked for, classified against the PRD. Each still needs a primary source and a VM
check before it becomes a tweak.

## Install-time (Rufus + install guide, not the playbook)

Rufus "Windows User Experience" ticks, decided 2026-09-26:

| Tick | Decision |
| --- | --- |
| Remove TPM / Secure Boot / RAM requirement | Not used |
| Remove online Microsoft account requirement | Install guide (Slice 6) |
| Create local account (name `PC`) | Install guide (Slice 6) |
| Set regional options from this PC | Install guide (Slice 6) |
| Disable data collection (privacy questions) | Playbook: post-install privacy policies (Slice 1/2) |
| Disable BitLocker automatic device encryption | Deferred; opt-in with a warning if added |

Rufus tick wording is from memory; verify on a real USB write.

## Shell (Slice 3)

- **Hide the taskbar search box.** Per-user setting (`SearchboxTaskbarMode`), with the policy
  alternative (Policy CSP `Search/ConfigureSearchOnTaskbarMode`). Search itself stays working.
- **Hide the Task View button.** Per-user setting (`ShowTaskViewButton`), policy alternative
  exists. Win+Tab keeps working.

Open: per-user value (user can turn it back on) vs. policy (locked). Default to the per-user value,
applied to existing users and the default profile.

Prerequisite: state snapshots cover only the current user today. Per-user tweaks need snapshots
for every user hive plus the default profile, so revert is complete for all accounts.

## Compact (Slice 4, open items)

Shipped: component store cleanup (default, one-way), and options for hibernation off, Compact OS and
reserved storage off. Savings in `docs/measurements/slice4-disk.md`.

- **Hibernation on real hardware.** The VM firmware has no S4, so `disable-hibernation` and its
  revert have only run as a no-op. Check on a real PC, including whether `powercfg /hibernate on`
  keeps a reduced hiberfile type.
- **Not taken from WinUtil:** Storage Sense off (works against free space), Disk Cleanup / cleanmgr
  (DISM covers the component store), temp file deletion (small gain, Windows cleans it), and
  `/ResetBase` (installed updates could no longer be uninstalled).

## Privacy, per-user (parked from Slice 2)

Slice 2 shipped device-wide (HKLM) policies only. These wait for the multi-hive snapshots above:

- **DisableTailoredExperiencesWithDiagnosticData** (HKCU policy).
- **DisableThirdPartySuggestions** (HKCU policy).
- **Web results in Start search** (`DisableSearchBoxSuggestions`, HKCU policy).

Also unresolved (see `docs/research/privacy-policies.md`):

- `ConnectedSearchUseWeb=0`: the CSP page says Windows 10 1803+, the LTSC `Search.admx` says
  `WinBlueOnly`. Verify in the VM before use.
- `DisableInventory`: unclear whether Inventory Collector still exists in 24H2.
- Find My Device, app location access, Windows Error Reporting: candidates for opt-in options with
  a warning.

## Apps (new, not in the v1 PRD)

- **PotPlayer** as the video player.
- **nomacs** as the image viewer.
- **Brave** as the default browser. **Edge stays installed** (PRD: Edge/WebView2 are never removed).

Notes:

- Decided 2026-09-27: these ship as FeaturePages checkboxes (user can untick each app). The PRD
  moved app installs (winget) to v2; pulling them into v1 as a new slice between 5 and 6 is proposed
  and needs a PRD update.
- LTSC 2024 ships without Microsoft Store / App Installer, so `winget` is likely absent; verify in
  the VM. Fallback: official vendor installers with signature check.
- Setting default apps: Windows protects user file/URL associations, so a silent per-user switch is
  not supported. Candidate supported path: a default-associations XML (`Dism
  /Export-DefaultAppAssociations`) plus the "Set a default associations configuration file"
  policy. Verify in the VM that it works for `http`/`https` and the video/image types on LTSC.
- For general users these should be FeaturePages options, not forced installs.
