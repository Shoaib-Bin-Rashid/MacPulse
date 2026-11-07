# MacPulse — AI Testing & QA Guide

This package contains the precompiled native macOS application bundle, CLI test binary, and automated test suites for **MacPulse** ("Your Mac. Always Ready.").

Target Platform: macOS 13.0+ (Ventura, Sonoma, Sequoia)
Architecture: Universal Mach-O Fat Binary (`arm64` Apple Silicon + `x86_64` Intel)

---

## 1. Quick Automated Test Commands

### A. Run In-App Headless Self-Tests (10 Tests)
Execute deterministic internal logic tests without launching GUI windows:
```bash
./bin/MacPulse --selftest
```
Expected output:
- `[PASS] MPAppSettings initialization and defaults`
- `[PASS] MPPowerManager dual assertion lifecycle and idempotency`
- `[PASS] MPPowerManager double-release safety (no 0xe00002c2)`
- `[PASS] MPPriorityArbiter hierarchy (Always Awake > Timed Awake > Smart Awake > Disabled)`
- `[PASS] MPPriorityArbiter battery safety cutoff logic`
- `[PASS] MPPowerSourceMonitor desktop Mac detection`
- `[PASS] MPTimedAwakeManager monotonic countdown and session lifecycle`
- `[PASS] MPPriorityArbiter dynamic Timed Awake manager integration and fallback`
- `[PASS] MPAboutWindowController utility panel instantiation and feature coverage`
- `[PASS] Clean teardown and assertion release`
- Exit code: `0`

### B. Run Complete E2E Automated Test Suites (98 Test Cases)
Run the 17 automated regression suites across all 4 tiers:
```bash
./Tests/run_e2e_tests.sh
```
Duration: ~45-50 seconds
Expected result: `17 Passed, 0 Failed, 98 Passed, 0 Failed`.

### C. Run Adversarial Stress Test Suite (3,840 Permutations)
Run stress tests covering multi-threading, rapid AC/battery transitions, and debounce coalescing:
```bash
./Tests/tiers/tier5_adversarial/run_adversarial_tests.sh
```

---

## 2. Kernel Power Assertion Verification (`pmset`)

MacPulse uses Apple's native IOKit IOPMAssertion APIs. Verify live kernel assertions via macOS `pmset`:

### Test Smart Awake Assertion:
```bash
# 1. Enable Smart Awake
defaults write com.shoaib.macpulse keepAwakeWhileCharging -bool YES
defaults write com.shoaib.macpulse alwaysAwake -bool NO

# 2. Launch MacPulse
open ./MacPulse.app

# 3. Check active kernel assertions (when plugged into AC power)
pmset -g assertions | grep MacPulse
```
Expected result:
`PreventUserIdleSystemSleep "MacPulse Smart Awake (AC Connected)"` is active.

### Test Display Sleep Toggle:
```bash
# When Allow Display Sleep is toggled OFF (keep display awake):
defaults write com.shoaib.macpulse allowDisplaySleep -bool NO

# Check kernel assertions
pmset -g assertions | grep MacPulse
```
Expected result:
Both `PreventUserIdleSystemSleep` AND `PreventUserIdleDisplaySleep` are held.

### Test Clean Teardown (Zero Assertion Leaks):
```bash
# Quit MacPulse
osascript -e 'quit app "MacPulse"'
sleep 1

# Check assertions
pmset -g assertions | grep MacPulse
```
Expected result:
Output is completely empty. Zero dangling assertions.

---

## 3. Package Contents

- `MacPulse.app`: Standalone application bundle with native AppIcon and LaunchServices configuration.
- `MacPulse.dmg`: Read-only compressed release installer with `/Applications` drag-and-drop link.
- `bin/MacPulse`: Universal command-line executable.
- `Tests/`: Full bash test harness and test suites.
- `AI_TESTING_GUIDE.md`: This testing guide.
