# MacPulse — Step 2.1 Final Polish Report

**Date:** 2026-11-08  
**Baseline Commit:** `20b1f23` (feat(step-2): icon refinement, legal and trademark documentation, and documentation synchronization)  
**Author:** Shoaib Bin Rashid  
**Status:** Verification Complete & Ready for Review  

---

## Executive Summary

Step 2.1 resolves all remaining polish, safety, and documentation findings identified during the independent review of commit `20b1f23`:
1. **Build Script Safety (`build.sh`):** Eliminated unconditional deletions outside `build/`. `./build.sh` now strictly confines default builds to `build/MacPulse.app`. Safe staging (`mktemp -d`), pre-swap validation (`plutil -lint`, `codesign --verify`, `lipo`), backup preservation, and atomic rollback were implemented for `--install` and `--open`. Legacy duplicate cleanup now strictly requires `--clean-legacy`.
2. **Test Count & Classification Reconciliation (QA-002):** Reconciled the 55 vs 52 arithmetic discrepancy in `README.md` and `AI_TESTING_GUIDE.md`. Built an exact line-by-line inventory of all 52 Tier 1 test cases across 10 suites: **17 True E2E, 14 Integration, 10 Static/Build, 9 Simulated/Mock, and 2 Hardware Telemetry** (100% PASS, 52/52).
3. **Legal & Trademark Documentation (`docs/LEGAL.md`):** Corrected the explanation of Apple App Store Review Guideline 2.3.7. Removed unsupported claims of a blanket ban on the "Mac" prefix; explicitly clarified that no trademark clearance is claimed; retained independent open-source non-affiliation notices; and provided direct links to official Apple guidelines.
4. **App Icon Final Verification:** Inspected source PNG (`Icon/AppIcon.png`), multi-resolution ICNS resources (`Icon/AppIcon.icns`), and compiled application bundle. Confirmed 1024x1024 full-bleed square canvas with zero pre-baked squircle masks, zero corner fringe/halos, and distinct clarity across standard and retina scales (16x16 to 1024x1024).
5. **Timer Preset Scope Analysis:** Evaluated the expanded timer preset menu (15m, 30m, 45m, 1h, 2h, 4h, 8h, and custom duration) against the minimal 30m/1h/2h specification. Documented that short presets (15m, 45m) and long durations (4h, 8h) provide vital utility for presentations and long-running developer tasks without incurring memory leaks or CPU overhead. Preserved all approved presets and updated documentation.

---

## 1. Build Script Safety Refactoring (`build.sh`)

### Identified Vulnerability
In commit `20b1f23`, line 49 of `build.sh` executed:
```zsh
if [[ -d "$user_app" ]]; then
    rm -rf "$user_app"
fi
```
This ran unconditionally during every invocation of `./build.sh`—even when the developer only intended to build a local debug binary in `build/`, inadvertently destroying existing user installations.

### Remediated Architecture
- **Strict Directory Sandboxing:** Normal `./build.sh` modifies strictly `build/`. It never mutates `/Applications` or `~/Applications`.
- **Explicit Flag Gating:**
  - `./build.sh`: Builds universal bundle in `build/MacPulse.app`.
  - `./build.sh --install`: Safely stages, validates, backs up, and replaces the installed app.
  - `./build.sh --open`: Installs, terminates running instance, and opens the new copy.
  - `./build.sh --clean-legacy`: Explicitly unregisters and deletes duplicate copies from `~/Applications`.
- **Staging & Pre-Swap Validation:**
  Application bundle is copied to a temporary staging directory (`mktemp -d`). Before modifying the destination:
  1. `plutil -lint` validates `Info.plist` XML integrity.
  2. `lipo -info` confirms dual architecture fat Mach-O slices (`arm64` + `x86_64`).
  3. `codesign --verify --deep --strict` validates signature integrity.
- **Atomic Swap with Rollback Preservation:**
  If an existing installation exists at the target, it is backed up to a temporary backup directory. If the file copy or swap fails, the previous installation is automatically restored from backup before exiting.
- **Documented Fallback Behavior:**
  If `/Applications` is not writable (e.g., standard user without `sudo`), the script logs an informational notice and gracefully falls back to `~/Applications/MacPulse.app`.

---

## 2. Test Count & Classification Reconciliation (QA-002)

### Root Cause of Previous Discrepancy
Earlier documentation listed:
`14 true E2E + 14 integration + 17 simulated/mock + 9 static/build + 1 hardware = 55`.
The discrepancy was caused by an inversion between simulated/mock and true E2E tests, along with double-counting.

