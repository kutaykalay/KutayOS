# AME Wizard Playbook Actions - Quick Reference

Verified against the official docs (https://docs.amelabs.net/developers/actions.html and per-action pages)
on 2026-09-24. A first draft by a Haiku research agent had several errors; this version replaces it.

## Pitfalls (read first)

- `!powerShell` defaults to `wait: false` (fire and forget). Always set `wait: true`, otherwise
  `handleExitCodes` and ordering are meaningless. `!run` defaults to `wait: true`.
- `!service` defaults to `operation: delete`. Always set `operation` explicitly.
- Script actions default to `runas: trustedInstaller`. Use `currentUserElevated` or `currentUser`
  only when a per-user context is required.
- `!registryValue` with `HKCU` applies to **all user hives** by default (`scope: allUsers`).
- There is no `runas` on `!registryValue` or `!service`.

## Global properties (all actions)

| Property | Type | Default | Notes |
|---|---|---|---|
| `option` | string | - | Runs only if the FeaturePages option is selected |
| `options` | string[] | - | Multiple options |
| `builds` | string[] | - | e.g. `['26100']`, `['>=26100']`, `['!>26200']`, `26100.1742` |
| `cpuArch` | string | - | e.g. `X64` |
| `errorAction` | enum | varies | `Ignore`, `Log`, `Notify`, `Halt` |
| `weight` | int | 2-5 | Progress bar weight |
| `status` | string | - | Status text shown to the user |
| `onUpgrade` | bool | false | Run during a playbook upgrade |
| `onUpgradeVersions` | string[] | - | Previous versions that trigger upgrade actions |
| `previousOption` | string | - | Option state matching during upgrades |
| `iso` | enum | false | `true` / `false` / `only` (ISO injection) |
| `oobe` | enum | null | OOBE execution |

## !registryValue

| Property | Required | Default | Notes |
|---|---|---|---|
| `path` | yes | - | Key path, e.g. `HKLM\SOFTWARE\...` |
| `value` | yes | - | Value name |
| `type` | yes (not for delete) | - | REG_SZ, REG_MULTI_SZ, REG_EXPAND_SZ, REG_DWORD, REG_QWORD, REG_BINARY, REG_NONE, REG_UNKNOWN |
| `data` | yes (not for delete) | - | |
| `operation` | no | `add` | `add`, `delete`, `set` |
| `scope` | no | `allUsers` | HKCU only: `allUsers`, `currentUser`, `activeUsers`, `defaultUsers` |

## !service

| Property | Required | Default | Notes |
|---|---|---|---|
| `name` | yes | - | Service name |
| `operation` | no | **`delete`** | `stop`, `continue`, `start`, `pause`, `delete`, `change` |
| `startup` | when `change` | - | 2 Automatic, 3 Manual, 4 Disabled |
| `device` | no | false | Target is a driver |
| `deleteStop` | no | true | Stop before delete |
| `deleteUsingRegistry` | no | false | Bypass service permissions |

## !run

| Property | Default | Notes |
|---|---|---|
| `exe` | required | Executable, optionally with path |
| `path` | - | Directory containing the exe |
| `args` | - | |
| `exeDir` | false | Working dir = playbook Executables folder |
| `baseDir` | false | Working dir = amelioration directory |
| `runas` | `trustedInstaller` | `currentUser`, `currentUserElevated`, `system`, `trustedInstaller` |
| `wait` | true | |
| `timeout` | - | Kill + error when exceeded |
| `showOutput` / `showError` | true | Forward stdout/stderr to log |
| `handleExitCodes` | - | Map of code -> `log`, `error`, `halt`, `retry`, `retryError`; conditions like `'!0': halt` |

## !powerShell

Same as `!run` for `exeDir`, `runas` (default `trustedInstaller`), `timeout`, `handleExitCodes`,
but `command` (required) instead of `exe`/`args`, and **`wait` defaults to false**.

## !cmd

Checked on https://docs.amelabs.net/developers/actions/Cmd.html on 2026-10-06:

| Property | Default | Notes |
|---|---|---|
| `command` | required | |
| `exeDir` | false | Working dir = playbook Executables folder |
| `runas` | `trustedInstaller` | `currentUser`, `currentUserElevated`, `system`, `trustedInstaller` |
| `timeout` | - | Kill + error when exceeded |
| `wait` | **false** | Like `!powerShell`: always set `wait: true` |
| `handleExitCodes` | - | Same handlers as `!run` |


## !task

`path` (required): relative path to a task YAML. The docs do not say relative to what. Atlas files
use paths relative to the `Configuration\` folder (checked in the previous session) - treat that as
the working assumption.

## Unverified

- Option negation (e.g. `option: '!name'`): not found in the docs (checked again 2026-10-06). Do
  not rely on it; use two options on a RadioPage instead. `tools/build.ps1` and
  `tests/Tweaks.Tests.ps1` reject any option that is not a FeaturePages option name.
- `!registryKey`: not checked in this pass.

## Sources

- https://docs.amelabs.net/developers/actions.html
- https://docs.amelabs.net/developers/actions/Run.html
- https://docs.amelabs.net/developers/actions/PowerShell.html
- https://docs.amelabs.net/developers/actions/RegistryValue.html
- https://docs.amelabs.net/developers/actions/Service.html
- https://docs.amelabs.net/developers/actions/Task.html
