# Battery Safety Threshold Specification & Validation Report

**Product:** MacPulse  
**Feature:** Battery Safety Protection (`SCOPE-002`)  
**Approved Configuration:** Range 10%–80% inclusive, Default 40%  
**Date:** 2026-11-07  
**Status:** IMPLEMENTED & VERIFIED

---

## 1. Approved Product Decision

The Product Owner explicitly approved the canonical Battery Safety Threshold configuration:
- **Default Threshold:** `40%` (preserves healthy reserve before entering deep battery drain).
- **Minimum Value:** `10%`.
- **Maximum Value:** `80%`.
- **Valid Range:** `[10%, 80%]` inclusive.
- **UI Submenu Range:** `10%, 20%, 30%, 40%, 50%, 60%, 70%, 80%`.
- **Display Awake Integration:** When battery percentage is at or below the configured threshold, both continuous keep-awake (`Always Awake`) and `Keep Display Awake` are automatically paused to prevent sudden battery exhaustion.
- **Smart Awake Non-Interference:** Smart Awake continues uninterrupted while connected to AC power, regardless of battery level.

---

## 2. Shared Constants (`MPCommon.h`)

All components share identical canonical definitions:

```objc
#define kMPBatteryThresholdMin 10
#define kMPBatteryThresholdMax 80
#define kMPBatteryThresholdDefault 40
```

---

## 3. Persistence & Boundary Clamping (`MPAppSettings.m`)

### 3.1 Setter Clamping
```objc
- (void)setBatterySafetyThreshold:(NSInteger)batterySafetyThreshold {
    NSInteger clamped = batterySafetyThreshold;
    if (clamped < kMPBatteryThresholdMin) clamped = kMPBatteryThresholdMin;
    if (clamped > kMPBatteryThresholdMax) clamped = kMPBatteryThresholdMax;
    _batterySafetyThreshold = clamped;
    [[self userDefaults] setInteger:_batterySafetyThreshold forKey:kBatterySafetyThresholdKey];
    [[self userDefaults] synchronize];
    CFPreferencesAppSynchronize((__bridge CFStringRef)kBundleIdentifier);
    [[NSNotificationCenter defaultCenter] postNotificationName:kMPAppSettingsDidChangeNotification object:self];
}
```

### 3.2 Corrupted Preference Fallback
If an external tool or script writes an out-of-range value via Terminal (e.g. `defaults write com.shoaib.macpulse batterySafetyThreshold -int 100` or `-int -5`), `reloadSettings` safely falls back to default 40%:
```objc
id threshVal = [defs objectForKey:kBatterySafetyThresholdKey];
if (threshVal != nil) {
    NSInteger val = [defs integerForKey:kBatterySafetyThresholdKey];
    if (val >= kMPBatteryThresholdMin && val <= kMPBatteryThresholdMax) {
        _batterySafetyThreshold = val;
    } else {
        _batterySafetyThreshold = kMPBatteryThresholdDefault;
    }
} else {
    _batterySafetyThreshold = kMPBatteryThresholdDefault;
}
```

---

## 4. Automated Boundary Test Results

Executed within `/tmp/macpulse_step1_build/MacPulse --selftest` (and integrated in `main.m` self-test 1):

| Test Input | Expected Value | Actual Value | Result |
|:---:|:---:|:---:|:---:|
| `-5` | `10` | `10` | **PASS** |
| `0` | `10` | `10` | **PASS** |
| `9` | `10` | `10` | **PASS** |
| `10` | `10` | `10` | **PASS** |
| `40` | `40` | `40` | **PASS** |
| `80` | `80` | `80` | **PASS** |
| `81` | `80` | `80` | **PASS** |
| `100` | `80` | `80` | **PASS** |
| Corrupted / Missing | `40` | `40` | **PASS** |

Console Verification:
```
⚡ Running MacPulse Deterministic Headless Self-Tests...
[PASS] MPAppSettings initialization, defaults, and boundary clamping [10-80%]
...
[PASS] MPPriorityArbiter battery safety cutoff logic
All self-tests passed cleanly.
```

---

## 5. UI & Documentation Synchronization

1. **Menu Bar Submenu:** Offers options `@10, @20, @30, @40, @50, @60, @70, @80`.
2. **Menu Item Tooltip:** `"Battery percentage below which continuous keep-awake and display awake automatically pause."`
3. **About Window:** Explains default 40% cutoff with user-selectable threshold up to 80%.
4. **CLI Help (`--help`):** Documents default 40% threshold.
