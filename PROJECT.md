# Project: MacPulse

## Architecture
MacPulse is a native macOS automatic awake utility with optional advanced controls.
- **Frameworks**: AppKit (`NSApplication`, `NSStatusItem`, `NSMenu`, `NSWindow`), IOKit (`IOPowerSources.h`, `IOPMLib.h`), ServiceManagement (`SMAppService.mainApp`), Foundation.
- **Language & Runtime**: Native Objective-C ARC compiled via `xcrun clang` into a Universal Fat Mach-O Binary (`arm64 + x86_64`) targeting macOS 13+.
- **Subsystems**:
  - `MPPowerSourceMonitor`: Event-driven zero-polling hardware monitor using `IOPSNotificationCreateRunLoopSource` on the main runloop. Tracks AC connection, battery percentage, charging state, and desktop Mac presence.
  - `MPPowerManager`: Sleep assertion lifecycle manager. Manages `PreventUserIdleSystemSleep` (`systemAssertionID`) and `PreventUserIdleDisplaySleep` (`displayAssertionID`). Ensures idempotency, zero leaks, and clean termination teardown.
  - `MPPriorityArbiter`: State machine resolving competing mode demands: `Always Awake (>= threshold) > Timed Awake (active timer) > Smart Awake (AC connected) > Disabled`.
  - `MPTimedAwakeManager`: Manages 30m, 1h, 2h keep-awake sessions, live 1-second countdown ticks, status bar title updates, cancellation, and expiration fallback.
  - `MPStatusMenuController`: Controls `NSStatusItem`, dynamic template SF Symbols (`bolt.fill`, `bolt.slash`, `sun.max.fill`, `timer`), submenus for Timed Awake and Always Awake threshold, toggles for Display Sleep, Smart Awake, Launch at Login, and Help/About.
  - `MPAboutWindowController`: Centered floating utility window explaining all features clearly to new users.
  - `MPSelfTestRunner`: Headless CLI test harness invoked via `--selftest` executing deterministic unit and integration checks across all subsystems.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Dynamic Status Icon | Menu bar icon reflects state (`bolt.fill`, `bolt.slash`, `sun.max.fill`, `timer`) | M3 | survey |
| 2 | Status Bar Countdown Title | Compact remaining duration displayed beside icon when timer is active | M2 | survey |
| 3 | Menu Header Section | Non-clickable bold branding header "MacPulse" | M3 | survey |
| 4 | Power Source Status Line | Live power source and battery percentage display | M1 | survey |
| 5 | System Status Line | Live system sleep assertion mode display | M1 | survey |
| 6 | Smart Awake Toggle & Assertion | `PreventUserIdleSystemSleep` assertion when AC connected; release on unplug | M1 | survey |
| 7 | Allow Display Sleep Toggle & Assertion | Independent screen sleep toggle; unchecking creates `PreventUserIdleDisplaySleep` | M1 | survey |
| 8 | Timed Awake 30-Minute Preset | 1,800-second temporary session with sleep assertion | M2 | survey |
| 9 | Timed Awake 1-Hour Preset | 3,600-second temporary session with sleep assertion | M2 | survey |
| 10 | Timed Awake 2-Hour Preset | 7,200-second temporary session with sleep assertion | M2 | survey |
| 11 | Timed Awake Live Countdown & Cancellation | Submenu displays live MM:SS countdown and cancellation item | M2 | survey |
| 12 | Always Awake Primary Toggle | Keeps system awake on both AC and battery power | M1 | survey |
| 13 | Battery Safety Threshold Submenu | Configures safety threshold (10%, 20% default, 30%, 40%, 50%) | M1 | survey |
| 14 | Always Awake Automatic Battery Cutoff | Automatically disengages Always Awake when battery <= threshold | M1 | survey |
| 15 | Mode Priority Arbiter | Resolves Always Awake > Timed Awake > Smart Awake > Disabled | M1 | survey |
| 16 | Launch at Login via SMAppService | Toggles persistent login item via `SMAppService.mainApp` | M3 | survey |
| 17 | About & Help Window | Native floating dialog explaining all features to new users | M3 | survey |
| 18 | Clean Termination Teardown | Releases all assertions on quit/termination; zero kernel leaks | M1 | survey |
| 19 | Universal Binary Compilation | Emits fat Mach-O executable (`arm64 + x86_64`) via `build.sh` | M4 | survey |
| 20 | Packaging Pipeline & Bun Scripts | Generates `dist/MacPulse.dmg` and Bun script wrappers | M4 | survey |
| 21 | Headless Self-Test Runner | `--selftest` flag running deterministic checks exiting 0 or 1 | M4 | survey |
| 22 | Zero-Polling Hardware Monitor | `IOPSNotificationCreateRunLoopSource` event-driven notifications | M1 | survey |
| 23 | Desktop Mac Support | Detects desktop Macs without battery hardware; avoids division-by-zero | M1 | survey |
| 24 | E2E Full Test Suite Verification | Passes 100% of Tiers 1-4 opaque-box requirement tests | M5 | survey |
| 25 | Adversarial Coverage Hardening | Tier 5 white-box challenger analysis and stress testing | M5 | survey |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Power Assertion & Priority Engine | Power monitoring (IOPS runloop), dual assertions (system + display), priority arbitration, battery cutoff, teardown | none | DONE |
| M2 | Timed Awake & Countdown Engine | Timed sessions (30m, 1h, 2h), monotonic countdown timer, live menu title updates, cancellation & expiration | M1 | DONE |
| M3 | User Interface, Submenus & About Window | Dynamic menu bar icons, submenus for Timed Awake & Battery Threshold, Display Sleep toggle, About/Help window, Launch at Login | M1, M2 | DONE |
| M4 | Universal Build, Packaging & Self-Test | Universal binary build (`build.sh`), `tools/selftest.sh`, Bun scripts, headless `--selftest` suite | M1, M2, M3 | DONE |
| M5 | E2E Verification & Adversarial Hardening | Phase 1: Pass 100% E2E test suite (Tiers 1-4); Phase 2: Tier 5 adversarial hardening | M4, TEST_READY | DONE |

