# 00 — Executive Summary: MacPulse Independent Pre-Launch Audit

- **Audit Date:** 2026-11-07
- **Target Repository:** `/Users/shoaib/Workspace/Projects/MacPulse`
- **Git Baseline:** Commit `6461428` (`master`, dirty working tree with untracked production implementation in `Sources/MacPulseNative/`)
- **Host Environment:** Apple Silicon (`arm64`), macOS 26.2 (Build `25C56`), Apple clang 17.0.0 (`clang-1700.3.19.1`), Swift 6.2
- **Overall Release Status:** **NOT READY** (for Public Release)
- **Next-Stage Recommendation:** **Continue engineering** (resolve P0/P1 findings, then advance to **Ready for internal testing** / **Ready for controlled beta**)

---

## 1. Overall Assessment

MacPulse has a solid, lightweight native core in `Sources/MacPulseNative/` (1,210 lines of Objective-C ARC across 7 classes) that genuinely uses event-driven `IOPowerSources` run-loop notifications (`IOPSNotificationCreateRunLoopSource`), creates and releases real `IOPMAssertion` kernel assertions (`powerd`), runs as a native menu-bar agent (`LSUIElement = true`) with `0.0%` idle CPU usage and `~10.4 MB` RSS (`18 MB` private memory), and compiles into a Universal Mach-O binary (`arm64` + `x86_64`) targeting macOS 13.0+.

However, **MacPulse is NOT READY for public release.** Independent source inspection, automated test analysis, and runtime verification uncovered **2 P0 Critical release blockers**, **8 P1 High defects/gaps**, **9 P2 Medium issues**, and **2 P3 Low issues** that were masked by an over-optimistic test suite where **70 out of 98 E2E test cases (71.4%) never execute the compiled MacPulse binary**.

---

## 2. Sector Scorecard

| Sector | Score / 5 | Confidence | Evidence Coverage | Unresolved Findings | NOT VERIFIED Reqs | Status |
|---|---:|---|---|---:|---:|---|
| 1. Product & Feature Scope | **3.0 / 5** | High | Static + Automated + Runtime | 4 (`SCOPE-001`, `POWER-001`, `SCOPE-002`, `UX-001`) | 2 | Acceptable with notable scope & cutoff gaps |
| 2. Market & Competitor Positioning | **3.5 / 5** | High | External Research + Static | 1 (`BRAND-001`) | 0 | Clear niche; trademark naming risk |
| 3. UX, UI & Accessibility | **2.5 / 5** | High | Static + Runtime | 5 (`PERF-001`, `POWER-001`, `UX-001`, `UX-002`, `UX-003`, `UX-004`) | 2 | Significant UI/UX fixes required |
| 4. Architecture & Code Quality | **2.5 / 5** | High | Static + Automated | 4 (`ARCH-001`, `POWER-001`, `POWER-002`, `QA-003`) | 0 | Good ObjC core; dead Swift duplication & callback bugs |
| 5. macOS Power Management & Lifecycle | **3.0 / 5** | High | Static + Runtime (`pmset`) | 4 (`POWER-001`, `POWER-002`, `POWER-003`, `POWER-004`) | 5 | Core assertions work; cutoff & sleep/wake gaps |
| 6. Security & Privacy | **3.5 / 5** | High | Static + Automated (`otool`, `codesign`, `spctl`) | 3 (`REL-001`, `QA-001`, `SEC-001`) | 0 | Strong offline privacy; unsigned/unnotarized |
| 7. QA & Test Engineering | **1.5 / 5** | High | Static + Automated Execution | 3 (`QA-001`, `QA-002`, `QA-003`) | 6 | Serious deficiencies; 71% fake E2E tests |
| 8. Performance & Compatibility | **3.0 / 5** | Medium | Runtime (`ps`/`top`) + Static (`lipo`/`otool`) | 2 (`PERF-001`, `QA-003`) | 4 | Great idle footprint; 1 Hz IPC in Timed mode |
| 9. Build, DevOps & Release Engineering | **1.5 / 5** | High | Static + Automated (`codesign`, `spctl`, `hdiutil`) | 3 (`REL-001`, `REL-002`, `REL-003`) | 1 | Serious deficiencies; Gatekeeper blocks app |
| 10. Documentation, Support & Marketing | **2.0 / 5** | High | Static Inspection | 3 (`REL-003`, `DOC-001`, `BRAND-001`) | 0 | Missing `LICENSE`, stale docs, path mismatches |

