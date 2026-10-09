# Backlog: requested settings

Settings Kutay asked for, classified against the PRD. Each still needs a primary source and a VM
check before it becomes a tweak.

## Install-time (Rufus + install guide, not the playbook)

Rufus "Windows User Experience" ticks, decided 2026-09-26:

| Tick | Decision |
| --- | --- |
| Remove TPM / Secure Boot / RAM requirement | Not used |
| Remove online Microsoft account requirement | Install guide (`docs/install.md`) |
| Create local account (name `PC`) | Install guide (`docs/install.md`) |
| Set regional options from this PC | Install guide (`docs/install.md`) |
| Disable data collection (privacy questions) | Playbook: post-install privacy policies (Slice 1/2) |
| Disable BitLocker automatic device encryption | Deferred; opt-in with a warning if added |

Rufus tick wording is from memory (Rufus 4.x); verify on a real USB write before 1.0.0.

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

## Performance (Slice 5, open items)

Shipped: DiagTrack off (measured), CEIP tasks off (privacy), Edge background off (measured with a
logon). Results in `docs/measurements/slice5-performance.md`.

- **Delivery Optimization** and **visual effects**: candidates, not measured yet.
- **Which privacy tweak stops VaultSvc / InventorySvc and keeps wisvc running.** Not DiagTrack
  (isolated). Candidates: `AllowTelemetry=0`, `AITEnable=0`, CEIP tasks. Small effect, so isolate only
  if one of them turns out to matter.
- **Snapshot merge for new task names.** `Save-KutaySystemSnapshot` keeps the first snapshot as is,
  so a task added to `disable-ceip-tasks` in a later version would get no snapshot entry and revert
  would leave it disabled. Merge missing names into an existing snapshot before adding a task.
- **Dropped after the idle inventory** (not running at idle, or needed by general users): SysMain,
  scheduled defrag, Xbox services, troubleshooter services (DPS, WdiSystemHost, DiagSvc), RmSvc,
  DusmSvc, icssvc, lfsvc (automatic time zone), MapsBroker, WerSvc, System Restore task, PI folder
  tasks (Secure Boot updates), VerifyWinRE, memory diagnostics, Ultimate Performance plan (laptop
  heat), background apps, StartupDelay (undocumented), and tasks that never ran at idle (WinSAT,
  Maps, Family Safety, Work Folders).

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

## Real hardware (before 1.0.0)

The full AME run passed in the VM (`docs/measurements/slice6-fullrun.md`). Still to check on a real PC:

- A game with anti-cheat (Vanguard, FACEIT, EAC or BattlEye) launches after the run.
- `disable-hibernation` and its revert (see Compact above).
- The Rufus option wording in `docs/install.md`.
- The latest cumulative update installs after the run (the VM snapshot was already current).

## Apps (v2, decided 2026-10-06)

- **PotPlayer** as the video player.
- **nomacs** as the image viewer.
- **Brave** as the default browser. **Edge stays installed** (PRD: Edge/WebView2 are never removed).

Notes:

- Decided 2026-09-27: these ship as FeaturePages checkboxes (user can untick each app).
- Decided 2026-10-06: they stay in v2 with the other app installs, as the PRD says; v1 ships without
  them.
- LTSC 2024 ships without Microsoft Store / App Installer; confirmed in the VM. winget and Windows
  Terminal now install through the `install-winget-terminal` option (2026-10-09, see
  `docs/measurements/winget-terminal.md`), so these apps can use `winget install` instead of
  vendor installers (check each id in the community source first).
- Open after winget + Terminal: App Installer has no update path (`winget upgrade
  Microsoft.AppInstaller` unverified; pinned version only moves with a KutayOS release); a second
  user's first logon upgrading the stale provisioned Terminal; a run through AME Wizard itself.
- Setting default apps: Windows protects user file/URL associations, so a silent per-user switch is
  not supported. Candidate supported path: a default-associations XML (`Dism
  /Export-DefaultAppAssociations`) plus the "Set a default associations configuration file"
  policy. Verify in the VM that it works for `http`/`https` and the video/image types on LTSC.
- For general users these should be FeaturePages options, not forced installs.