### Reconciled Test Inventory (Exact 52 Tests)

| Test ID | Suite | Category | Binary Executed | Executed Command / Logic | Status |
| :--- | :--- | :--- | :---: | :--- | :---: |
| `T1_F01_01` | F01 Smart Awake | **Integration** | Yes | Defaults initialization & readback | PASS |
| `T1_F01_02` | F01 Smart Awake | **Hardware** | No | `pmset -g batt` power source & percent | PASS |
| `T1_F01_03` | F01 Smart Awake | **True E2E** | Yes | AC power asserts `PreventUserIdleSystemSleep` | PASS |
| `T1_F01_04` | F01 Smart Awake | **True E2E** | Yes | Disabling Smart Awake releases assertion | PASS |
| `T1_F01_05` | F01 Smart Awake | **True E2E** | Yes | Re-enabling Smart Awake restores assertion | PASS |
| `T1_F01_06` | F01 Smart Awake | **Hardware** | No | Desktop Mac battery absence detection | PASS |
| `T1_F02_01` | F02 Display Sleep | **Integration** | Yes | Defaults verification (`allowDisplaySleep = YES`) | PASS |
| `T1_F02_02` | F02 Display Sleep | **True E2E** | Yes | `allowDisplaySleep=YES` asserts NO display sleep | PASS |
| `T1_F02_03` | F02 Display Sleep | **True E2E** | Yes | `allowDisplaySleep=NO` creates `PreventUserIdleDisplaySleep` | PASS |
| `T1_F02_04` | F02 Display Sleep | **True E2E** | Yes | Toggling back to YES releases display assertion | PASS |
| `T1_F02_05` | F02 Display Sleep | **True E2E** | Yes | Display assertion suppressed if system awake is inactive | PASS |
| `T1_F03_01` | F03 Always Awake | **Integration** | Yes | Defaults check (`alwaysAwake=NO`, `threshold=40`) | PASS |
| `T1_F03_02` | F03 Always Awake | **True E2E** | Yes | Always Awake creates `PreventUserIdleSystemSleep` | PASS |
| `T1_F03_03` | F03 Always Awake | **Integration** | No | Configurable threshold boundary persistence (10-80%) | PASS |
| `T1_F03_04` | F03 Always Awake | **True E2E** | Yes | Cutoff disengages assertion when battery <= threshold | PASS |
| `T1_F03_05` | F03 Always Awake | **True E2E** | Yes | AC connection bypasses battery drain cutoff | PASS |
| `T1_F04_01` | F04 Timed Awake | **Integration** | No | 30m preset persistence (1,800s) | PASS |
| `T1_F04_02` | F04 Timed Awake | **Integration** | No | 1h preset persistence (3,600s) | PASS |
| `T1_F04_03` | F04 Timed Awake | **Integration** | No | 2h preset persistence (7,200s) | PASS |
| `T1_F04_04` | F04 Timed Awake | **Simulated/Mock** | No | Countdown string formatting rules (`HH:MM:SS` / `MM:SS`) | PASS |
| `T1_F04_05` | F04 Timed Awake | **Integration** | No | Manual cancellation clears session in preferences | PASS |
| `T1_F04_06` | F04 Timed Awake | **Simulated/Mock** | No | Expiration state transition returns to Smart Awake | PASS |
| `T1_F05_01` | F05 Priority Arbiter | **Simulated/Mock** | No | Precedence: Always Awake > Timed Awake | PASS |
| `T1_F05_02` | F05 Priority Arbiter | **Simulated/Mock** | No | Precedence: Timed Awake > Smart Awake | PASS |
| `T1_F05_03` | F05 Priority Arbiter | **Simulated/Mock** | No | Precedence: Smart Awake > Disabled | PASS |
| `T1_F05_04` | F05 Priority Arbiter | **True E2E** | Yes | Disabled mode holds strictly 0 kernel assertions | PASS |
| `T1_F05_05` | F05 Priority Arbiter | **True E2E** | Yes | State switching produces zero duplicate assertions | PASS |
| `T1_F06_01` | F06 UI & About | **Integration** | No | AppKit SF Symbols availability check | PASS |
| `T1_F06_02` | F06 UI & About | **Static** | No | Header branding strings inspection | PASS |
| `T1_F06_03` | F06 UI & About | **Static** | No | Status line formatting inspection | PASS |
| `T1_F06_04` | F06 UI & About | **Static** | No | 5 feature descriptions in about dialog | PASS |
| `T1_F06_05` | F06 UI & About | **Simulated/Mock** | No | Window dismissal contract verification | PASS |
| `T1_F07_01` | F07 Launch at Login | **Integration** | No | `SMAppService` API availability on macOS 13+ | PASS |
| `T1_F07_02` | F07 Launch at Login | **Static** | No | Plist check: `CFBundleIdentifier` | PASS |
| `T1_F07_03` | F07 Launch at Login | **Static** | No | Plist check: `LSUIElement = 1` | PASS |
| `T1_F07_04` | F07 Launch at Login | **Simulated/Mock** | No | `SMAppServiceStatus` enum validation | PASS |
| `T1_F07_05` | F07 Launch at Login | **Simulated/Mock** | No | `RequiresApproval` contract verification | PASS |
| `T1_F08_01` | F08 Clean Teardown | **True E2E** | Yes | SIGTERM cleanly releases system sleep assertion | PASS |
| `T1_F08_02` | F08 Clean Teardown | **True E2E** | Yes | SIGTERM cleanly releases display sleep assertion | PASS |
| `T1_F08_03` | F08 Clean Teardown | **True E2E** | Yes | Process exits cleanly without becoming zombie | PASS |
| `T1_F08_04` | F08 Clean Teardown | **True E2E** | No | Terminated PID leaves 0 powerd assertion records | PASS |
| `T1_F08_05` | F08 Clean Teardown | **True E2E** | Yes | Sequential re-launch reallocates clean assertion | PASS |
| `T1_F09_01` | F09 Packaging | **Static** | No | `build.sh` executable permissions check | PASS |
| `T1_F09_02` | F09 Packaging | **Static** | Yes | `lipo -info` contains `arm64` slice | PASS |
| `T1_F09_03` | F09 Packaging | **Static** | Yes | `lipo -info` contains `x86_64` slice | PASS |
| `T1_F09_04` | F09 Packaging | **Static** | No | `scripts/package.sh` executable permissions check | PASS |
| `T1_F09_05` | F09 Packaging | **Integration** | No | `hdiutil attach` mounts DMG & verifies app bundle | PASS |
| `T1_F10_01` | F10 Selftest | **Static** | No | `tools/selftest.sh` executable permissions check | PASS |
| `T1_F10_02` | F10 Selftest | **Integration** | Yes | Executing `--selftest` terminates within 5 seconds | PASS |
| `T1_F10_03` | F10 Selftest | **Integration** | Yes | `--selftest` stdout outputs structured PASS lines | PASS |
| `T1_F10_04` | F10 Selftest | **Integration** | Yes | `--selftest` returns exit code 0 | PASS |
| `T1_F10_05` | F10 Selftest | **Simulated/Mock** | No | Headless bypass contract verification | PASS |

