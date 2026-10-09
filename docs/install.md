# Installing KutayOS

KutayOS runs on a fresh **Windows 11 IoT Enterprise LTSC 2024** (build 26100). It does not install
Windows for you: you install LTSC first, then run the KutayOS playbook in AME Wizard.

> [!WARNING]
> Version 0.9.0 is a preview. It passed a full run in a virtual machine, but it has not yet been
> checked on real hardware (see [Known limits](#known-limits)). Try it on a PC you can reinstall.

## 1. Make the install USB

You need a Windows 11 IoT Enterprise LTSC 2024 ISO you are licensed to use, an 8 GB or larger USB
stick and [Rufus](https://rufus.ie/).

Pick the ISO and the USB stick in Rufus and press **Start**. Rufus then offers a few Windows setup
options:

| Rufus option | Choose | Why |
| --- | --- | --- |
| Remove requirement for 4GB+ RAM, Secure Boot and TPM 2.0 | **Leave unticked** | Anti-cheat (Vanguard, FACEIT) and Windows security need Secure Boot and TPM. |
| Remove requirement for an online Microsoft account | Tick | Lets you set up a local account. |
| Create a local account using username | Tick, any name | The account KutayOS was tested with is a local admin account. |
| Set regional options to the same values as this user's | Tick | Skips the region and keyboard questions. |
| Disable data collection (skip privacy questions) | Your choice | KutayOS turns the same settings off by policy anyway. |
| Disable BitLocker automatic device encryption | Leave unticked | KutayOS does not change disk encryption. |

The option names are those of Rufus 4.x; newer versions may word them differently.

## 2. Install and update Windows

1. Install Windows from the USB stick and sign in with the local account.
2. Open **Settings > Windows Update** and install every update, restarting until none are left.
   AME Wizard refuses to start while updates are pending.
3. Plug a laptop into power. AME Wizard requires it.

## 3. Run KutayOS

1. Download **AME Wizard** from [ameliorated.io](https://ameliorated.io/). There is no published
   KutayOS release yet: build `dist/KutayOS-<version>.apbx` yourself (see
   [Build from source](../README.md#build-from-source)).
2. Start AME Wizard and drop the `.apbx` file on it. In the test run on an updated LTSC 2024 it
   asked for nothing else: Defender stays on and no extra prerequisite screen appeared.
3. Pick the options you want. Each one says what it changes; the ones with a trade-off are off by
   default. The one exception is **Install winget and Windows Terminal**, which is ticked: LTSC has
   no Microsoft Store, so it has neither. It downloads about 360 MB from Microsoft's GitHub, so the
   PC needs internet; untick it to skip. Everything is checked against a pinned SHA256 and the
   Microsoft signature before it is installed.
4. Wait. A run takes about 5 minutes on a fast PC, most of it cleaning up old update files (add
   about 5 minutes for the winget and Terminal download). KutayOS creates a System Restore point
   first and stops if it can't, and it stops before changing anything else if a download or
   signature check fails: fix the connection and run it again.
5. AME Wizard restarts the PC when it is done.

## 4. Check that Windows still works

After the restart, open **Windows PowerShell as administrator** and run:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:windir\KutayOS\KutayDesktop\Test-KutayHealth.ps1"
```

It changes nothing. It prints one line per check: Windows Update (needs internet), Microsoft
Defender, Windows Search and the WebView2 Runtime. `PASS` is fine, `WARN` says what to look at,
`FAIL` means something is wrong. The result is also saved in `C:\Windows\KutayOS\Logs\health.log`.

## Undo

Every change except the cleanup of old update files can be undone. In **Windows PowerShell as
administrator**:

```powershell
# Everything
powershell -ExecutionPolicy Bypass -File "$env:windir\KutayOS\KutayDesktop\Revert-KutayOS.ps1" -All
# One tweak, by the name of its file in src/playbook/Configuration/tweaks
powershell -ExecutionPolicy Bypass -File "$env:windir\KutayOS\KutayDesktop\Revert-KutayOS.ps1" -Id dark-mode
```

Restart afterwards. Per-user settings come back for every account that existed when KutayOS ran.
The System Restore point from before the run is a second way back.

Reverting removes Windows Terminal and its update task. **winget stays**: Windows treats App
Installer as part of the OS and refuses to uninstall it. It does nothing until you use it.
Terminal updates itself through a scheduled task (`\KutayOS\Update Windows Terminal`) that runs
`winget upgrade` as the signed-in user at logon and once a day; its log is
`%LOCALAPPDATA%\KutayOS\terminal-update.log`.

Logs are in `C:\Windows\KutayOS\Logs` (`install.log`, `revert.log`, `health.log`).

## Known limits

- **Not yet checked on real hardware:** a game with anti-cheat (Vanguard, FACEIT, EAC, BattlEye) and
  the "Turn off hibernation" option. KutayOS does not touch anything those depend on, but 1.0.0
  waits for a real test.
- **Only build 26100** (LTSC 2024) is supported. AME Wizard refuses other builds.
- **Accounts created after the run** get KutayOS's per-user settings from the default profile,
  except the classic right-click menu, which only applies to accounts that existed at the time.
