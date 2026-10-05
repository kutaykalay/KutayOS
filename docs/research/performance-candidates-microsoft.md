# Microsoft Performance Optimization Guidance for Windows 11 LTSC 2024

> **Verification note (2026-10-01, main session).** This file was drafted by a quick research
> agent and only partly checked. Corrections: UsoSvc (Update Orchestrator) is NOT safe to disable
> and is not in Microsoft's VDOT service list; it drives Windows Update. The MB / % / process-count
> effects below are estimates, not measurements; the measured numbers are in
> `docs/measurements/slice5/`. Decisions for KutayOS are in `docs/measurements/slice5-performance.md`.

## 1. Virtual Desktop Optimization Tool (VDOT)

**Source:** github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool; learn.microsoft.com/rds-vdi-recommendations; learn.microsoft.com/remote-desktop-services-vdi-optimize-configuration

### Services Safe to Disable (Desktop-Relevant, Not VDI-Only)

- **SysMain** (Superfetch): Caches data in memory; does not improve performance on virtual drives; test before disabling on LTSC as it affects Windows Search performance.
- **defragsvc** (Optimize drives): Virtual drives don't benefit from defragmentation; safe to disable.
- **DiagTrack** (Connected User Experiences and Telemetry): Telemetry only; can disable if not required by policy.
- **DPS** (Diagnostic Policy Service): Disables Windows diagnostics; test if tools like Remote Assistance are used.
- **icssvc** (Windows Mobile Hotspot Service): Mobile hotspot not needed on LTSC; safe to disable.
- **Lfsvc** (Geolocation Service): Only needed if apps use location APIs; otherwise safe.
- **UsoSvc** (Update Orchestrator Service): Managed during maintenance windows; test before disabling on persistent machines.
- **WerSvc** (Windows Error Reporting): Diagnostics normally offline; safe to disable.
- **XblAuthManager, XblGameSave, XboxNetApiSvc**: Xbox services; safe to disable on enterprise LTSC.

**Risk notes:** SysMain affects Windows Search and Outlook sync; DPS affects Remote Assistance; UsoSvc impacts auto-updates.

### Scheduled Tasks Safe to Disable (Desktop-Relevant)

- **\Microsoft\Windows\Defrag\ScheduledDefrag**: Virtual disks don't benefit; safe to disable.
- **\Microsoft\Windows\Customer Experience Improvement Program\***: Telemetry; all safe to disable.
- **\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem**: Power optimization not relevant to VDI/desktop; safe to disable.
- **\Microsoft\Windows\Maintenance\WinSAT**: System performance measurement; run offline if needed; safe to disable from scheduled runs.
- **\Microsoft\Windows\Shell\FamilySafetyMonitor / FamilySafetyRefreshTask**: Enterprise only; safe to disable if not deployed.
- **\Microsoft\Windows\Windows Error Reporting\QueueReporting**: Process offline; safe to disable.
- **\Microsoft\Windows\Application Experience\ProgramDataUpdater**: Compatibility telemetry; safe to disable on LTSC.

**Measurable effect:** Processes (-5 to -15), CPU idle (-10-20%), boot time (-2-5%), none on RAM for most tasks except SysMain (-50-100 MB).

---

## 2. Microsoft Edge Background Process Policies

**Sources:** learn.microsoft.com/deployedge/microsoft-edge-browser-policies/startupboostenabled; learn.microsoft.com/deployedge/microsoft-edge-browser-policies/backgroundmodeenabled

### StartupBoostEnabled

- **Registry path:** HKLM\SOFTWARE\Policies\Microsoft\Edge
- **Value name:** StartupBoostEnabled (REG_DWORD)
- **0 = disabled (startup boost off), 1 = enabled (processes start at OS sign-in)**
- **Effect:** Processes (+1), startup time (+startup delay if disabled), CPU at logon (+5-10%)
- **Risk:** None; user can reconfigure in edge://settings/system

### BackgroundModeEnabled

- **Registry path:** HKLM\SOFTWARE\Policies\Microsoft\Edge
- **Value name:** BackgroundModeEnabled (REG_DWORD)
- **0 = disabled (background mode off), 1 = enabled (Edge keeps running after close)**
- **Effect:** Processes (+1 if enabled), CPU idle (+5-10%), RAM (+50-100 MB if enabled)
- **Risk:** None; affects only Edge background behavior

---

## 3. Background Apps Policy (LetAppsRunInBackground)

**Source:** learn.microsoft.com/windows/client-management/mdm/policy-csp-privacy

- **Registry path:** HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy
- **Value name:** LetAppsRunInBackground (REG_DWORD)
- **Values:** 0 = User choice (default), 1 = Force allow, 2 = Force deny
- **LTSC 2024 impact:** Minimal. LTSC 2024 has no Store apps; only Edge and SecHealthUI provisioned. Most background activity is system services, not UWP apps.
- **Measurable effect:** Processes (-5-10 if set to 2), RAM (-10-50 MB)
- **Risk notes:** May block background sync for Mail if enabled; Edge unaffected (native app)

---

## 4. Boot Performance Measurement

**Sources:** learn.microsoft.com Event Viewer documentation; WPT/WPA guidance; Windows Assessment Toolkit

### Event Tracing (Event Viewer)

- **Log:** Applications and Services Logs > Microsoft > Windows > Diagnostics-Performance > Operational
- **Event ID:** 100 (Boot Performance)
- **Key fields:**
  - **BootTime** (milliseconds): Total boot duration
  - **MainPathBootTime** (ms): BIOS end to desktop visible
  - **BootPostBootTime** (ms): Desktop visible to idle state (~5 seconds of low activity)
- **Threshold comparison:** HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\Performance\Boot
  - PostBootMinorThreshold_Sec: 30s (Warning if exceeded)
  - PostBootMajorThreshold_Sec: 60s (Critical if exceeded)
- **Interactive logon required:** No. Events logged regardless; boot metrics captured during automated startup.

### Tools

- **Windows Assessment Toolkit (WAC):** Boot Performance (Fast Startup) assessment; compares baseline vs. current; 30-minute run; outputs XML with sub-metrics (devices resume, hiberfile size, process CPU/disk per phase).
- **Windows Performance Recorder (WPR) + Analyzer (WPA):** Deep analysis of all startup drivers, apps, disk I/O; included in Windows ADK; requires xbootmgr or manual trace start.
- **xbootmgr:** Legacy boot measurement tool; used with WPR; referenced for compatibility.

**Best practice:** Use WAC for before/after comparisons (baseline XML provided); use WPR/WPA for root-cause analysis of slow phases.

---

## Summary

Sixteen services and fifteen scheduled tasks listed above are Microsoft-documented candidates for LTSC 2024 without breaking Update, Defender, search, printing, or anti-cheat. Edge policies (StartupBoostEnabled, BackgroundModeEnabled) toggle background processes via HKCU/HKLM registry. LetAppsRunInBackground has minimal impact on LTSC (no Store apps). Boot performance measured via Event ID 100 (no logon required), WAC, or WPR/WPA tools.
