# KutayOS Project Rules

These rules take precedence over the generic ECC rules in `../ecc/`.

## Red lines (never)
- Never run playbook scripts or system-modifying commands on the dev host (Windows 11 Home). Real behavior is tested only in the LTSC 2024 VMware Workstation VM. `.claude/hooks/host-guard.js` enforces this.
- Never touch anti-cheat requirements: Secure Boot, TPM, driver signature enforcement / testsigning, `bcdedit` hypervisor/debug/nx settings, anti-cheat services (vgc, vgk, FACEIT, EasyAntiCheat*, BEService). Vanguard, FACEIT, EAC and BattlEye must keep working.
- VBS/HVCI (Memory Integrity) changes only behind an explicit opt-in option with a warning; default leaves it untouched.
- No hosts-file telemetry blocking (Defender flags it, some endpoints bypass it). Use policies/registry and firewall rules.
- Don't break Windows: never delete system files, remove servicing packages/components/AppX system apps, or disable services that Windows Update, Defender, search, networking, printing, audio, WebView2 or app installs depend on. Known side effects go behind an opt-in option with a plain-language warning.
- No copied code. KutayOS is written from scratch. AtlasOS, ReviOS, WinUtil, tiny11 and similar projects may be read only to learn which settings exist; every setting is re-derived from Microsoft docs (or another primary source) and implemented in our own code. License is GPL-3.0-or-later (`LICENSE`).

## Every tweak
- Lives in `src/playbook/Configuration/tweaks/<category>/<id>.yml` with `title` and `description`.
- Has a source/justification link in a comment above the action.
- Declares an evidence level in a comment: `measured` | `documented` | `community`. Performance tweaks need `measured` (VM before/after: boot time, idle CPU/RAM, process count, disk use) before they are enabled by default.
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

## ECC surface
- Only the DAILY set in `.claude/agents`, `.claude/skills` and `.claude/commands` is installed; the ECC plugin is off for this repo. Index and LIBRARY paths: `.claude/skills/skill-library/SKILL.md`.
- Agents are project-local: `subagent_type: "planner"`, not `"ecc:planner"`. This overrides the names in `../ecc/common/agents.md`.
- Work goes through the `orch-*` skills (two gates: plan approval, commit approval). Subagents only when the task needs one, not by default.
