# 12 — Prioritized Remediation Roadmap

This roadmap organizes all 21 audit findings into actionable engineering tasks across priority tiers (`P0` through `P4`). Per Phase 1 Audit Rules (§1.1 & §18.13), no production code was modified during this audit; execute these tasks in sequence during Phase 2 remediation.

---

## P0 — Release Blockers (Must Fix Immediately)

### Task P0-1: Isolate `--selftest` and Stress Suites from Live User Preferences
- **Finding IDs:** `QA-001`
- **Classification:** Required fix
- **Affected Files:**
  - `Sources/MacPulseNative/MPAppSettings.h` & `MPAppSettings.m`
  - `Sources/MacPulseNative/main.m` (`runSelfTests`)
  - `Tests/tiers/tier5_adversarial/test_arbiter_exhaustive_matrix.m`
  - `tools/selftest.sh`
- **Expected Outcome:** Running `MacPulse --selftest`, `./tools/selftest.sh`, or `./build/bin/test_arbiter_exhaustive_matrix` uses an isolated, ephemeral `NSUserDefaults` suite name (e.g., `com.shoaib.macpulse.selftest.<pid>` or environment variable `MACPULSE_DEFAULTS_SUITE`) and removes the temporary domain upon completion, leaving `~/Library/Preferences/com.shoaib.macpulse.plist` 100% untouched.
- **Dependencies:** None
- **Complexity Estimate:** **Small** (~30 lines of Objective-C)
- **Test Plan & Acceptance Criteria:**
  1. Set `defaults write com.shoaib.macpulse keepAwakeWhileCharging -bool YES`.
  2. Run `./build/bin/MacPulse --selftest` and `./build/bin/test_arbiter_exhaustive_matrix`.
  3. Verify `defaults read com.shoaib.macpulse keepAwakeWhileCharging` still returns `1` (`YES`).

---

### Task P0-2: Enable Hardened Runtime, Developer ID Signing, Notarization, and Stapling
- **Finding IDs:** `REL-001`
- **Classification:** Launch requirement
- **Affected Files:**
  - `build.sh`
  - `scripts/package.sh`
- **Expected Outcome:**
  1. `build.sh` always passes `--options runtime` to `codesign` (even for local ad-hoc builds, which supports Hardened Runtime on macOS) and accepts an optional `CODESIGN_IDENTITY="Developer ID Application: ..."` environment variable (defaulting to `-` for local development).
  2. `scripts/package.sh` supports signing `dist/MacPulse.dmg`, submitting to `xcrun notarytool submit --wait` when `NOTARY_PROFILE` is provided, and running `xcrun stapler staple`.
- **Dependencies:** Requires Apple Developer ID Application certificate and `notarytool` keychain profile for public release signing.
- **Complexity Estimate:** **Small** (script changes) + Apple Developer account setup
- **Test Plan & Acceptance Criteria:**
  1. Local verification: `codesign -dvvv build/MacPulse.app` reports `flags=0x10000(runtime)`.
  2. Release verification: `spctl --assess --type execute -vv build/MacPulse.app`, `spctl --assess --type open --context context:primary-signature -vv dist/MacPulse.dmg`, and `xcrun stapler validate dist/MacPulse.dmg` all succeed with exit code `0`.

---

## P1 — Required Before Public Launch (Core Defects & Scope Alignment)

### Task P1-1: Remove Out-of-Scope Independent Display Sleep Prevention (`Allow Display Sleep`)
- **Finding IDs:** `SCOPE-001`, `QA-003`
- **Classification:** Required fix (Canonical Scope §3.5 alignment)
- **Affected Files:**
  - `Sources/MacPulseNative/MPAppSettings.h/.m`
  - `Sources/MacPulseNative/MPPowerManager.h/.m`
  - `Sources/MacPulseNative/MPPriorityArbiter.m`
  - `Sources/MacPulseNative/MPStatusMenuController.m`
  - `Sources/MacPulseNative/MPAboutWindowController.m`
  - `Sources/MacPulseNative/main.m`
  - `Tests/tiers/tier1_features/test_f02_display_sleep.sh` & `Tests/tiers/tier5_adversarial/*`
- **Expected Outcome:** MacPulse exclusively manages `kIOPMAssertionTypePreventUserIdleSystemSleep` and always allows the display to dim and sleep normally. The `"Allow Display Sleep"` menu toggle and `_displayAssertionID` are removed. Removing the second assertion ID also eliminates the dual-property `TOCTOU` race in `MPPowerManager` (`QA-003`).
- **Dependencies:** Task P0-1
- **Complexity Estimate:** **Small**
- **Test Plan & Acceptance Criteria:**
  1. `grep -rn "PreventUserIdleDisplaySleep" Sources/` returns zero matches.
  2. `./build/bin/test_power_manager_stress` passes 10 consecutive runs with 0 invariant violations.
  3. `pmset -g assertions` shows only `PreventUserIdleSystemSleep` when MacPulse is active.

