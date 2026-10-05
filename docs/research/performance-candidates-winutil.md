# Performance Tweaks from WinUtil - Candidates for KutayOS Slice 5

> **Verification note (2026-10-01, main session).** This file was drafted by a quick research
> agent and only partly checked. Corrections: UsoSvc (Update Orchestrator) is NOT safe to disable
> and is not in Microsoft's VDOT service list; it drives Windows Update. The MB / % / process-count
> effects below are estimates, not measurements; the measured numbers are in
> `docs/measurements/slice5/`. Decisions for KutayOS are in `docs/measurements/slice5-performance.md`.

Research date: 2026-10-01  
Source: [WinUtil config/tweaks.json](https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json)  
Approach: Extract performance-related tweaks, verify against Microsoft primary sources, identify red-lines, measure impact.

## Performance Candidates Evaluation

| WinUtil ID | Tweak Name | Registry/Service Setting | Microsoft Docs | Impact | Status |
|---|---|---|---|---|---|
| WPFTweaksDisplay | Visual Effects - Best Performance | MenuShowDelay, MinAnimate, DragFullWindows, ListviewShadow, TaskbarAnimations, VisualFXSetting | [Settings reference - Visual Effects](https://learn.microsoft.com/en-us/windows/win32/controls/visual-effects) | UI feel only | OK |
| WPFTweaksDeliveryOptimization | Delivery Optimization - Disable | DODownloadMode (0) | [DO Policy CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-deliveryoptimization) | RAM / Network | OK |
| WPFTweaksDisableBGapps | Background Apps - Disable | BackgroundAccessApplications.GlobalUserDisabled | [Background apps CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-applicationmanagement#backgroundappsettings) | RAM / CPU | OK |
| WPFAddUltPerf | Ultimate Performance Profile - Enable | powercfg power scheme | [Power settings ADMX](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/powercfg) | CPU / Power | OK |
| WPFToggleGameMode | Game Mode - Enable | AllowAutoGameMode, AutoGameModeEnabled (GameBar) | [Game Mode - Settings support](https://support.microsoft.com/en-us/windows/settings-for-gaming-6f19e47a-3e26-9bb4-83f1-f465b5e05301) | GPU / Processes | OK |
| WPFMultiplaneOverlay | Multiplane Overlay - Disable | DWM.OverlayTestMode, GraphicsDrivers.DisableOverlays | [Multiplane Overlay - WDDM](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/multiplane-overlay-support) | GPU / Rendering | WARN |
| WPFToggleS3Sleep | S3 Sleep (vs Modern Standby) | PlatformAoAcOverride | [Modern Standby / S3 Sleep CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-power) | Wake/Sleep modes | WARN |
| WPFToggleStandbyFix | S0 Sleep Network Connectivity | PowerSettings.f15576e8... (WLAN low power) | [Power settings - Connected Standby](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-power) | Network / CPU idle | WARN |
| WPFTweaksEdgeDebloat | Edge - Disable Telemetry / Startup | Edge Policy keys (DiagnosticData, StartupBoostEnabled, etc.) | [Edge policies - Manage startup, home, search](https://learn.microsoft.com/en-us/DeployEdge/microsoft-edge-policies) | Startup time / RAM | OK |
| WPFTweaksServices | Services - Set to Manual | CscService (Disabled), DiagTrack (Disabled), MapsBroker, StorSvc (Manual) | [Services list - Offline Files, Diagnostic](https://learn.microsoft.com/en-us/windows/application-management/list-of-services) | Processes / RAM | DROP |

## Red-Line Violations

**WPFTweaksServices - DROP**: Disables CscService and DiagTrack, sets StorSvc to Manual.  
- **CscService** (Offline Files): Low risk, safe to disable if no offline file sync needed  
- **DiagTrack** (Diagnostic Tracking): Safe to disable (telemetry only)  
- **StorSvc** (Storage Service): Used for app updates and device management; setting to manual can break Microsoft Store app installs

---

## Top Picks (No Red Lines)

1. **Visual Effects - Best Performance** (WPFTweaksDisplay)  
   - Disables animations, menu delays, shadows, Aero Peek  
   - Impact: UI responsiveness feel (no measurable CPU/RAM on modern hardware)

2. **Delivery Optimization - Disable** (WPFTweaksDeliveryOptimization)  
   - Blocks DODownloadMode to prevent peer-to-peer update sharing  
   - Impact: ~20-50 MB RAM freed (minor on systems with >8GB)

3. **Background Apps - Disable** (WPFTweaksDisableBGapps)  
   - Disables UWP background execution globally  
   - Impact: ~50-150 MB RAM saved depending on Store app count

4. **Ultimate Performance Profile** (WPFAddUltPerf)  
   - Enables high-performance power plan  
   - Impact: CPU stays high clock (trade: increased power draw, better for desktops)

5. **Game Mode** (WPFToggleGameMode)  
   - Enables auto-detection and prioritization for games  
   - Impact: Process priority shifts; measurable only in gaming workloads

6. **Edge Debloat** (WPFTweaksEdgeDebloat)  
   - Disables telemetry, Rewards, shopping, asset delivery in Edge policies  
   - Impact: Startup time (medium), RAM (medium with many tabs)

---

## Investigation Notes

- **S3 Sleep / S0 Standby** (WPFToggleS3Sleep, WPFToggleStandbyFix): Affects sleep/wake behavior; useful for laptops, may not apply to general-user desktops; marked WARN pending verification
- **Multiplane Overlay**: Graphics driver setting; toggle disabled for compatibility; low measured impact on idle baseline but measurable in graphics workloads
- **Hibernation already covered** in earlier slices (KutayOS v1)
- Services tweak requires careful review of StorSvc dependency chain before enabling

## Measurement Strategy

Baseline VM (idle after logon, snapshot clean):  
- Boot time (seconds, <5 min warm boot)  
- Idle CPU (% avg over 30s)  
- Idle RAM (MB committed)  
- Process count  
- Disk I/O (MB/s)

Apply each tweak individually, re-snapshot, measure, then reset to track delta.