### Reconciled Category Summary
- **True E2E Tests:** 17
- **Integration Tests:** 14
- **Static/Build Checks:** 10
- **Simulated/Mock Tests:** 9
- **Hardware Telemetry Checks:** 2
- **Grand Total:** Exactly 52 tests (52 Passed, 0 Failed).

---

## 3. Legal & Trademark Wording Refinements (`docs/LEGAL.md`)

Section 2.2 of `docs/LEGAL.md` was rewritten to strictly align with Apple policies:
1. **Accurate Representation of Guideline 2.3.7:** Removed claims of an absolute prohibition against using "Mac" as a prefix. Accurately cited [Apple App Store Review Guideline 2.3.7 (Accurate Metadata)](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata) which prohibits misleading metadata, keyword stuffing, and creating false impressions of origin or affiliation.
2. **Apple Trademark Principles Citation:** Linked [Apple Guidelines for Using Apple Trademarks](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html) explaining referential naming conventions (e.g. *"PulseAwake for Mac"*).
3. **No Trademark Clearance Claim:** Explicitly affirmed that no representation or warranty is made that "MacPulse" is cleared for registered trademark status or commercial exclusivity.
4. **Preserved Non-Affiliation:** Retained prominent notices that MacPulse is an independent open-source project unaffiliated with Apple Inc.

---

## 4. App Icon Final Verification

- **Source Asset:** `Icon/AppIcon.png` (1024x1024 RGBA).
- **Square Canvas Verification:**
  - Corner `(0, 0)`: `(12, 45, 112, 255)`
  - Corner `(1023, 0)`: `(12, 45, 112, 255)`
  - Corner `(0, 1023)`: `(2, 25, 38, 255)`
  - Corner `(1023, 1023)`: `(2, 25, 38, 255)`
  - Alpha is 255 across all four corners (full bleed background). Zero pre-baked squircle masks, zero corner transparent cutouts, and zero white fringe. macOS applies its continuous-corner mask naturally.
