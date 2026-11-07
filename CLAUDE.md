# MacPulse Developer Reference

A native macOS menu bar keep-awake utility (`LSUIElement = true`) implemented in Objective-C, AppKit, and Apple IOKit. It runs locally with no external daemon, server, or cloud dependencies.

## Architecture & Codebase Layout

- `Sources/MacPulseNative/` — Core Objective-C engine:
  - `main.m`: Application delegate, single-instance file lock guard (`SEC-001`), CLI flag parser (`--selftest`, `--help`), and headless self-test runner.
  - `MPCommon.h`: Common enumerations (`MPActiveMode`), battery threshold constants (`kMPBatteryThresholdMin 10`, `Max 80`, `Default 40`).
  - `MPAppSettings.h/.m`: Persistent user defaults with isolated suite support (`MACPULSE_DEFAULTS_SUITE`), boundary clamping, and notification broadcasting.
  - `MPPowerManager.h/.m`: Thread-safe (`os_unfair_lock`) IOKit power assertion manager (`PreventUserIdleSystemSleep`, `PreventUserIdleDisplaySleep`).
  - `MPPowerSourceMonitor.h/.m`: Zero-polling event-driven power source monitor (`IOPSNotificationCreateRunLoopSource`) with monotonic generation token and debounce protection.
  - `MPPriorityArbiter.h/.m`: Deterministic priority arbitration engine (Always Awake > Timed Awake > Smart Awake > Disabled) and battery threshold cutoff evaluator.
  - `MPTimedAwakeManager.h/.m`: Sleep-aware continuous countdown timer (`mach_continuous_time`) with clock-injection provider and wake reconciliation.
  - `MPStatusMenuController.h/.m`: AppKit menu bar controller (`NSStatusItem`), custom duration prompt, tooltips, and `SMAppService` login item integration.
  - `MPAboutWindowController.h/.m`: Floating utility panel explaining features and controls.
- `Icon/` — Application icon assets:
  - `AppIcon.png`: 1024x1024 square source artwork without embedded text.
  - `AppIcon.icns`: Multi-resolution icon compiled via `iconutil`.
- `Tests/` — Automated test suites:
  - `run_e2e_tests.sh`: Automated test runner across feature tiers.
  - `tiers/tier1_features/`: Feature verification scripts (`test_f01` through `test_f10`).
  - `tiers/tier5_adversarial/`: Concurrency, 3,840-state matrix, debounce, and kernel `pmset` lifecycle harnesses.
- `build.sh` — Universal Mach-O compiler (`arm64` + `x86_64`) and packaging script.

## Common Developer Commands

- **Build Local Bundle:**
  ```bash
  ./build.sh
  ```
- **Install to `/Applications`:**
  ```bash
  ./build.sh --install
  ```
- **Build, Install, and Open:**
  ```bash
  ./build.sh --open
  ```
- **Run Headless Self-Tests:**
  ```bash
  ./build/bin/MacPulse --selftest
  ```
- **Run Tier 1 Regression Tests:**
  ```bash
  ./Tests/run_e2e_tests.sh --tier 1
  ```
- **Run Tier 5 Adversarial Stress Tests:**
  ```bash
  ./Tests/tiers/tier5_adversarial/run_adversarial_tests.sh
  ```
- **Inspect Kernel Assertions:**
  ```bash
  pmset -g assertions | grep MacPulse
  ```

## Key Rules & Invariants

1. **Test Preference Isolation:** Never mutate `com.shoaib.macpulse` during automated tests. Always use `MACPULSE_DEFAULTS_SUITE=com.shoaib.macpulse.tests` or `[MPAppSettings sharedSettingsWithSuiteName:]`.
2. **Single Instance Invariant:** Only one GUI menu bar instance may run at any time (`LSMultipleInstancesProhibited` + atomic `flock` guard). Secondary launches must activate the existing instance and exit with code 0.
3. **Continuous Sleep-Aware Time:** All timer deadlines must use `mach_continuous_time()` so that time spent in system sleep counts toward session expiry.
4. **Display Sleep Separation:** Keep Display On is strictly decoupled from system keep-awake. Display sleep assertion is only asserted when system sleep is prevented AND user enables Keep Display On AND battery is above threshold.
5. **No Dock Icon:** Keep `LSUIElement = true` in `Info.plist.in`. MacPulse is strictly a menu bar accessory.
