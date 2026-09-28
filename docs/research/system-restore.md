# System Restore Research: Windows 11 IoT Enterprise LTSC 2024

## Q1: Default State on Fresh Install (Build 26100/24H2)

**Answer: Disabled by default on LTSC.**

System Restore is **OFF** by default on Windows 11 Enterprise LTSC 2024 fresh installs. Windows Home editions enable it by default; Enterprise/LTSC editions do not. [System Protection - Microsoft Support]

On LTSC 2024, an alternative option exists: Point-in-Time Restore (PTR) is available on Windows 11 version 24H2 or later. [Point-in-time restore for Windows 11]

## Q2: Enable System Restore & Disk Space Allocation

**Enable via PowerShell 5.1:**
```powershell
Enable-ComputerRestore -Drive "C:\"
```

**Disk Space Allocation (Optional):**
Manual allocation is NOT required; System Restore will auto-allocate if needed. However, you can pre-allocate shadow copy storage via `vssadmin`:

```powershell
vssadmin resize shadowstorage /For=C: /On=C: /MaxSize=20%
```

**Constraints:**
- System Restore requires minimum 300 MB allocated to function.
- Recommended minimum is 10% of volume size per Microsoft.
- Drive must be 1 GB or larger.

[vssadmin resize shadowstorage - Microsoft Learn]

## Q3: Checkpoint-Computer Specifics

**Cmdlet Signature:**
```powershell
Checkpoint-Computer -Description <string> [-RestorePointType <string>]
```

**Required Parameters:**
- `-Description`: User-facing label for the restore point (required).

**Optional Parameters:**
- `-RestorePointType`: One of five types (default: `APPLICATION_INSTALL`).

**RestorePointType Values:**
- `APPLICATION_INSTALL` (0) - default
- `APPLICATION_UNINSTALL` (1)
- `DEVICE_DRIVER_INSTALL` (10)
- `MODIFY_SETTINGS` (12)
- `CANCELLED_OPERATION` (13)

[Restore Point Description Text - Microsoft Learn]

**24-Hour Frequency Limit:**
`Checkpoint-Computer` cannot create more than one restore point per 24 hours (since Windows 8). Attempts within 24 hours return: "A new system restore point cannot be created because one has already been created within the past 24 hours. Please try again later."

**Registry Override (Windows 8+):**
```
Path: HKLM\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore
Key: SystemRestorePointCreationFrequency (DWORD)
Values:
  0 = disable frequency check (create immediately)
  N = skip if restore point created in last N minutes (default: 1440 = 24 hours)
```

[CreateRestorePoint method - Win32 apps - Microsoft Learn]

## Q4: Known Silent Failures & Limitations

**PowerShell Version:**
- **Checkpoint-Computer is only available in Windows PowerShell 5.1**, NOT PowerShell 7.x (Core). The cmdlet is part of the Microsoft.PowerShell.Management module in 5.1.
- PowerShell 7 cannot invoke this cmdlet; scripts must use Windows PowerShell 5.1 explicitly.

[Migrating from Windows PowerShell 5.1 to PowerShell 7 - Microsoft Learn]

**SYSTEM Context Risks:**
- Running as SYSTEM/TrustedInstaller may impede VSS writer access and cause silent failures.
- UAC elevation (Run as Administrator) recommended; full SYSTEM context untested with Checkpoint-Computer.

**VSS Service Dependency:**
- If Volume Shadow Copy Service (VSS) is stopped or unhealthy, Checkpoint-Computer may fail silently or hang.
- No built-in error propagation if VSS is unavailable.

**Return Behavior:**
- `Checkpoint-Computer` generates NO output on success (returns None).
- On frequency-limit violation, PowerShell issues a **terminating error** (not a warning), which halts the script unless caught with `-ErrorAction`.
- If System Restore is disabled on the target drive, the cmdlet fails silently with an error.

## Q5: Verification Methods

**Method 1: PowerShell Cmdlet (Recommended)**
```powershell
# List all restore points
Get-ComputerRestorePoint

# Verify most recent restore point
Get-ComputerRestorePoint | Select-Object -Last 1 | Select-Object Description, CreationTime, SequenceNumber

# Check last restore operation status
Get-ComputerRestorePoint -LastStatus
```

**Method 2: WMI (SystemRestore class)**
```powershell
Get-WmiObject -Namespace root/default -Class SystemRestore | `
  Sort-Object SequenceNumber -Descending | `
  Select-Object -First 1
```

