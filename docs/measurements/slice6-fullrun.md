# Slice 6 (Release): full AME run

Run on 2026-10-06 in the test VM (Windows 11 IoT Enterprise LTSC 2024, 26100.9550, snapshot
`clean-9550-scanned`, 8 GB RAM, 4 vCPU). First run of the real package through AME Wizard; until
now the tweak smoke test (`tools/vm/Invoke-TweakSmoke.ps1`) only replayed the playbook's commands.

## Setup

- Package: `dist/KutayOS-0.9.0.apbx` from `tools/build.ps1`.
- AME Wizard Beta (`AME Beta.exe`, downloaded from ameliorated.io in the VM; the file is not
  Authenticode signed), run by hand in the VM console as the local admin `PC`.
- Every FeaturePages option ticked (8 of 8), so each tweak and its revert ran.
- Smoke test on the same code before the run: 328/328 PASS.

## Playbook run

From `%windir%\KutayOS\Logs\install.log`:

| Step | Time |
| --- | --- |
| Start, modules copied, restore point (sequence 1) | 21:19:39 to 21:19:46 |
| Privacy, shell and performance tweaks | 21:19:46 to 21:20:07 |
| Component store cleanup (exit code 0) | 21:20:07 to 21:24:03 |
| Compact OS, then AME restarted the PC | 21:24:03, boot at 21:24:27 |

About 5 minutes, most of it the component store cleanup. 29 snapshots in `%windir%\KutayOS\State`:
30 tweaks minus `component-cleanup`, which is one-way by design.

## Applied values (after the restart)

- 17 machine values (HKLM policies, DiagTrack `Start = 4`): all as the tweak files say.
- 11 per-user values, read in the mounted hives of `PC` and the default profile: all as the tweak
  files say. Read through `HKCU` by a vmrun guest process, the same values look missing: with no
  one logged on, that process does not see `PC`'s hive. Per-user checks must mount the hive.
- CEIP tasks: the 5 tasks disabled. DiagTrack stopped. Compact OS on (it was already on: setup
  chose it for the 64 GB disk). No hiberfil.sys (the VM has no S4).

## Health check (`KutayDesktop\Test-KutayHealth.ps1`, after the restart)

| Check | Result |
| --- | --- |
| Windows Update | PASS: services can start, update search succeeded, 0 updates available |
| Microsoft Defender | PASS: `AMRunningMode` Normal, antivirus and real-time protection on, tamper protection on, signatures 0 days old |
| Windows Search | PASS: WSearch runs, the index returns results |
| WebView2 Runtime | PASS: 154.0.4258.53, per-machine |

Exit code 0. The snapshot was already on the latest cumulative update, so "the latest CU installs"
was shown as a successful update search, not as an install. Re-check on the next Patch Tuesday.

## Revert all (`tools/vm/guest-revert-check.ps1`)

`Revert-KutayOS.ps1 -All` exit code 0 in about 5 seconds. Each saved snapshot compared with the
state after the revert (`Compare-KutaySnapshot`): 29 of 29 with 0 differences, no snapshot left.

## Not covered here

- An anti-cheat protected game (Vanguard does not run in a VM) and hibernation (no S4 in the VM):
  real-hardware checks before 1.0.0.
- A run with the default options only: the default path is a subset of this run and is covered by
  the smoke test.
