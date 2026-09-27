# KutayOS

AME Wizard Playbook (`.apbx`) for Windows 11 IoT Enterprise LTSC 2024 (build 26100): a fast, clean, minimal and compact Windows for general users that does not break updates, security or apps. v2 adds a C# WPF (.NET Framework 4.8) Toolbox for post-install toggles and rollback.

License: GPL-3.0-or-later (`LICENSE`).

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
- ECC update: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/sync-ecc.ps1 [-Check]` (list in `.claude/ecc-sync.txt`)

## Test VM
VMware Workstation VM `KutayOS-Test` (created by `tools/new-testvm.ps1`: EFI, Secure Boot, 6 GB, 4 vCPU, 64 GB NVMe; vTPM 2.0 added by hand in VM Settings because it needs VM encryption), Windows 11 IoT Enterprise LTSC 2024, snapshot `clean` taken before every playbook run. VirtualBox is no longer used.
