# Privacy, advertising and suggestion policies (Slice 2)

Checked 2026-09-29 against Microsoft Learn (Policy CSP pages) and the ADMX files shipped in
`C:\Windows\PolicyDefinitions` on the test VM (LTSC 2024, 26100.9550). The ADMX `enabledValue` /
`disabledValue` is the primary source for the registry data, because several CSP pages don't state
which number turns a "Turn off ..." policy on.

## What LTSC 2024 ships (VM inventory, `tools/vm/guest-inventory.ps1`)

- No Microsoft Store, Widgets (Web Experience Pack), Copilot app, OneDrive or Xbox apps.
  Provisioned AppX: Edge and Windows Security only.
- Optional feature `Recall` is `DisabledWithPayloadRemoved`.
- On by default: advertising ID (`HKCU ...\AdvertisingInfo\Enabled=1`), tailored experiences,
  implicit inking/typing collection, CEIP and Application Experience tasks, DiagTrack (running).
- `ContentDeliveryManager` exists and has suggestion flags set, but with no Store it has little to
  install.

## Applied in Slice 2 (device scope, on by default, evidence `documented`)

| Tweak id | Registry (HKLM) | Data | Source |
| --- | --- | --- | --- |
| `disable-advertising-id` | `SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo\DisabledByGroupPolicy` | 1 | [Privacy CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-privacy#disableadvertisingid) |
| `disable-consumer-features` | `...\Windows\CloudContent\DisableWindowsConsumerFeatures` | 1 | [Experience CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#allowwindowsconsumerfeatures) |
| `disable-cloud-optimized-content` | `...\Windows\CloudContent\DisableCloudOptimizedContent` | 1 | [Experience CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#disablecloudoptimizedcontent) |
| `disable-windows-tips` | `...\Windows\CloudContent\DisableSoftLanding` | 1 | [Experience CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#allowwindowstips) |
| `disable-feedback-prompts` | `...\Windows\DataCollection\DoNotShowFeedbackNotifications` | 1 | [Experience CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#donotshowfeedbacknotifications) |
| `disable-activity-history` | `...\Windows\System\EnableActivityFeed`, `PublishUserActivities`, `UploadUserActivities` | 0 | [Privacy CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-privacy#enableactivityfeed) |
| `disable-inking-typing-data` | `SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\TextInput\AllowLinguisticDataCollection` | 0 | [TextInput CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-textinput#allowlinguisticdatacollection) |
| `disable-ceip` | `SOFTWARE\Policies\Microsoft\SQMClient\Windows\CEIPEnable` | 0 | [ADMX_ICM CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-admx-icm#ceipenable) |
| `disable-app-telemetry` | `...\Windows\AppCompat\AITEnable` | 0 | [ADMX_AppCompat CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-admx-appcompat#appcompatturnoffapplicationimpacttelemetry) |
| `disable-search-highlights` | `...\Windows\Windows Search\EnableDynamicContentInWSB` | 0 | [Search CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-search#allowsearchhighlights) |

Pitfalls found while checking:

- `CEIPEnable` and `AITEnable` are "Turn off" policies whose enabled value is **0**, not 1.
- Consumer features, cloud optimized content and Windows tips are Enterprise/Education/IoT
  Enterprise only; LTSC IoT Enterprise qualifies.

## Applied in Slice 3 (user scope, every profile and the default profile)

Checked against the ADMX files in the VM (`tools/vm/guest-admx-lookup.ps1`, 2026-09-29):

| Tweak | Policy (ADMX) | Class | Enabled value |
| --- | --- | --- | --- |
| disable-tailored-experiences | `DisableTailoredExperiencesWithDiagnosticData` (CloudContent) | User | 1 |
| disable-third-party-suggestions | `DisableThirdPartySuggestions` (CloudContent) | User | 1 |
| disable-start-web-search | `DisableSearchBoxSuggestions` (WindowsExplorer) | User | 1 |

- `DisableSearchBoxSuggestions` is documented for recent entries in the File Explorer search box;
  that it also removes web results from Start search on Windows 11 is community knowledge
  (evidence `community`).
- `ConnectedSearchUseWeb` (`DoNotUseWebResults`, Search.admx) is not used: the LTSC 2024 ADMX marks it
  `WinBlueOnly`, class Machine.
- `HideRecommendedSection` (StartMenu.admx, class Both, Windows 11 22H2+) exists on LTSC; whether it
  hides Recommended on IoT Enterprise needs a visual check at a desktop logon in the VM.

## Parked
- **`DisableInventory`** (AppCompat): unclear whether Inventory Collector still exists in 24H2.
- **Find My Device, app location access, Windows Error Reporting**: they turn features off, not
  just data collection. Candidates for opt-in options with a warning.