Output columns: `Description`, `CreationTime`, `SequenceNumber`, `RestorePointType`, `EventType`.

## Recommended Implementation Sequence

1. **Check if enabled:** `Get-ComputerRestorePoint` succeeds only if System Restore is active.
2. **Pre-check frequency:** Before `Checkpoint-Computer`, verify the registry value `SystemRestorePointCreationFrequency` if offline mode is desired.
3. **Enable if needed:** `Enable-ComputerRestore -Drive "C:\"` (idempotent; safe to run twice).
4. **Optional: pre-allocate space:** `vssadmin resize shadowstorage /For=C: /On=C: /MaxSize=20%` if disk space is tight (e.g., <20% free).
5. **Create checkpoint:** Catch errors explicitly with `-ErrorAction Stop` to detect failures.
6. **Verify:** Use `Get-ComputerRestorePoint` to confirm the restore point was created with the expected `SequenceNumber` and `CreationTime`.

## Review note (main session, 2026-09-24)

- The "terminating error" claim in Q4 is NOT confirmed. The Microsoft Learn page only says PowerShell
  "generates the following error" and does not say it is terminating. In practice the 5.1 cmdlet is
  widely reported to emit a *warning* (WriteWarning) and return normally, which is a silent skip.
  Verify in the VM.
- Design consequence: do not rely on the error or the warning. Set `SystemRestorePointCreationFrequency`
  to 0 first (snapshot the prior value), compare the newest `SequenceNumber` from
  `Get-ComputerRestorePoint` before and after, and fail with a non-zero exit if no new point appeared.

## VM results (LTSC 2024 26100.9550, 2026-09-29)

Slice 1 smoke test in the VMware test VM, scripts run as the elevated local admin:

- A fresh install has no restore points and no `SystemRestorePointCreationFrequency` value.
- `Enable-ComputerRestore -Drive C:\` followed by `Checkpoint-Computer` worked without resizing
  shadow storage. The first restore point took about 85 s, the second about 45 s.
- With the frequency value set to 0, a second restore point minutes after the first was created
  (sequence 1 -> 2). Removing the value afterwards left the system as it was.
- The Win32 docs confirm the silent skip: without the override, CreateRestorePoint "returns S_OK"
  while skipping. So the sequence-number check is required, not optional.

Still untested: running as SYSTEM/TrustedInstaller (KutayOS uses `currentUserElevated`).

## Unverified / Unclear

- Exact behavior of `Checkpoint-Computer` when running as SYSTEM/TrustedInstaller (untested on LTSC 2024; not documented).
- Whether VSS must be running before or can be started by `Enable-ComputerRestore` (likely requires running VSS, but undocumented).
- Whether running the script in a non-interactive session (e.g., scheduled task as SYSTEM) affects error propagation (suspected risk).

## Sources

- [Checkpoint-Computer (Microsoft.PowerShell.Management) - PowerShell](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/checkpoint-computer?view=powershell-5.1)
- [Enable-ComputerRestore (Microsoft.PowerShell.Management) - PowerShell](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/enable-computerrestore?view=powershell-5.1)
- [Get-ComputerRestorePoint (Microsoft.PowerShell.Management) - PowerShell](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-computerrestorepoint?view=powershell-5.1)
- [CreateRestorePoint method of the SystemRestore class - Win32 apps](https://learn.microsoft.com/en-us/windows/win32/sr/createrestorepoint-systemrestore)
- [SystemRestore class - Win32 apps](https://learn.microsoft.com/en-us/windows/win32/sr/systemrestore)
- [vssadmin resize shadowstorage](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/vssadmin-resize-shadowstorage)
- [Recovery options in Windows - Microsoft Support](https://support.microsoft.com/en-us/windows/experience/backup-recovery/recovery-options-in-windows)
- [System Protection - Microsoft Support](https://support.microsoft.com/en-us/windows/system-protection-e9126e6e-fa64-4f5f-874d-9db90e57645a)
- [Point-in-time restore for Windows 11 is now generally available](https://techcommunity.microsoft.com/blog/windows-itpro-blog/point-in-time-restore-for-windows-11-is-now-generally-available/4508101)
- [Migrating from Windows PowerShell 5.1 to PowerShell 7 - PowerShell](https://learn.microsoft.com/en-us/powershell/scripting/whats-new/migrating-from-windows-powershell-51-to-powershell-7?view=powershell-7.5)
