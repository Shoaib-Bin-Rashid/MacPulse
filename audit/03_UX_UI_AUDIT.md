# 03 — UX, UI, and Accessibility Audit

- **Sector Score:** **2.5 / 5**
- **Confidence:** High
- **Evidence Coverage:** Static Inspection (`MPStatusMenuController.m`, `MPAboutWindowController.m`, `Icon/AppIcon.png`), Runtime Inspection (`PID 16618`)
- **Unresolved Findings:** 6 (`PERF-001` [P1], `POWER-001` [P1], `SCOPE-001` [P1], `UX-001` [P2], `UX-002` [P2], `UX-003` [P2], `UX-004` [P3])
- **NOT VERIFIED Requirements:** 2 (VoiceOver full interactive screen-reader pass; multi-display menu bar appearance under extreme display scaling)

---

## 1. Ten-Question First-Use Comprehension Assessment (§6)

| # | Evaluation Question | Verdict | Evidence & Analysis |
|---:|---|---|---|
| 1 | **Is it clear what the application does?** | **Mostly Yes** | The menu items and `About & Help...` panel explain keep-awake modes, though `"Keep Awake While Charging"` in the menu vs `"Smart Awake"` in `About MacPulse` creates minor naming inconsistency (`UX-001`). |
| 2 | **Can the user identify its current state?** | **Partial** | The menu bar icon changes (`bolt.fill`, `bolt.slash`, `sun.max.fill`, `timer`), and the menu shows `System Status: ...`. However, in Smart Awake mode, the label reads `"System Status: Awake (Awake)"` (`UX-001`), which looks like a string formatting bug. |
| 3 | **Can they predict what will happen when unplugging the charger?** | **Yes** | When `"Keep Awake While Charging"` is checked and `"Always Awake"` / `"Timed Awake"` are unchecked, unplugging transitions the icon from `bolt.fill` to `bolt.slash` (`System Status: Normal Sleep`). |
| 4 | **Can they start and cancel a timed session without confusion?** | **Partial** | Starting and cancelling from the `Timed Awake` submenu is intuitive, and a checkmark (`✓`) appears on `Timed Awake` and the active preset. **However**, while a timer is running, `updateTimedAwakeSubmenu` calls `[_timedAwakeSubmenu removeAllItems]` every 1.0 second (`PERF-001`), which resets submenu hover highlight and breaks keyboard/VoiceOver navigation while the submenu is open. |
| 5 | **Is Always Awake distinguishable from Smart Awake?** | **Yes** | `Always Awake` uses `sun.max.fill` and displays `System Status: Awake (Always Awake)`, whereas `Smart Awake` uses `bolt.fill`. |
| 6 | **Is battery protection understandable?** | **No (`POWER-001`, `SCOPE-002`)** | `"Battery Safety Threshold"` sits as a top-level menu item without indicating that it **only** applies to `"Always Awake"`. Worse, when Battery Protection trips and turns off `Always Awake`, the UI gives **zero notification or status message** (`isBatteryCutoffActive` is never displayed in `MPStatusMenuController.m`), and there is no toggle to enable/disable battery protection. |
| 7 | **Are advanced options hidden until needed?** | **No (`SCOPE-001`, `SCOPE-002`)** | The canonical design (§3.9, §4) calls for a minimal menu where battery threshold is tucked under `Always Awake` / `Advanced Settings` and Display Sleep is absent. Currently, `Battery Safety Threshold` and `Allow Display Sleep` are top-level menu items. |
| 8 | **Does any element make the menu unnecessarily complicated?** | **Yes (`SCOPE-001`)** | `"Allow Display Sleep"` is out of scope (§3.5) and adds an extra toggle (`Cmd+D`). Also, informational rows (`Power Source:` and `System Status:`) are placed *below* the toggles rather than at the top of the menu as specified in §4. |
| 9 | **Does the interface feel like a native macOS utility?** | **Yes** | Uses native AppKit `NSStatusItem`, `NSMenu`, `NSMenuItem`, SF Symbol template images (`image.template = YES`), and a native `NSPanel` for About/Help. Adapts automatically to Light and Dark modes. |
| 10 | **Are errors explained in actionable language?** | **Partial (`UX-002`)** | Custom duration validation (`promptCustomDuration`, lines 326–331) shows a clear `NSAlert` (`"Please enter a valid duration between 1 and 10080 minutes."`). However, `Launch at Login` (`toggleLaunchAtLogin`, lines 40–52) silently swallows `SMAppService` errors without telling the user when approval is required in **System Settings > General > Login Items & Extensions**. |

