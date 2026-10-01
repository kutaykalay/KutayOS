# Slice 4 (Compact): disk space

Measured on 2026-10-01 in the test VM (Windows 11 IoT Enterprise LTSC 2024, 26100.9550, snapshot
`clean-9550-scanned`, 63 GB NVMe disk, 4 GB RAM) with `tools/vm/Invoke-TweakSmoke.ps1`. The guest
script reads free space on C: before and after each tweak's first run. One run, so treat the numbers
as rough: free space also moves with logs and caches.

## Starting state of the clean VM

Read with `tools/vm/guest-disk-usage.ps1`:

| Item | Value |
| --- | --- |
| Used / free on C: | 20.4 GB / 42.7 GB |
| Component store (actual) | 11.86 GB, of which 7.36 GB backups and disabled features; cleanup recommended |
| Compact OS | already on: Windows setup chose it for the 64 GB disk (`HKLM\SYSTEM\Setup\Compact = 1`) |
| Reserved storage | off: this VM fails the reserve policy (`ReserveManager\PassedPolicy = 0`) |
| Hibernation | not available: the VM firmware has no S4, so there is no hiberfil.sys |

So that each option really changes something, the smoke run first turned reserved storage on and
Compact OS off. Free space after that: 31.8 GB.

## Saving per tweak

| Tweak | Default | Freed |
| --- | --- | --- |
| component-cleanup | on | 8.0 GB |
| disable-reserved-storage | option | 6.3 GB |
| compact-os | option | 4.5 GB |
| disable-hibernation | option | 0 (not measurable in the VM; Microsoft's table: 1.5 GB on a 4 GB x64 device) |

Free space went from 31.8 GB to 50.6 GB over the whole first pass (+18.8 GB).

## Notes

- The cleanup saving fits the store analysis (7.36 GB of backups). On a PC with fewer installed
  updates it will be smaller.
- On a PC whose setup already chose Compact OS, or whose reserve is off, those options free nothing.
- Revert brought every state back (reserved storage Enabled, Compact OS Never); 284/284 checks passed.
  A second run on the final code (after the review fixes) passed 284/284 too, with the same savings
  within 10 MB.
