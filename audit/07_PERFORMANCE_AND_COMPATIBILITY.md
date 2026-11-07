# 07 — Performance, Stability, and Compatibility Audit

- **Sector Score:** **3.0 / 5**
- **Confidence:** Medium (High for Apple Silicon macOS 26.2 runtime and static binary inspection; Medium overall because Intel `x86_64` and macOS 13–15 runtime remain unverified on physical hardware)
- **Evidence Coverage:** Runtime Measurement (`ps`, `top`, `/usr/bin/time`, `pmset`), Static Binary Analysis (`lipo -detailed_info`, `otool -L`, `otool -l`), Source Inspection
- **Unresolved Findings:** 4 (`PERF-001` [P1], `QA-003` [P1], `POWER-003` [P2], `POWER-004` [P2])
- **NOT VERIFIED Requirements:** 4 (Intel `x86_64` hardware execution; macOS 13 Ventura / 14 Sonoma / 15 Sequoia OS testing; physical multi-display high-DPI menu bar; VoiceOver live navigation)

---

## 1. Empirical Performance & Resource Measurements (§11)

All measurements below were captured on the target machine without synthetic mocks:

- **Host Hardware:** Apple Silicon (`arm64`) MacBook (InternalBattery-0 present, 100% charged on AC Power)
- **Operating System:** macOS 26.2 (Build `25C56`)
- **Compiler:** Apple clang 17.0.0 (`clang-1700.3.19.1`), `-O2 -fobjc-arc`

### 1.1 Idle Active Mode (Smart Awake Active on AC Power — No Countdown Timer)

- **Target Process:** `PID 16618` (`/Applications/MacPulse.app/Contents/MacOS/MacPulse`), uptime `28m 59s`, holding `PreventUserIdleSystemSleep` assertion `[0x0004974c0001a3e7]`.
- **Measurement Tools:** `ps -o pid,pcpu,pmem,rss,vsz,etime -p 16618` and `top -l 2 -pid 16618 -s 1 -stats pid,cpu,mem,purg,ports,threads,power`.

| Metric | Measured Value | Methodology & Notes |
|---|---|---|
| **Idle CPU Usage (`%CPU`)** | **`0.0%`** | Sampled across 2-second `top -l 2` window and cumulative `ps` CPU time over 29 minutes of runtime. |
| **Energy Impact (`POWER`)** | **`0.0`** | `top` power score while holding `PreventUserIdleSystemSleep` on AC power with menu closed. |
| **Resident Set Size (`RSS`)** | **`10,400 KB` (`~10.16 MB`)** | Physical resident memory reported by `ps`. |
| **Private Memory (`MEM`)** | **`18 MB`** | Private memory footprint reported by `top` (`0B` purgeable). |
| **Mach Ports (`#PORTS`)** | **`188`** | Normal baseline for an AppKit `LSUIElement` status-bar application. |
| **Threads (`#TH`)** | **`4`** | Main runloop thread + standard GCD/AppKit worker threads. |
| **Executable Binary Size** | **`244 KB`** (`build/bin/MacPulse`) / **`293 KB`** (signed in `.app`) | Universal fat Mach-O (`135,240 bytes` `arm64` + `104,864 bytes` `x86_64`). |
| **Headless `--selftest` Execution Time** | **`0.84s` wall** (`0.07s` user, `0.18s` sys) | Measured via `/usr/bin/time -p ./build/bin/MacPulse --selftest` (10 subsystem checks including `NSPanel` layout). |

### 1.2 Active Timed Awake Mode Performance Defect (`PERF-001` — P1)

While idle performance in `Smart Awake`, `Always Awake`, and `Disabled` modes is genuinely event-driven (`0.0%` CPU, zero timers running), **starting a `Timed Awake` session introduces severe unnecessary work every 1.0 second**:

- **Location:** `Sources/MacPulseNative/MPStatusMenuController.m` lines 110–112, 230–294, 335–384; `MPAppSettings.m` line 77.
- **What Happens Every 1.0 Second During a Timed Session (Even With Menu Closed):**
  1. `MPTimedAwakeManager`'s `NSTimer` (1.0s interval, `NSRunLoopCommonModes`, zero `tolerance` set!) fires `handleTimerTick` -> `onTick`.
  2. `MPStatusMenuController` calls `[self updateUI]`.
  3. `updateUI` allocates a new `NSImage` for the status bar button (`line 343`).
  4. `updateUI` updates `button.title = _timedAwakeManager.compactTitle` (`line 350`) every second, even though `compactTitle` (`" 29m"`) only changes **once every 60 seconds**!
  5. `updateUI` calls `[self updateTimedAwakeSubmenu]` (`line 368`), which calls `[_timedAwakeSubmenu removeAllItems]` (`line 231`) and allocates 11 fresh `NSMenuItem` and `NSDictionary` objects every second, even when the menu is closed!
  6. `updateUI` calls `[_loginManager refreshStatus]` (`line 382`), which calls `[SMAppService mainAppService].status` (`line 34`)—performing a **synchronous XPC IPC call to `smd` (`launchd`) every 1.0 second** for the entire duration of the timer (e.g., 28,800 synchronous IPC calls during an 8-hour session)!
