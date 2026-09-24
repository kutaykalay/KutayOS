# KutayOS Project Rules

These rules take precedence over the generic ECC rules in `../ecc/`.

## Red lines (never)
- Never run playbook scripts or system-modifying commands on the dev host (Windows 11 Home). Real behavior is tested only in the LTSC 2024 VirtualBox VM. `.claude/hooks/host-guard.js` enforces this.
- Never touch anti-cheat requirements: Secure Boot, TPM, driver signature enforcement / testsigning, `bcdedit` hypervisor/debug/nx settings, anti-cheat services (vgc, vgk, FACEIT, EasyAntiCheat*, BEService). Vanguard, FACEIT, EAC and BattlEye must keep working.
- VBS/HVCI (Memory Integrity) changes only behind an explicit opt-in option with a warning; default leaves it untouched.
- No hosts-file telemetry blocking (Defender flags it, some endpoints bypass it). Use policies/registry and firewall rules.
- License is GPL-3.0-or-later (`LICENSE`). Code from GPL-3.0 (AtlasOS, Revision Tool), CC-BY-SA-4.0 (ReviOS playbook) and MIT (WinUtil) projects may be reused, but every reused file or block needs an attribution comment: source project, URL, original license. Never reuse code from projects with no license or a proprietary/non-commercial license.

## Every tweak
- Lives in `src/playbook/Configuration/tweaks/<category>/<id>.yml` with `title` and `description`.
- Has a source/justification link in a comment above the action.
- Declares an evidence level in a comment: `measured` | `documented` | `community`. Latency/performance tweaks need `measured` (LatencyMon/xperf before/after) before they are enabled by default.
- Is revertible: prior state is snapshotted before the change, and a matching revert script exists under `Executables/KutayDesktop`.
- Anything that reduces security or may break apps sits behind an `option:` from a `FeaturePages` entry in `playbook.conf`.

## PowerShell
- Target Windows PowerShell 5.1: no `??`, `?:`, `&&`/`||`, `ForEach-Object -Parallel`, `-AsHashtable`.
- ASCII-only source, or UTF-8 with BOM (5.1 misreads BOM-less UTF-8).
- `$ErrorActionPreference = 'Stop'` and a non-zero exit code on failure, so AME `handleExitCodes` can halt.
- Scripts must be idempotent (safe to run twice).

## Testing
- Pester 5 for pure logic, with registry/service cmdlets mocked. VM smoke test for real behavior.
- ECC's 80% coverage rule applies to pure helpers and the C# Toolbox, not to scripts whose only job is changing system state.
- ECC web rules (SQL injection, XSS, CSRF, rate limiting, auth) do not apply to the playbook.