---

### Task P1-2: Fix Battery Safety Cutoff Re-Entrancy, Callback Overwrite, and Missing Cutoff UI
- **Finding IDs:** `POWER-001`, `POWER-002`
- **Classification:** Required fix
- **Affected Files:**
  - `Sources/MacPulseNative/MPPriorityArbiter.h/.m`
  - `Sources/MacPulseNative/MPStatusMenuController.m`
- **Expected Outcome:**
  1. Prevent synchronous recursive re-entrancy in `MPPriorityArbiter.evaluateEffectiveState` when `self.settings.alwaysAwake = NO` is called upon low-battery cutoff (use an `_isEvaluating` re-entrancy guard or internal setter).
  2. Keep `_isBatteryCutoffActive = YES` latched after a low-battery cutoff until either AC power is connected or the user manually toggles `Always Awake` / `Timed Awake`.
  3. Display `"System Status: Normal Sleep (Low Battery Cutoff)"` in `_systemStatusItem.title` when `_arbiter.isBatteryCutoffActive == YES`.
  4. Remove the duplicate `onTick` / `onCompletion` block assignments in `MPStatusMenuController.m` (lines 110–117) so `MPPriorityArbiter` remains the sole owner of `MPTimedAwakeManager` callbacks and forwards state/tick updates cleanly to `MPStatusMenuController`.
- **Dependencies:** Task P1-1
- **Complexity Estimate:** **Small**
- **Test Plan & Acceptance Criteria:**
  1. In `test_arbiter_exhaustive_matrix.m`, keep the `kMPAppSettingsDidChangeNotification` observer **attached** (remove lines 42–45) and verify all state permutations pass.
  2. Verify in Self-Test #5 (`main.m`) with a mock low-battery monitor (`isAC = NO`, `battery = 15`, `threshold = 20`, `alwaysAwake = YES`) that `arbiter.isBatteryCutoffActive` remains `YES` across two consecutive `[arbiter evaluateEffectiveState]` calls.

---

### Task P1-3: Eliminate 1 Hz `SMAppService` IPC and Destructive Submenu Rebuilds During Timed Awake
- **Finding IDs:** `PERF-001`
- **Classification:** Required fix / UX improvement
- **Affected Files:**
  - `Sources/MacPulseNative/MPStatusMenuController.m`
  - `Sources/MacPulseNative/MPTimedAwakeManager.m`
- **Expected Outcome:**
  1. Set `_timer.tolerance = 0.2;` in `MPTimedAwakeManager.m`.
  2. Split `updateUI` into full `updateUI` (called on state changes and `menuWillOpen:`) and lightweight `updateCountdownUI` (called on 1-second timer ticks).
  3. `updateCountdownUI` updates only `_timedRemainingItem.title` in-place (without calling `[_timedAwakeSubmenu removeAllItems]`) and updates `button.title` only when `compactTitle` changes, never calling `[_loginManager refreshStatus]`.
- **Dependencies:** Task P1-2
- **Complexity Estimate:** **Small**
- **Test Plan & Acceptance Criteria:**
  1. Start a Timed Awake session, open the `Timed Awake` submenu, and hover over `"Cancel Timed Session"` for 5 seconds; verify hover highlight is never lost and `Time Remaining: MM:SS` counts down smoothly in place.

---

### Task P1-4: Remove Dead Swift Codebase, Fix `build.sh` Multi-Install Behavior, and Replace Fake E2E Tests
- **Finding IDs:** `ARCH-001`, `REL-002`, `QA-002`
- **Classification:** Required fix
- **Affected Files:**
  - Delete `Sources/MacPulse/`, `Sources/MacPulseKit/`, `Tests/MacPulseKitTests/`, `Package.swift`, and unused Swift template scripts in `tools/`.
  - Update `build.sh` so default `./build.sh` builds only `build/MacPulse.app`, and `./build.sh --install` installs only to `/Applications/MacPulse.app` (removing any duplicate `~/Applications/MacPulse.app`).
  - Rewrite fake Python-mock test cases in `Tests/tiers/` (`test_f04`, `test_f05`, `test_f06`, `test_b01`, `test_b05`, `tier3`, `tier4`) and `main.m` Self-Test #5 to test actual compiled Objective-C classes and real `MacPulse` binary execution.