- **How to Fix:**
  1. Set `_timer.tolerance = 0.2;` on the `NSTimer` in `MPTimedAwakeManager.m` so macOS can coalesce timer wakeups and save CPU/battery energy.
  2. Only call `[_loginManager refreshStatus]` inside `menuWillOpen:` (when the user actually opens the menu) and `toggleLaunchAtLogin`, never inside the 1-second timer tick!
  3. Only update `button.title` on tick when `compactTitle` actually changes (`![button.title isEqualToString:newCompactTitle]`), and only update `_timedRemainingItem.title` in-place rather than calling `[_timedAwakeSubmenu removeAllItems]`.

### 1.3 Unnecessary `CFPreferencesAppSynchronize` IPC on Every State Evaluation
- In `MPPriorityArbiter.m` line 69, `evaluateEffectiveState` calls `[self.settings reloadSettings]`, which calls `CFPreferencesAppSynchronize` (`MPAppSettings.m` line 77). Every menu open (`menuWillOpen:`) and every setting toggle calls `CFPreferencesAppSynchronize` multiple times. `NSUserDefaults` already caches values in-process; removing redundant `CFPreferencesAppSynchronize` calls eliminates main-thread `cfprefsd` IPC stalls.

---

## 2. Binary Architecture & OS Compatibility Verification (§12)

### 2.1 Universal Binary Verification (`lipo` & `otool`)

Verified via `lipo -detailed_info build/bin/MacPulse` and `otool -l build/bin/MacPulse`:

| Slice | CPU Type | Offset | Slice Size | Alignment | `LC_BUILD_VERSION minos` | `sdk` | Linked Frameworks |
|---|---|---:|---:|---|---|---|---|
| **Apple Silicon (`arm64`)** | `CPU_TYPE_ARM64` (`ALL`) | `114688` | `135,240 B` | `2^14` (`16384`) | **`13.0`** | `26.0` | `Cocoa`, `IOKit`, `ServiceManagement`, `Foundation`, `AppKit`, `CoreFoundation` |
| **Intel (`x86_64`)** | `CPU_TYPE_X86_64` (`ALL`) | `4096` | `104,864 B` | `2^12` (`4096`) | **`13.0`** | `26.0` | `Cocoa`, `IOKit`, `ServiceManagement`, `Foundation`, `AppKit`, `CoreFoundation` |

### 2.2 API Availability Audit Against macOS 13.0 Ventura Target

All APIs used in `Sources/MacPulseNative/` were checked against Apple's SDK availability headers for macOS 13.0:
- `SMAppService.mainAppService` (`ServiceManagement.framework`): Introduced in **macOS 13.0** (guarded by `if (@available(macOS 13.0, *))` in `MPStatusMenuController.m` lines 33, 41).
- `[NSImage imageWithSystemSymbolName:accessibilityDescription:]`: Introduced in **macOS 11.0**. All 4 symbols (`bolt.fill`, `bolt.slash`, `sun.max.fill`, `timer`) exist in SF Symbols 2.0+ (macOS 11+).
- `IOPMAssertionCreateWithName` / `IOPMAssertionRelease`: Available since **macOS 10.6**.
- `IOPSNotificationCreateRunLoopSource` / `IOPSCopyPowerSourcesInfo`: Available since **macOS 10.2**.
- `os_unfair_lock`: Available since **macOS 10.12**.
- **Deprecation Note (`UX-004`):** `[NSApp activateIgnoringOtherApps:YES]` (`MPStatusMenuController.m` line 297, `MPAboutWindowController.m` line 129) is available on macOS 13.0 but soft-deprecated in macOS 14.0+.

---

## 3. Compatibility & Verification Matrix

| Configuration / Dimension | Target Requirement | Verification Method | Status | Notes |
|---|---|---|---|---|
| **Apple Silicon (`arm64`)** | Native execution | Compiled & executed live on `arm64` host | **VERIFIED** | Runs natively as `arm64` process (`PID 16618`). |
| **Intel (`x86_64`)** | Native execution | `lipo -detailed_info` + `otool -L` | **STATICALLY VERIFIED / RUNTIME NOT VERIFIED** | `x86_64` slice verified in Mach-O; physical Intel Mac or `arch -x86_64` Rosetta test needed. |
| **macOS 26.2 (Host OS)** | Supported | Live execution & test suites | **VERIFIED** | Tested on host OS Build `25C56`. |
| **macOS 13 Ventura / 14 Sonoma / 15 Sequoia** | Supported (`minos 13.0`) | `LC_BUILD_VERSION` & symbol availability inspection | **STATICALLY VERIFIED / RUNTIME NOT VERIFIED** | Binary `minos` is `13.0` and all symbols exist on macOS 13+, but not runtime-tested on macOS 13/14/15 VMs. |
| **Light & Dark Appearances** | Native adaptation | Static inspection (`image.template = YES`, system colors `labelColor`, `secondaryLabelColor`) | **VERIFIED** | Uses semantic `NSColor` and template SF Symbols; no hardcoded text colors. |
| **Desktop Mac (No Battery)** | Treat as AC connected; no `-1%` display | `MPPowerSourceMonitor.m` lines 147–152 + `test_arbiter_exhaustive_matrix` | **SIMULATED VERIFIED / HARDWARE NOT VERIFIED** | Fallback logic verified in unit/matrix tests; not tested on physical Mac mini/Studio/iMac. |
| **VoiceOver & Keyboard Navigation** | Accessible menu & About window | Static inspection (`accessibilityDescription`, `keyEquivalent`) | **PARTIAL (`PERF-001`, `UX-004`)** | Active timer breaks submenu focus every 1s (`PERF-001`); live VoiceOver pass **NOT VERIFIED**. |
