# Slice 5 (Performance): idle measurements

Measured on 2026-10-05 and 2026-10-06 in the test VM (Windows 11 IoT Enterprise LTSC 2024,
26100.9550, 8 GB RAM, 4 vCPU, NVMe) on the desktop host (Ryzen 5 9600X, 32 GB, VMware Workstation
26.0.1). Tool: `tools/vm/measure-baseline.ps1 -NoLogon`, compared with `tools/vm/Compare-Baseline.ps1`.
Raw files: `docs/measurements/slice5/`.

## Method

- **Two snapshots made the same way.** `kutay-applied` is the clean VM with every default-on tweak
  applied by `Invoke-TweakSmoke.ps1 -SaveAppliedAs`; `clean-control` is the same clean VM put through
  the same boot, 10 minute idle and shutdown with no tweaks (`-Control`). So both carry the same
  first-boot maintenance history, and the only difference is the playbook.
- **Fixed uptime.** Each run reverts the snapshot, boots without a logon, waits until the VM is quiet
  (CPU under 10 % for 5 minutes) and measures no earlier than 30 minutes after boot. CPU is sampled
  for 120 seconds; the inventory (services, processes with private bytes, scheduled tasks) is taken
  right after.
- **Three pairs**, control and applied run back to back in the same job.
- No logon, so these numbers cover services and system processes only. Boot time and per-user
  processes (Edge) are in "With a logon" below.

## Results (average of 3 pairs)

| Metric | clean-control | kutay-applied | Change | Spread |
| --- | --- | --- | --- | --- |
| Processes | 95 | 92 | -3 | same in every run |
| Running services | 80 | 77 | -3 | same in every run |
| Commit charge | 2097 MB | 2013 MB | -84 MB | control 2096-2098, applied 2008-2018 |
| Private bytes, all processes | 825 MB | 800 MB | -25 MB | control 820-829, applied 798-803 |
| Private bytes, svchost | 243 MB | 216 MB | -27 MB | +/- 1 MB |
| RAM in use | 2373 MB | 2236 MB | -137 MB | noisy (2211-2433), same sign in each pair |
| CPU at idle (avg) | 1.5 % | 1.5 % | 0 | 1.4-1.6 % |
| Minutes until quiet | 9.3 | 9 | -0.3 | 8-10 |

Stable differences (in all 3 pairs):

| Item | clean-control | kutay-applied |
| --- | --- | --- |
| DiagTrack (own svchost, ~24 MB private) | running | not running |
| InventorySvc (~2 MB) | running | not running at 30 min |
| lfsvc, Geolocation (~4 MB) | running | not running |
| VaultSvc, Credential Manager (runs inside lsass) | running | not running |
| wisvc, Windows Insider Service (~1.4 MB) | not running | running |
| AggregatorHost.exe (~2 MB) | running | not running |

## Why the services differ

None of the tweaks touches VaultSvc, wisvc, InventorySvc or lfsvc. Their start type, delayed flag
and triggers (`sc qtriggerinfo`) are identical in both snapshots; only DiagTrack's start type
differs (Auto vs Disabled). So the differences come from what other components do at run time.