---

## 2. Menu Structure Comparison (Canonical §4 vs. Implemented `MPStatusMenuController.m`)

| Canonical Menu Structure (§4) | Implemented Menu (`MPStatusMenuController.m` lines 134–226) | Discrepancy |
|---|---|---|
| **MacPulse** *(Header)* | **MacPulse** *(Bold 13pt header)* | Matches |
| `Smart Awake Active` *(Status)* | *(Placed at bottom of controls as `System Status: Awake (Awake)`)* | Redundant `"Awake (Awake)"` string (`UX-001`); status placed below toggles instead of above |
| `Power Source: AC` / `Battery: 85%` | `Power Source: AC Power (100%)` *(Placed below toggles)* | Combined into one clean line, but placed below toggles |
| `Smart Awake` (`ON`/`✓`) | `Keep Awake While Charging` (`Cmd+C`) | Different label from `"Smart Awake"` (`UX-001`) |
| `Timed Awake` › (`30m, 1h, 2h, Cancel`) | `Timed Awake` › (`Custom Duration...`, `15m, 30m, 45m, 1h, 2h, 4h, 8h`) | Rebuilt destructively every 1s during active session (`PERF-001`) |
| `Always Awake` / `Advanced` › (`Battery protection`, `10%–50%`) | Top-level `Always Awake` (`Cmd+A`) + separate top-level `Battery Safety Threshold` › (`10%–80%`) | Threshold not grouped under Always Awake / Advanced; includes 60–80%; lacks protection ON/OFF toggle (`SCOPE-002`) |
| *(No Display Sleep toggle — §3.5)* | `Allow Display Sleep` (`Cmd+D`) | **Out-of-scope feature (`SCOPE-001`)** |
| `Launch at Login` | `Launch at Login` (`Cmd+L`) | Silent failure on `SMAppServiceStatusRequiresApproval` (`UX-002`) |
| `About MacPulse` | `About & Help...` | Opens 440x420 `MPAboutWindowController` panel |
| `Quit MacPulse` | `Quit MacPulse` (`Cmd+Q`) | Matches |

---

## 3. Specific UI, Icon, and Accessibility Findings

### 3.1 Destructive Submenu Rebuild Every 1 Second (`PERF-001` — P1)
- **Location:** `Sources/MacPulseNative/MPStatusMenuController.m` lines 110–112, 230–294, 368.
- **Observed Implementation:** When a Timed Awake session is active, `_timedAwakeManager.onTick` fires every 1.0 second and calls `[self updateUI]`, which calls `[self updateTimedAwakeSubmenu]`. Line 231 executes `[_timedAwakeSubmenu removeAllItems];` and recreates all submenu items from scratch every second.
- **Why It Matters:** If the user opens the menu and hovers over `Timed Awake` to click `"Cancel Timed Session"` or switch presets, destroying and recreating all `NSMenuItem` objects every 1 second causes the open submenu to lose hover state, flicker, and drop VoiceOver focus.
- **How to Fix:** Build `_timedAwakeSubmenu` items once (or only when `_timedAwakeManager.isActive` transitions between `YES` and `NO`), keep an ivar `_timedRemainingItem`, and on each 1-second tick only update `_timedRemainingItem.title = [NSString stringWithFormat:@"Time Remaining: %@", _timedAwakeManager.formattedRemainingTime]` and `button.title = _timedAwakeManager.compactTitle`.

### 3.2 Redundant `"System Status: Awake (Awake)"` & Naming Drift (`UX-001` — P2)
- **Location:** `Sources/MacPulseNative/MPPriorityArbiter.m` lines 18, 136, 141; `Sources/MacPulseNative/MPStatusMenuController.m` lines 145, 194, 376–378.
- **Observed Implementation:**
  - In `MPPriorityArbiter.m` line 136, `MPActiveModeSmartAwake` sets `_statusSummaryString = @"Awake";`.
  - In `MPStatusMenuController.m` line 376, `isAwake` formats `[NSString stringWithFormat:@"System Status: Awake (%@)", _arbiter.statusSummaryString]`, producing `"System Status: Awake (Awake)"`.
  - Ironically, `Tests/tiers/tier1_features/test_f06_ui_and_about.sh` (`T1_F06_03`) asserted `format_status("Smart Awake", True) == "System Status: Awake (Smart Awake)"` using a fake Python function instead of inspecting the real app!
  - Also, `MPPriorityArbiter.m` line 18 & 141 uses British spelling `"Normal Sleep Behaviour"`, whereas `MPStatusMenuController.m` line 194 & 378 uses `"System Status: Normal Sleep"`.