---

## 3. Main Strengths (What Is Already Good and Must Be Preserved)

1. **Zero-Polling Power Source Architecture (`MPPowerSourceMonitor.m`):** Uses `IOPSNotificationCreateRunLoopSource` attached to `CFRunLoopGetMain()` in `kCFRunLoopCommonModes` with a 250ms debounce window (`dispatch_after`), avoiding background polling timers when idle.
2. **Real Kernel Assertion Lifecycle (`MPPowerManager.m`):** Uses `IOPMAssertionCreateWithName` and `IOPMAssertionRelease`, sets `_systemAssertionID = kIOPMNullAssertionID` before releasing to prevent double-release (`0xe00002c2`) errors, and cleans up assertions on `SIGTERM` (`applicationWillTerminate:`) and `SIGKILL` (via kernel Mach task port reaping).
3. **Minimal Runtime Footprint:** Verified live process `PID 16618` (`/Applications/MacPulse.app/Contents/MacOS/MacPulse`) consumes `0.0%` CPU and `10,400 KB` RSS (`18 MB` MEM) when idle on AC power.
4. **Zero Third-Party Dependencies & Complete Offline Privacy:** Links exclusively against Apple system frameworks (`Cocoa`, `IOKit`, `ServiceManagement`, `Foundation`, `AppKit`, `CoreFoundation`). Contains zero networking code (`NSURLSession`, `CFNetwork`), zero analytics, and zero telemetry.
5. **Universal Fat Binary (`arm64` + `x86_64`):** Both architectures are present and verified via `lipo -detailed_info` and `otool -l` (`LC_BUILD_VERSION minos 13.0`).

**Do not rewrite `Sources/MacPulseNative/` into Swift or another framework.** The Objective-C ARC implementation is compact, fast, and directly suited to the task; only targeted defect fixes and scope cleanup are needed.

---

## 4. Main Weaknesses & Most Serious Risks

1. **P0 — In-App Self-Test Corrupts Live User Preferences (`QA-001`):** Running `./build/bin/MacPulse --selftest` or `./tools/selftest.sh` mutates the user's real `com.shoaib.macpulse` `NSUserDefaults` domain (ignoring `APP_STORE=/tmp/MacPulse-self.store`) and leaves `keepAwakeWhileCharging = 0` (`NO`) on exit. Any user or script running `--selftest` silently disables Smart Awake.
2. **P0 — Gatekeeper Rejects App Bundle and DMG (`REL-001`):** `MacPulse.app` is ad-hoc signed (`flags=0x2(adhoc)`) without Hardened Runtime (`--options runtime`), Developer ID Application certificate, or Apple Notarization (`stapler validate` fails; `spctl --assess` returns `rejected / source=no usable signature`). Any Mac user downloading `MacPulse.dmg` from the internet will be blocked by macOS Gatekeeper.
3. **P1 — Out-of-Scope Display Sleep Prevention Shipped (`SCOPE-001`):** Canonical requirement §3.5 explicitly prohibits an independent display-sleep prevention toggle or `PreventUserIdleDisplaySleep` assertion. Yet `MPPowerManager`, `MPPriorityArbiter`, `MPStatusMenuController`, and `MPAboutWindowController` expose `"Allow Display Sleep"` and create `kIOPMAssertionTypePreventUserIdleDisplaySleep`.
4. **P1 — Battery Cutoff Synchronous Re-Entrancy & Invisible UI State (`POWER-001`):** When battery drops at or below threshold on battery power, `MPPriorityArbiter.m` line 85 calls `self.settings.alwaysAwake = NO` *before* setting `_isBatteryCutoffActive = YES` (line 94). Because `setAlwaysAwake:` synchronously posts `kMPAppSettingsDidChangeNotification`, `evaluateEffectiveState` recursively re-enters itself with `alwaysAwake == NO`, setting `_isBatteryCutoffActive = NO`. Worse, `MPStatusMenuController` never reads `isBatteryCutoffActive`, so the user receives zero visual feedback that Battery Protection turned off Always Awake.
5. **P1 — 1 Hz Synchronous IPC & Submenu Reconstruction in Timed Awake (`PERF-001`):** Every 1 second during a Timed Awake session, `_timedAwakeManager.onTick` calls `[self updateUI]`, which queries `[SMAppService mainAppService].status` (synchronous XPC IPC to `smd`) and calls `[_timedAwakeSubmenu removeAllItems]` to destroy and recreate all 11 submenu items—breaking user hover and VoiceOver navigation while the submenu is open.
6. **P1 — Misleading E2E Test Suite (`QA-002`) & Multi-Threaded Stress Failure (`QA-003`):** 70 of the 98 E2E tests in `Tests/run_e2e_tests.sh` never execute `MacPulse` (41 run inline `python3 -c` mock functions, 12 only read/write `defaults`, 5 are unconditional `test_pass` no-ops). Meanwhile, executing `./build/bin/test_power_manager_stress` actually **failed** during audit verification with `INVARIANT VIOLATION: Display sleep prevented while system sleep allowed!` due to separate lock acquisitions (`TOCTOU`) in `isSystemSleepPrevented` and `isDisplaySleepPrevented`.
7. **P1 — Dual Disconnected Codebases (`ARCH-001`) & Destructive `build.sh` (`REL-002`):** Dead Swift files in `Sources/MacPulse/` and `Sources/MacPulseKit/` fail `swift test` and diverge from `Sources/MacPulseNative/`. Meanwhile, `build.sh` unconditionally overwrites both `/Applications/MacPulse.app` and `~/Applications/MacPulse.app`, registering duplicate bundles in LaunchServices and Spotlight.

