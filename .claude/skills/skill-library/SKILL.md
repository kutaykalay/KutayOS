---
name: skill-library
description: Index of the KutayOS ECC surface. Lists the DAILY agents/skills installed in this repo and the LIBRARY ones kept outside it, with where to read them. Use when a task needs an ECC agent, skill or command that is not installed here (C# Toolbox work, docs sync, deeper research, learning/instincts).
---

# KutayOS ECC surface (DAILY vs LIBRARY)

Selected with ECC's `agent-sort` method from the upstream ECC repo.
Files are copied verbatim by `tools/sync-ecc.ps1`; ECC's
installer resolves `--skills` to whole modules (119+ files), so it was not used.

The ECC plugin is disabled (`"ecc@ecc": false` in `~/.claude/settings.json`),
so only the DAILY set below loads. ECC hooks do
not run here; the repo's own hooks (`host-guard.js`, `ps-lint.ps1`) do.

## DAILY (installed in `.claude/`)

| Surface | Evidence in this repo |
|---|---|
| agent `planner` | `docs/PRD.md` slice plan, Gate 1 |
| agent `tdd-guide` | Pester 5 tests in `tests/`, TDD rule |
| agent `code-reviewer` | review after every change |
| agent `security-reviewer` | playbook runs as TrustedInstaller and edits security settings |
| agent `silent-failure-hunter` | `$ErrorActionPreference = 'Stop'` + exit-code rule for AME `handleExitCodes` |
| agent `code-explorer` | intake step of `orch-*` for changes to existing tweaks |
| skills `orch-pipeline`, `orch-add-feature`, `orch-fix-defect`, `orch-change-feature`, `orch-refine-code` | the gated Research -> Plan -> TDD -> Review -> Commit workflow chosen at kickoff |
| skills `tdd-workflow`, `verification-loop` | Pester + VM smoke test before "done" |
| skill `search-first` | reuse AtlasOS / ReviOS / WinUtil code with attribution |
| skill `strategic-compact` | manual `/compact` at phase boundaries (no hook) |
| commands `save-session`, `resume-session` | session files in `~/.claude/session-data/` |

Agent names are project-local: use `subagent_type: "planner"`, not `"ecc:planner"`.
Project overrides in `.claude/rules/kutayos/project.md` win over ECC text
(for example: 80% coverage only for pure helpers, web security rules do not apply).

## LIBRARY (not loaded; read on demand)

Read the file from `~/.claude/plugins/marketplaces/ecc/<path>` and follow it,
or copy it into `.claude/` when it becomes daily.

| When | Path |
|---|---|
| v2 C# Toolbox starts (`src/toolbox` has `.cs` files) | `agents/csharp-reviewer.md`, `skills/dotnet-patterns/`, `skills/csharp-testing/`, `skills/windows-desktop-e2e/` |
| architecture call (Toolbox design, state format) | `agents/architect.md` |
| build script breaks | `agents/build-error-resolver.md`, `commands/build-fix.md` |
| docs drift | `agents/doc-updater.md`, `commands/update-docs.md` |
| broad web research | `skills/deep-research/` |
| capture a reusable lesson | `commands/learn.md`, `skills/continuous-learning-v2/` |
| dead code cleanup | `agents/refactor-cleaner.md` |

Not used here (off-stack): language reviewers other than C#, web/frontend,
database, ML, business, marketing, prediction-market skills.

## Updating

The DAILY list lives in `.claude/ecc-sync.txt`, the pinned ECC commit in
`.claude/ecc-sync.lock`. It does not depend on the ECC plugin being installed.

- Check: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/sync-ecc.ps1 -Check`
- Update: same command without `-Check`, then review `git diff .claude` and
  commit as `chore: sync ECC to <short hash>`.
- To add or drop a DAILY item, edit `ecc-sync.txt` and this file, then sync.
- Sync overwrites the listed files. Put KutayOS-specific changes in
  `.claude/rules/kutayos/`, never in the vendored files.