## Interface Contracts
### MPPowerSourceMonitor ↔ MPPriorityArbiter
- Callback signature: `typedef void (^MPPowerSourceChangeHandler)(BOOL isACConnected, NSInteger batteryPercentage, BOOL isCharging, BOOL isDesktop);`
- Invariants: Handled on main runloop. When `isDesktop == YES`, `isACConnected` is unconditionally `YES` and `batteryPercentage` is `-1`.

### MPPowerManager ↔ MPPriorityArbiter
- Signatures:
  - `-(void)applyStateWithSystemSleepPrevented:(BOOL)preventSystem displaySleepPrevented:(BOOL)preventDisplay reason:(NSString *)reason;`
  - `-(void)releaseAllAssertions;`
  - `@property (nonatomic, readonly) BOOL isSystemSleepPrevented;`
  - `@property (nonatomic, readonly) BOOL isDisplaySleepPrevented;`
- Error handling: Returns boolean success; logs IOKit return code on failure; defensive assertion ID tracking prevents double-release.

### MPTimedAwakeManager ↔ MPPriorityArbiter
- Signatures:
  - `-(void)startSessionWithDuration:(NSTimeInterval)duration;`
  - `-(void)cancelSession;`
  - `@property (nonatomic, readonly) BOOL isActive;`
  - `@property (nonatomic, readonly) NSTimeInterval remainingSeconds;`
  - `typedef void (^MPTimedAwakeTickHandler)(NSTimeInterval remainingSeconds);`
  - `typedef void (^MPTimedAwakeCompletionHandler)(BOOL expired);`

### MPPriorityArbiter ↔ MPStatusMenuController
- Signatures:
  - `-(void)evaluateEffectiveState;`
  - `@property (nonatomic, readonly) MPActiveMode currentMode; // Disabled, SmartAwake, TimedAwake, AlwaysAwake`
  - `@property (nonatomic, readonly) NSString *statusSummaryString;`
  - `@property (nonatomic, readonly) NSString *menuIconName;`

## Code Layout
Target directory: `/Users/shoaib/Workspace/Projects/MacPulse`
- `Sources/MacPulseNative/`
  - `main.m` — Application entrypoint, subsystem initialization, NSApplicationDelegate, `--selftest` dispatcher
  - `MPPowerSourceMonitor.h / .m` — Zero-polling IOKit runloop power monitoring
  - `MPPowerManager.h / .m` — Dual assertion lifecycle (`PreventUserIdleSystemSleep`, `PreventUserIdleDisplaySleep`)
  - `MPPriorityArbiter.h / .m` — Mode arbitration state machine (Always Awake > Timed Awake > Smart Awake > Disabled)
  - `MPTimedAwakeManager.h / .m` — Timed session countdown engine
  - `MPStatusMenuController.h / .m` — Menu bar UI, dynamic icons, submenus, toggles
  - `MPAboutWindowController.h / .m` — Floating About & Help utility window
  - `MPSelfTestRunner.h / .m` — Deterministic headless verification suite
- `build.sh` — Universal Fat Binary compilation (`-arch arm64 -arch x86_64`) and app bundling
- `tools/selftest.sh` — Automated headless self-test execution
- `scripts/package.sh` & `scripts/package.ts` — DMG generation and packaging
- `tests/` — E2E test suite directory (opaque-box requirement tests)
