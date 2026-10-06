# AME Wizard Official Documentation Research

> Checked in the main session on 2026-10-06: the `!cmd` table against the AME docs page and the CLI
> syntax against the trusted-uninstaller-cli README. Everything else is the research agent's reading;
> the full VM run (`docs/measurements/slice6-fullrun.md`) used the AME Wizard GUI, not the CLI.

Date: 2026-10-06  
Research scope: Official Amelabs documentation (docs.amelabs.net) and Ameliorated-LLC GitHub repositories  
Time-boxed research: ~10 minutes

## Findings

### 1. `!cmd` Action: Full Property List and Defaults

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `command` | string | Required | The command to execute (equivalent to `cmd /c "<command>"`) |
| `exeDir` | bool | false | Sets the playbook executables folder as the working directory |
| `runas` | enum | trustedInstaller | Execution context: `currentUser`, `currentUserElevated`, `system`, or `trustedInstaller` |
| `timeout` | integer | None | Maximum execution duration (seconds); terminates process on timeout and reports error |
| `wait` | bool | false | Whether to wait for the cmd instance to exit |
| `handleExitCodes` | dictionary | None | Controls how exit codes are processed using handlers (`log`, `error`, `halt`, `retry`) and conditional expressions (e.g., `!0` for non-zero) |

**Source:** https://docs.amelabs.net/developers/actions/Cmd.html

### 2. Option Negation with `!` Prefix

**Status:** Not documented in accessible official sources.

Searched for `option:` and `options:` properties in FeaturePages documentation and global properties documentation, but those pages returned 404 errors or are not accessible via docs.amelabs.net. The `!cmd` and `!powerShell` action documentation shows conditional expressions using `!` (e.g., `!0` for "not zero") in `handleExitCodes`, but negation of conditions like `!option:optionName` is **not documented**.

**Source:** https://docs.amelabs.net/developers/actions/Cmd.html and https://docs.amelabs.net/developers/actions/PowerShell.html (FeaturePages doc at `/developers/` returned 403)

### 3. Non-Interactive / CLI Execution

**Capability:** Yes, AME Wizard can run from command line.

**CLI Syntax:**
```
TrustedUninstaller.CLI.exe "<Extracted Playbook Folder>"
TrustedUninstaller.CLI.exe "<Playbook Name>" option1 option2
```

**Example:**
```
TrustedUninstaller.CLI.exe "AME 11 v0.7" browser-firefox enhanced-security
```

**Unattended mode and logging location:** Not documented in official sources. The trusted-uninstaller-cli README indicates that normal users should use the GUI, and CLI documentation beyond basic syntax is not provided.

**Source:** https://github.com/Ameliorated-LLC/trusted-uninstaller-cli (releases and project description)

### 4. Post-Run Behavior (Progress Text, Reboot, Final Message)

**Status:** Not documented in accessible official sources.

Searched for `playbook.conf` properties related to post-run steps, `<ProgressText>`, reboot prompts, or final messages, but the playbook configuration documentation pages returned 404 or are not accessible (e.g., `/developers/playbook-conf.html` returned 404).

**Source:** Attempted https://docs.amelabs.net/developers/playbook-conf.html (404)

### 5. Executables Folder: Location and Retention

**From playbook structure:** Playbooks contain an `Executables/` folder with scripts and tools referenced by actions.

**Copied to target:** Not documented. The `exeDir` property on actions indicates that the playbook executables folder can be set as the working directory, but the target system path where executables are copied is **not documented** in official sources.

**Retained after run:** Not documented.

**Source:** General playbook structure information from https://github.com/Ameliorated-LLC (repository descriptions) and https://docs.amelabs.net/ (main page).

## Summary

- ✅ **!cmd action properties:** Fully documented with all defaults
- ❌ **Option negation:** Not documented (pages inaccessible or don't exist)
- ⚠ **CLI execution:** Supported but unattended mode / logging not documented
- ❌ **Post-run behavior:** Not documented (pages don't exist or inaccessible)
- ❌ **Executables location:** Not documented

## Sources

- [AME Wizard - !cmd action](https://docs.amelabs.net/developers/actions/Cmd.html)
- [AME Wizard - !powerShell action](https://docs.amelabs.net/developers/actions/PowerShell.html)
- [AME Wizard - !task action](https://docs.amelabs.net/developers/actions/Task.html)
- [Ameliorated-LLC/trusted-uninstaller-cli GitHub](https://github.com/Ameliorated-LLC/trusted-uninstaller-cli)
- [Ameliorated-LLC Organization GitHub](https://github.com/Ameliorated-LLC)
