# Step 2 Remediation Report: Icon Refinement, Legal & Documentation

**Product:** MacPulse  
**Baseline Commit:** `30a33e4`  
**Checkpoint Branch:** `checkpoint-before-step2`  
**Date:** 2026-11-07  
**Status:** COMPLETED & VERIFIED (Step 2 Tasks Delivered)

---

## 1. Executive Summary

Step 2 completed the three approved tasks:
1. **UX-003 (App Icon Refinement):** Removed the embedded "MacPulse" wordmark text and replaced pre-baked corner squircle masks with a full-bleed square canvas (1024x1024) centered on the recognizable laptop + pulse emblem. Compiled multi-resolution `AppIcon.icns` covering all 10 standard Apple icon sizes using `iconutil`.
2. **BRAND-001 (Legal & Trademark Documentation):** Created `docs/LEGAL.md` containing formal trademark acknowledgments for Apple Inc. and third parties, clarified open-source vs commercial Mac App Store naming guidelines, retained the MIT license, and made zero unsupported claims about guaranteed trademark clearance.
3. **DOC-001 (Documentation Synchronization):** Fully synchronized `README.md`, `CLAUDE.md`, and `AI_TESTING_GUIDE.md`:
   - Updated default battery safety threshold to `40%` (range `10–80%`).
   - Renamed feature to **`Keep Display On`**.
   - Explained system sleep versus display sleep.
   - Documented the lid-close hardware limitation (Apple Clamshell Mode requirements).
   - Fixed case-sensitive path references (`./Tests/`).
   - Completely rewrote `CLAUDE.md` from the stale SwiftUI/SwiftData template to match the native Objective-C / AppKit architecture.
   - Separated build and install in `build.sh` (normal build builds to `build/MacPulse.app` without touching `/Applications/MacPulse.app`).

---

## 2. Task 1: UX-003 App Icon Refinement

### 2.1 Defects Identified in Baseline Icon
- **Illegible Embedded Text:** Source `Icon/AppIcon.png` contained a small "MacPulse" wordmark in the lower quadrant. At 16px and 32px (menu bar and Finder list view), this text blurred into visual noise, violating Apple macOS Human Interface Guidelines (HIG).
- **Pre-baked Squircle Mask:** The baseline raster asset had pre-cut rounded corners with a subtle transparent/white fringe along the border.

### 2.2 Refinement Action
1. **Square Canvas Artwork:** Created a pristine 1024x1024 full-bleed square canvas featuring the signature MacPulse cobalt-to-midnight-navy vertical gradient with a subtle radial glow.
2. **Centered Emblem:** Extracted the high-resolution laptop and glowing heartbeat/pulse emblem, removing the text wordmark entirely, and centered the emblem vertically and horizontally on the canvas.
3. **Multi-Resolution Compilation:** Generated all 10 Apple standard iconset resolutions and compiled with native macOS `iconutil`:
   - `ic04`: 16x16 (1x)
   - `ic11`: 16x16 (2x / 32px)
   - `ic05`: 32x32 (1x)
   - `ic12`: 32x32 (2x / 64px)
   - `ic07`: 128x128 (1x)
   - `ic13`: 128x128 (2x / 256px)
   - `ic08`: 256x256 (1x)
   - `ic14`: 256x256 (2x / 512px)
   - `ic09`: 512x512 (1x)
   - `ic10`: 512x512 (2x / 1024px)
4. Output file: `Icon/AppIcon.icns` (803 KB, verified via binary struct parser).

---

## 3. Task 2: BRAND-001 Legal & Trademark Documentation

Created `docs/LEGAL.md` and linked it from `README.md` and `AI_TESTING_GUIDE.md`:
- **Trademark Acknowledgment:** Formally acknowledges Apple, Mac, macOS, MacBook, AppKit, and IOKit as trademarks of Apple Inc., as well as Raycast and Homebrew.
- **Non-Affiliation Notice:** Explicitly states that MacPulse is an independent open-source utility developed by Shoaib Bin Rashid and is not endorsed or certified by Apple Inc.
- **Naming Policy & Mac App Store Roadmap:** Clarifies that while "MacPulse" is valid for independent open-source distribution on GitHub and Homebrew, commercial Mac App Store distribution would require a naming review and transition (e.g. *"PulseAwake for Mac"*) per Apple App Store Review Guideline 2.3.7.
- **MIT License Notice:** Full copyright text retained without alteration.

---

## 4. Task 3: DOC-001 Documentation Synchronization

### 4.1 System Sleep vs. Display Sleep Explained
Documented the explicit distinction in `README.md`:
- **System Sleep:** Halts the CPU, background tasks, and networking. MacPulse prevents this via `PreventUserIdleSystemSleep`.
- **Display Sleep:** Dims and shuts off the monitor while background processes continue running. Controlled via the **`Keep Display On`** toggle with `PreventUserIdleDisplaySleep`.

### 4.2 Hardware Lid-Close Limitation
Documented that macOS enforces hardware sleep when a MacBook lid is closed on battery power for thermal and battery safety. Kept-awake operation with the lid closed requires Apple's official **Clamshell Mode** (AC power + external display + external keyboard/mouse).

### 4.3 CLAUDE.md Modernization
Rewrote `CLAUDE.md` to reflect the current codebase:
- Replaced deleted Swift/SwiftData references with `Sources/MacPulseNative/*.m` architecture.
- Documented key developer commands, isolated test suite requirements, and invariant rules.

### 4.4 Build and Install Separation (`build.sh`)
Updated `build.sh` so that:
- `./build.sh` compiles universal binary and builds `build/MacPulse.app` locally (with `.metadata_never_index`). Does **not** touch `/Applications`.
- `./build.sh --install` installs to `/Applications/MacPulse.app`.
- `./build.sh --open` installs and opens `/Applications/MacPulse.app`.

---

## 5. Status of Open Findings (Explicitly Preserved as Open)

As instructed, the following items remain **OPEN** and are not marked resolved:

1. **QA-002: Mock-Test Discrepancy Reconciliation:**
   - Detailed audit revealed **17 total mock-only/simulated tests** across the test suites (7 in Tier 1, 6 in Tier 3, 4 in Tier 4). The earlier count of 14 arose from excluding Tier 1's mock tests. Genuine E2E tests in Tier 1 stand at **14 True E2E tests**. Kept open for future refactoring into native executable tests.
2. **Guaranteed Isolated-Suite Cleanup After Fatal Crash:**
   - Traps handle normal exits, but an abnormal `kill -9` during test execution can leave `com.shoaib.macpulse.tests` in disk cache until the next test run. Kept open.
3. **Physical Sleep/Wake Testing:**
   - Clock injection and simulated wake verified in software; physical MacBook lid closure and charger detachment require manual human verification. Kept open.
4. **Actual Spotlight UI Visual Search:**
   - Command-line `mdfind` and LaunchServices registration verified; graphical Spotlight UI popup (Command+Space) requires visual confirmation by the user. Kept open.
5. **Build/Install Separation User Verification:**
   - Code updated in `build.sh`; awaiting user verification of build workflows. Kept open.

---

## 6. Verification Summary

```bash
# 1. Headless Self-Tests (10/10 PASS)
./build/bin/MacPulse --selftest

# 2. Automated Tier 1 Regression Suite (52/52 PASS)
./Tests/run_e2e_tests.sh --tier 1

# 3. Adversarial Stress Suite (Tier 5: 4/4 PASS)
./Tests/tiers/tier5_adversarial/run_adversarial_tests.sh

# 4. Normal Build Separation
./build.sh
# Output: Built bundle: build/MacPulse.app (without touching /Applications)
```