---

## 5. Release Blockers Summary

Before any public release (and before beta distribution outside the developer's machine), the following **must** be resolved:

- **`QA-001` (P0):** Isolate `--selftest` (and Tier 5 stress tests) to a temporary/ephemeral `NSUserDefaults` suite so tests never mutate `com.shoaib.macpulse`.
- **`REL-001` (P0):** Enable Hardened Runtime (`--options runtime`), sign with a valid `Developer ID Application` certificate, notarize via `xcrun notarytool`, and staple the ticket (`xcrun stapler staple`) to both `MacPulse.app` and `MacPulse.dmg`.
- **`SCOPE-001` (P1):** Remove the out-of-scope `"Allow Display Sleep"` toggle and `PreventUserIdleDisplaySleep` assertion so the display always sleeps normally per §3.5.
- **`POWER-001` & `POWER-002` (P1):** Fix synchronous re-entrancy in `MPPriorityArbiter`, surface battery-cutoff state clearly in the menu UI, and stop `MPStatusMenuController` from overwriting `MPPriorityArbiter`'s timer callbacks.
- **`PERF-001` (P1):** Decouple 1-second countdown ticks from `[SMAppService mainAppService].status` IPC and update the countdown menu item title in-place without calling `removeAllItems`.
- **`ARCH-001` & `REL-002` (P1):** Remove dead Swift duplicate files (`Sources/MacPulse/`, `Sources/MacPulseKit/`, `Package.swift`), stop `build.sh` from installing duplicate bundles into both `/Applications` and `~/Applications`, commit the codebase to Git, and add the missing `LICENSE` file (`REL-003`).
- **`QA-002` & `QA-003` (P1):** Replace fake inline Python E2E tests with real binary/subsystem verification and fix the lock TOCTOU in `MPPowerManager`.

---

## 6. Final Recommendation

**Status:** **NOT READY** for public release (`Continue engineering`).

1. **Immediate Stage (Engineering Remediation — Est. 1–2 days):** Fix P0 and P1 findings (`QA-001`, `SCOPE-001`, `POWER-001`, `POWER-002`, `PERF-001`, `ARCH-001`, `QA-002`, `QA-003`, `REL-002`, `REL-003`).
2. **Gate to Internal Testing / Controlled Beta:** All unit/integration/E2E tests execute real Objective-C production code with zero live preference mutation; manual hardware test plan (`audit/13_MANUAL_HARDWARE_TEST_PLAN.md`) passes on physical MacBook AC/battery transitions.
3. **Gate to Public Release:** Developer ID signing, Hardened Runtime, Apple Notarization, and Gatekeeper `spctl --assess` verification pass (`REL-001`), and `audit/14_FINAL_RELEASE_CHECKLIST.md` is 100% signed off.