- **How to Fix:** Change `_statusSummaryString` for `MPActiveModeSmartAwake` in `MPPriorityArbiter.m` line 136 from `@"Awake"` to `@"Smart Awake"`, and standardize on `"Normal Sleep"` across all files. Rename or subtitle `"Keep Awake While Charging"` to `"Smart Awake (While Charging)"`.

### 3.3 Missing UI Feedback When Battery Safety Cutoff Disengages Always Awake (`POWER-001` — P1)
- **Location:** `Sources/MacPulseNative/MPPriorityArbiter.m` lines 83–94; `Sources/MacPulseNative/MPStatusMenuController.m` lines 375–379.
- **Observed Implementation:** `MPStatusMenuController.m` never reads `_arbiter.isBatteryCutoffActive`. When Always Awake is automatically turned off because battery reached `<= threshold`, the status line simply says `"System Status: Normal Sleep"`, giving the user no indication that Battery Safety Protection intervened.
- **How to Fix:** Preserve `_isBatteryCutoffActive = YES` in `MPPriorityArbiter` until the user manually toggles a mode or connects AC power, and display `"System Status: Normal Sleep (Paused at Low Battery)"` in `_systemStatusItem.title`.

### 3.4 Silent Login Item Failure on `RequiresApproval` (`UX-002` — P2)
- **Location:** `Sources/MacPulseNative/MPStatusMenuController.m` lines 40–52, 424–427.
- **Observed Implementation:** `toggleLaunchAtLogin` ignores the returned `BOOL` and `NSError *`. If `SMAppService.mainAppService.status == SMAppServiceStatusRequiresApproval`, registration fails silently.
- **How to Fix:** Check `SMAppService.mainAppService.status == SMAppServiceStatusRequiresApproval` or `error != nil` after `registerAndReturnError:`. Present an `NSAlert` explaining that macOS requires permission in **System Settings > General > Login Items & Extensions**, with a button calling `[SMAppService openSystemSettingsLoginItems]`.

### 3.5 App Icon Visual & HIG Audit (`UX-003` — P2)
- **Location:** `Icon/AppIcon.png`, `Icon/AppIcon.icns`.
- **Observed Implementation:**
  1. **Embedded Text (`"MacPulse"`):** The icon graphic contains the full word `"MacPulse"` across the bottom third of the squircle. Per Apple's macOS Human Interface Guidelines (*App Icons*), text inside an app icon should be avoided because the system displays the app name directly underneath the icon in Launchpad, Finder, and Dock, and embedded text becomes illegible blur at `16x16` and `32x32` menu/Spotlight sizes.
  2. **White Edge Fringe:** Because `AppIcon.png` was cropped from a flat JPEG with a white background and drop shadow, a 1–2px light/white fringe remains visible along the bottom-left and bottom-right curved corners of the dark navy squircle.
  3. **Menu-Bar Icons (`bolt.fill`, `bolt.slash`, `sun.max.fill`, `timer`):** In contrast to the app icon, the menu-bar icons are native Apple SF Symbols configured with `image.template = YES` (`MPStatusMenuController.m` line 345), so they render crisply at 16px/32px in both Light and Dark appearances and monochrome states.

### 3.6 Accessibility, Tooltips, and Deprecated Activation API (`UX-004` — P3)
- **Location:** `Sources/MacPulseNative/MPStatusMenuController.m` lines 145–226, 297; `MPAboutWindowController.m` line 129.
- **Observed Implementation:**
  - Menu items have no `.toolTip` strings set, so hovering over `"Battery Safety Threshold"` or `"Always Awake"` provides no contextual explanation.
  - `[NSApp activateIgnoringOtherApps:YES]` (`MPStatusMenuController.m` line 297 and `MPAboutWindowController.m` line 129) is deprecated in macOS 14.0+ (where `[NSApp activate]` is preferred).
  - Status bar button sets `accessibilityDescription` on the `NSImage` (`MPStatusMenuController.m` line 344), which is good practice for VoiceOver.