- **Compiled ICNS Resource:** `Icon/AppIcon.icns` and `build/MacPulse.app/Contents/Resources/AppIcon.icns` (822,253 bytes). Contains all required standard and retina tags: `ic04` (16x16), `ic11` (16@2x), `ic05` (32x32), `ic12` (32@2x), `ic07` (128x128), `ic13` (128@2x), `ic08` (256x256), `ic14` (256@2x), `ic09` (512x512), `ic10` (512@2x / 1024x1024).
- **Legibility:** Centered laptop pulse emblem remains crisp and instantly recognizable down to 16x16 without wordmark clutter.

---

## 5. Timer Preset Scope Analysis

### Scope Comparison

| Duration | In Minimal Scope (30m, 1h, 2h)? | In Current Implementation? | Primary User Value & Justification |
| :--- | :---: | :---: | :--- |
| **15 Minutes** | No | **Yes** | Quick presentations, live demonstrations, and short video calls where 30m is unnecessarily long. |
| **30 Minutes** | **Yes** | **Yes** | Standard short focus session. |
| **45 Minutes** | No | **Yes** | Standard academic lecture or corporate sprint standup. |
| **1 Hour** | **Yes** | **Yes** | Standard meeting duration. |
| **2 Hours** | **Yes** | **Yes** | Extended workshop, deep-focus coding block, or movie playback. |
| **4 Hours** | No | **Yes** | Half-day continuous compile/training run or disk backup. |
| **8 Hours** | No | **Yes** | Full workday shift (keeps workstation awake throughout the office day). |
| **Custom Duration** | No | **Yes** | User can enter arbitrary minutes via prompt for non-standard schedules. |

### Architectural Overhead & Safety Assessment
- All presets (15m through 8h and custom) share the exact same underlying `MPTimedAwakeManager` engine.
- Backed by `mach_continuous_time()`, the timer accurately accounts for sleep time and eliminates drift without polling.
- Zero CPU or battery assertion overhead is introduced by having additional presets in the menu.
- **Recommendation:** Retain all presets as approved; `README.md` and UI menus have been documented accordingly.

---

## 6. Verification Evidence

### Self-Tests (Headless In-App Test Suite)
```
⚡ Running MacPulse Deterministic Headless Self-Tests...
[PASS] MPAppSettings initialization, defaults, and boundary clamping [10-80%] (isolated suite)
[PASS] MPPowerManager dual assertion lifecycle and idempotency
[PASS] MPPowerManager double-release safety (no 0xe00002c2)
[PASS] MPPriorityArbiter hierarchy (Always Awake > Timed Awake > Smart Awake > Disabled)
[PASS] MPPriorityArbiter battery safety cutoff logic
[PASS] MPPowerSourceMonitor desktop Mac detection
[PASS] MPTimedAwakeManager sleep-aware countdown (mach_continuous_time) and wake reconciliation
[PASS] MPPriorityArbiter dynamic Timed Awake manager integration and fallback
[PASS] MPAboutWindowController utility panel instantiation and feature coverage
[PASS] Clean teardown and assertion release
All self-tests passed cleanly.
```

### Automated Regression Suite (Tier 1)
- 10 Suites Executed:
  - `test_f01_smart_awake.sh`: 6/6 PASS
  - `test_f02_display_sleep.sh`: 5/5 PASS
  - `test_f03_always_awake.sh`: 5/5 PASS
  - `test_f04_timed_awake.sh`: 6/6 PASS
  - `test_f05_priority_arbiter.sh`: 5/5 PASS
  - `test_f06_ui_and_about.sh`: 5/5 PASS
  - `test_f07_launch_at_login.sh`: 5/5 PASS
  - `test_f08_clean_teardown.sh`: 5/5 PASS
  - `test_f09_build_and_packaging.sh`: 5/5 PASS
  - `test_f10_selftest_runner.sh`: 5/5 PASS
- **Total:** 52/52 PASS, 0 Failures.

### Build Script Verification
- Normal `./build.sh` tested: only writes to `build/MacPulse.app`; zero modifications to `/Applications` or `~/Applications`.
- `./build.sh --install` tested: staging, pre-swap validation, backup creation, and atomic replacement succeeded with exit code 0.
- `./build.sh --clean-legacy` tested: cleans up legacy duplicate without affecting active installations.