- **Dependencies:** Tasks P0-1, P1-1, P1-2
- **Complexity Estimate:** **Medium**
- **Test Plan & Acceptance Criteria:**
  1. Zero `.swift` files remain in `Sources/` or `Tests/`.
  2. `./build.sh` does not touch `/Applications` or `~/Applications` unless `--install` is passed.
  3. 100% of test cases in `Tests/run_e2e_tests.sh` execute compiled Objective-C/app binaries with zero inline Python mocks and zero unconditional `test_pass` no-ops.

---

## P2 — Important Improvements (Reliability, UX, Docs, Release Hygiene)

| Task ID | Finding IDs | Classification | Target Files | Summary of Work & Acceptance Criteria | Est. Size |
|---|---|---|---|---|---|
| **Task P2-1** | `POWER-003`, `POWER-004` | Required fix | `MPTimedAwakeManager.m`, `MPPowerSourceMonitor.m`, `MPPriorityArbiter.m` | Switch timer deadline calculation from `[NSDate timeIntervalSinceReferenceDate]` to `CACurrentMediaTime()` (monotonic); observe `NSWorkspaceDidWakeNotification` to refresh power/timer state on wake; remove `_isStopped = NO` from `handleHardwareNotification` and make `test_debounce_stress` Step 3.2b fail on nonzero callback count. | Small |
| **Task P2-2** | `SCOPE-002` | UX improvement | `MPAppSettings.h/.m`, `MPStatusMenuController.m`, `MPPriorityArbiter.m` | Clamp `batterySafetyThreshold` to `[10, 50]` (or `[10, 80]` if retained by PO); add `batteryProtectionEnabled` toggle (default `YES`); group Battery Protection under an `Always Awake` / `Advanced` submenu; cancel active Timed Awake when Always Awake is enabled (and vice versa). | Small |
| **Task P2-3** | `UX-001`, `UX-002` | UX improvement | `MPPriorityArbiter.m`, `MPStatusMenuController.m` | Change Smart Awake `_statusSummaryString` from `@"Awake"` to `@"Smart Awake"` (fixing `"System Status: Awake (Awake)"`); standardize `"Normal Sleep"` spelling; show actionable `NSAlert` with button to open `SMAppService openSystemSettingsLoginItems` when Login Item registration requires user approval. | Small |
| **Task P2-4** | `UX-003`, `BRAND-001` | Launch requirement | `Icon/AppIcon.png`, `Icon/AppIcon.icns`, `Info.plist.in` | Regenerate `AppIcon.png` and `AppIcon.icns` without the embedded `"MacPulse"` text wordmark and without bottom-edge white fringe pixels; review `"MacPulse"` vs `"PulseAwake"` naming with Product Owner. | Small |
| **Task P2-5** | `REL-003`, `DOC-001` | Launch requirement | `LICENSE`, `Info.plist.in`, `README.md`, `AI_TESTING_GUIDE.md`, `CLAUDE.md`, `.github/workflows/ci.yml` | Add MIT `LICENSE` file; put `__BUILD__` in `Info.plist.in`; package zips with `ditto -c -k --keepParent`; fix `./tests/` -> `./Tests/` and assertion strings in docs; add end-user DMG install, uninstall, and sleep limitation docs; commit all tracked files to Git; add GitHub Actions CI workflow. | Small |

---

## P3 & P4 — Polish and Future Opportunities

| Task ID | Priority | Finding IDs | Classification | Summary |
|---|---|---|---|---|
| **Task P3-1** | **P3** | `SEC-001` | UX / Reliability polish | Add `<key>LSMultipleInstancesProhibited</key><true/>` to `Info.plist.in`, check `[NSRunningApplication runningApplicationsWithBundleIdentifier:]` on startup, and remove `killall MacPulse` from `test_pmset_lifecycle.sh`. |
| **Task P3-2** | **P3** | `UX-004` | UX / Accessibility polish | Add `.toolTip` strings to menu items and replace `[NSApp activateIgnoringOtherApps:YES]` with `@available(macOS 14.0, *)` `[NSApp activate]`. |
| **Task P4-1** | **P4** | — | Optional enhancement (Post-v1.0) | Add a Homebrew Cask formula (`Casks/macpulse.rb`) once a notarized GitHub Release DMG URL and SHA-256 checksum are published. |
| **Task P4-2** | **P4** | — | **Do not add** | Do **not** add per-app triggers, Wi-Fi triggers, mouse movement simulation, or closed-clamshell private-API hacks; keep MacPulse minimal, safe, and zero-config. |
