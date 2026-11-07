# MacPulse — AI Testing & QA Guide

This package contains the precompiled native macOS application bundle, CLI test binary, and automated test suites for **MacPulse** ("Your Mac. Always Ready.").

Target Platform: macOS 13.0+ (Ventura, Sonoma, Sequoia)  
Architecture: Universal Mach-O Fat Binary (`arm64` Apple Silicon + `x86_64` Intel)

---

## 1. Quick Automated Test Commands

### A. Run In-App Headless Self-Tests (10 Checks)
Execute deterministic internal logic tests using an isolated ephemeral suite (`com.shoaib.macpulse.tests`) without modifying production user preferences:
```bash
./build/bin/MacPulse --selftest
```
Expected output:
- `[PASS] MPAppSettings initialization, defaults, and boundary clamping [10-80%] (isolated suite)`
- `[PASS] MPPowerManager dual assertion lifecycle and idempotency`
- `[PASS] MPPowerManager double-release safety (no 0xe00002c2)`
- `[PASS] MPPriorityArbiter hierarchy (Always Awake > Timed Awake > Smart Awake > Disabled)`
- `[PASS] MPPriorityArbiter battery safety cutoff logic`
- `[PASS] MPPowerSourceMonitor desktop Mac detection`
- `[PASS] MPTimedAwakeManager sleep-aware countdown (mach_continuous_time) and wake reconciliation`
- `[PASS] MPPriorityArbiter dynamic Timed Awake manager integration and fallback`
- `[PASS] MPAboutWindowController utility panel instantiation and feature coverage`
- `[PASS] Clean teardown and assertion release`
- Exit code: `0`

### B. Run Tier 1 Automated Regression Suites (10 Suites, 52 Test Cases)
Run the automated regression suites across all features and lifecycles:
```bash
./Tests/run_e2e_tests.sh --tier 1
```
Duration: ~25-30 seconds  
Expected result: `10 Passed, 0 Failed, 52 Passed, 0 Failed`.

#### Reconciled Test Classification Breakdown (QA-002)
- **14 True E2E Tests:** Execute live compiled binaries and assert kernel power assertions via `pmset -g assertions`.
- **14 Integration Tests:** Exercise defaults persistence, AppKit/Cocoa APIs, and CLI argument parsing.
- **17 Simulated/Mock-Only Tests:** Fast algorithmic simulations validating mathematical edge cases across Tiers 1, 3, and 4 (reconciling the 14 vs 17 mock-test count discrepancy).
- **9 Static/Build Checks:** Verify architectures (`lipo`), packaging, and `Info.plist` metadata.
- **1 Hardware Telemetry Check:** Real-time battery status detection.

### C. Run Adversarial Stress Test Suite (Tier 5)
Run stress tests covering multi-threading (5,000 operations across 10 threads), 3,840-state exhaustive matrix validation, notification debounce coalescing, and kernel `pmset` lifecycle verification:
```bash
./Tests/tiers/tier5_adversarial/run_adversarial_tests.sh
```

---

## 2. Kernel Power Assertion Verification (`pmset`)

MacPulse uses Apple's native IOKit IOPMAssertion APIs. Verify live kernel assertions via macOS `pmset`:

### Test Smart Awake Assertion:
```bash
# 1. Set Smart Awake in isolated test domain
export MACPULSE_DEFAULTS_SUITE="com.shoaib.macpulse.tests"
defaults write com.shoaib.macpulse.tests keepAwakeWhileCharging -bool YES
defaults write com.shoaib.macpulse.tests alwaysAwake -bool NO

# 2. Launch MacPulse test instance
./build/bin/MacPulse &
PID=$!

# 3. Check active kernel assertions (when plugged into AC power)
pmset -g assertions | grep "pid $PID"
```
Expected result:
`PreventUserIdleSystemSleep "MacPulse: Keeping system awake while charging"` is active.

### Test Keep Display On:
```bash
# Enable Keep Display On
defaults write com.shoaib.macpulse.tests keepDisplayAwake -bool YES
defaults write com.shoaib.macpulse.tests alwaysAwake -bool YES

# Launch MacPulse
./build/bin/MacPulse &
PID=$!

# Check kernel assertions
pmset -g assertions | grep "pid $PID"
```
Expected result:
Both `PreventUserIdleSystemSleep` AND `PreventUserIdleDisplaySleep` are held.

### Test Clean Teardown (Zero Assertion Leaks):
```bash
# Graceful termination
kill -TERM "$PID"
sleep 0.5

# Check assertions
pmset -g assertions | grep "pid $PID"
```
Expected result:
Output is completely empty. Zero dangling assertions.

---

## 3. Package Contents

- `MacPulse.app`: Standalone application bundle with native AppIcon and LaunchServices configuration.
- `MacPulse.dmg`: Read-only compressed release installer with `/Applications` drag-and-drop link.
- `build/bin/MacPulse`: Universal command-line executable.
- `Tests/`: Full bash test harness and test suites.
- `AI_TESTING_GUIDE.md`: This testing guide.
- `docs/LEGAL.md`: Legal notices and trademark acknowledgments.