To see when each service starts and stops, a guest script polled the five services every 15 seconds
from boot to 32 minutes of uptime (the SCM does not log 7036 state changes on this build, so the
event log can't answer it). Same snapshots, one boot each, plus an isolation run: `clean-control`
with only DiagTrack `Start=4` set, then restarted.

| Service | clean-control | only DiagTrack off | kutay-applied |
| --- | --- | --- | --- |
| DiagTrack | running from boot | not running | not running |
| lfsvc | starts at 10.4 min | never starts | never starts |
| VaultSvc | starts at 9.6 min | starts at 9.7 min | never starts |
| InventorySvc (delayed auto) | starts at 2.4 min, stays | starts at 2.2 min, stays | starts at 2.4 min, stops at 20.1 min |
| wisvc | runs 0.6-1.6 min | not seen | starts at 0.6 min, stays |

- **lfsvc** follows DiagTrack: with DiagTrack off, nothing triggers the Geolocation service at idle.
  Its triggers are unchanged, so it still starts when something asks for location (for example
  automatic time zone).
- **VaultSvc, InventorySvc, wisvc** do not follow DiagTrack. They change with the rest of the default
  set: the privacy policies (`AllowTelemetry=0`, `AITEnable=0`, `CEIPEnable=0`, ...) and the disabled
  CEIP tasks. Which one of those was not isolated further; the effect is small (VaultSvc runs inside
  lsass, so stopping it saves no process; InventorySvc about 2 MB; wisvc costs about 1.4 MB).
- **AggregatorHost.exe** was not part of the isolation run.
- `Start=4` alone is enough to keep DiagTrack from starting; whether `AllowTelemetry=0` alone would
  also stop it was not tested.

## With a logon (2 pairs)

Same snapshots and fixed uptime, but with a desktop logon, so per-user processes (Edge) and boot
time count too. The logon is automatic: after each snapshot revert the run sets Winlogon autologon
in the guest (registry plus the LSA secret `DefaultPassword`), restarts the guest and measures that
boot. Never saved into a snapshot. Boot time is Diagnostics-Performance event 100 of that boot,
read at the end of the run (event 100 is written only after the post-boot phase).

| Metric | clean-control | kutay-applied | Change | Runs |
| --- | --- | --- | --- | --- |
| Boot, main path (to desktop) | 14.6 s | 10.6 s | -4.0 s | control 14.5 / 14.7, applied 10.9 / 10.3 |
| Boot, total (event 100) | 31.4 s | 29.4 s | not significant | control 28.3 / 34.5, applied 31.6 / 27.1 |
| Processes | 135 | 126.5 | -8.5 | |
| Running services | 92.5 | 88 | -4.5 | |
| Commit charge | 2628 MB | 2443 MB | -185 MB | |
| Private bytes, all processes | 1337 MB | 1206 MB | -131 MB | |
| msedge.exe after logon | 6 (77 MB) | 0 | -6 | same in every run |
| CPU at idle (avg) | 2.0 % | 2.0 % | 0 | |

- Without the playbook, Edge starts six background processes at sign-in (startup boost) although
  no one opened it. With `disable-edge-background` none run.
- The main boot path was shorter in both applied runs than in both control runs. With two pairs
  that is a consistent sign, not a precise number. Total boot time varies too much (28-35 s) to claim
  anything.
- AppIDSvc ran only in the control runs, and DefenderSessionHelper.exe and rundll32.exe only in the
  applied runs. Not investigated.
- The earlier logon run typed by hand (`discarded/manual-logon-control-1*`) read event 100 too early
  and has no boot time.

## Decisions

- **disable-diagtrack-service: default on.** Measured: DiagTrack is its own svchost with about
  24 MB private bytes, and with it off the Geolocation service no longer starts at idle. The whole
  default set gives -3 processes, -3 services, -84 MB commit and -25 MB private bytes; idle CPU does
  not change on this host.
- **disable-ceip-tasks: default on as a privacy tweak** (documented), not as a performance claim.
- **disable-edge-background: default on.** Measured with a logon: six msedge.exe processes (about
  77 MB private bytes) no longer start at sign-in. The cost is a slower first Edge start, and the user
  can turn both settings back on in Edge (Recommended policies).
- **Idle CPU is not a reason for any Slice 5 tweak.** It was 1.5 % with and without the playbook.

## Not comparable, kept for the record

`slice5/discarded/` holds runs that must not be compared with the table above:

- `laptop-*`: pair 1 on the previous host (laptop, 4 GB / 2 vCPU VM).
- `manual-unlock-control-1*`: the VM window waited about a minute for the encryption password typed
  by hand, so the guest booted later than in the other runs.
- `clean-nologon-*`, `applied-nologon-1*`: the first clean-vs-applied comparison (2026-10-01, laptop)
  measured the two sides at different uptimes (26 vs 6 minutes); that is why `clean-control` exists.
