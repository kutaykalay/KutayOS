# KutayOS

AME Wizard Playbook (`.apbx`) for Windows 11 IoT Enterprise LTSC 2024 (build 26100): performance, privacy, low-latency gaming, developer setup. v2 adds a C# WPF (.NET Framework 4.8) Toolbox for post-install toggles and rollback.

Project rules: `.claude/rules/kutayos/project.md` (overrides the generic ECC rules in `.claude/rules/ecc/`).

## Layout
- `src/playbook/playbook.conf` - metadata, supported builds, FeaturePages (user options)
- `src/playbook/Configuration/custom.yml` - root task; `tweaks/<category>/*.yml` - individual tweaks
- `src/playbook/Executables/KutayModules` - shared PowerShell helpers, copied to `%windir%\KutayOS`
- `src/playbook/Executables/KutayDesktop` - user-facing apply/revert scripts
- `src/toolbox` - v2 C# Toolbox
- `tools/build.ps1` - validates and packages `dist/KutayOS-<version>.apbx` (needs 7-Zip)

## Commands
- Build: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/build.ps1`
- Tests: `Invoke-Pester tests` (Pester 5)

## Test VM
VirtualBox, Windows 11 IoT Enterprise LTSC 2024, snapshot `clean` taken before every playbook run.
