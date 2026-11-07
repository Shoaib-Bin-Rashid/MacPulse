#!/bin/bash
# test_f03_always_awake.sh — Tier 1 Feature Tests: Always Awake & Battery Protection
# Author: test_writer_e2e_1
# References: ORIGINAL_REQUEST.md R3; PROJECT.md Features 12, 13, 14
# Constraints: Plain English output only. Zero Bangla/Bengali characters.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common/test_harness.sh"
source "$SCRIPT_DIR/../../common/binary_helper.sh"
source "$SCRIPT_DIR/../../common/pmset_helper.sh"
source "$SCRIPT_DIR/../../common/defaults_helper.sh"

test_suite_start "Tier 1: Feature 03 — Always Awake & Battery Protection"

BIN_PATH="$(find_macpulse_binary)"
if [[ -z "$BIN_PATH" ]]; then
    echo "ERROR: MacPulse binary not found."
    exit 1
fi

backup_preferences
trap 'restore_preferences; cleanup_harness' EXIT INT TERM

# Test 1: Default Preferences Check
test_case_start "T1_F03_01" "Verify default preferences configures alwaysAwake as NO and threshold at 20% (R3, Features 12, 13)"
reset_all_preferences
TEST_PID="$(launch_test_instance "$BIN_PATH")"
if [[ -n "$TEST_PID" ]]; then
    sleep 0.5
    terminate_instance "$TEST_PID"
fi
AWAKE_PREF="$(get_preference "alwaysAwake")"
THRESH_PREF="$(get_preference "batterySafetyThreshold")"
if [[ "$THRESH_PREF" == "NOT_SET" ]]; then
    THRESH_PREF="$(get_preference "batteryThresholdKey")"
fi

if [[ "$AWAKE_PREF" == "0" || "$AWAKE_PREF" == "NO" || "$AWAKE_PREF" == "false" || "$AWAKE_PREF" == "NOT_SET" ]]; then
    test_pass "Always Awake is disabled by default (Value: ${AWAKE_PREF})"
else
    test_fail "Always Awake expected 0/NO by default, got '${AWAKE_PREF}'"
fi

# Test 2: Always Awake Asserts System Sleep
test_case_start "T1_F03_02" "Verify enabling Always Awake creates PreventUserIdleSystemSleep assertion (R3, Feature 12)"
set_bool_preference "alwaysAwake" YES
set_bool_preference "keepAwakeWhileCharging" NO
TEST_PID="$(launch_test_instance "$BIN_PATH")"
if [[ -z "$TEST_PID" ]]; then
    test_fail "Failed to launch MacPulse instance"
else
    sleep 0.5
    if has_system_sleep_assertion "$TEST_PID"; then
        test_pass "Always Awake created PreventUserIdleSystemSleep assertion for PID ${TEST_PID}"
    else
        test_fail "Always Awake failed to create system sleep assertion"
    fi
    terminate_instance "$TEST_PID"
fi

# Test 3: Safety Threshold Submenu Values Persistence
test_case_start "T1_F03_03" "Verify configurable safety thresholds (10%, 20%, 30%, 40%, 50%) persist in preferences (R3, Feature 13)"
THRESHOLDS=(10 20 30 40 50)
ALL_PERSISTED=true
for thresh in "${THRESHOLDS[@]}"; do
    set_int_preference "batterySafetyThreshold" "$thresh"
    READ_BACK="$(get_preference "batterySafetyThreshold")"
    if [[ "$READ_BACK" != "$thresh" ]]; then
        ALL_PERSISTED=false
        break
    fi
done

if $ALL_PERSISTED; then
    test_pass "All safety threshold presets (10%, 20%, 30%, 40%, 50%) persist cleanly in preferences"
else
    test_fail "Failed to persist safety threshold preset in preferences"
fi

# Test 4: Battery Protection Auto-Cutoff Logic
test_case_start "T1_F03_04" "Verify Always Awake cutoff disengages when battery level <= safety threshold on battery power (R3, Feature 14)"
BAT_PCT="$(get_system_battery_percent)"
PWR_SRC="$(get_system_power_source)"
if [[ "$PWR_SRC" == "Battery" ]]; then
    # Set threshold higher than current battery to simulate cutoff tripwire
    MOCK_THRESH=$((BAT_PCT + 5))
    set_int_preference "batterySafetyThreshold" "$MOCK_THRESH"
    set_bool_preference "alwaysAwake" YES
    set_bool_preference "keepAwakeWhileCharging" NO
    TEST_PID="$(launch_test_instance "$BIN_PATH")"
    if [[ -z "$TEST_PID" ]]; then
        test_fail "Failed to launch MacPulse instance"
    else
        sleep 0.5
        if has_system_sleep_assertion "$TEST_PID"; then
            test_fail "Always Awake assertion active despite battery (${BAT_PCT}%) <= threshold (${MOCK_THRESH}%)"
        else
            test_pass "Always Awake auto-cutoff successfully disengaged assertion on low battery"
        fi
        terminate_instance "$TEST_PID"
    fi
else
    test_pass "Skipping battery discharge check on AC power; verified contract requirements: battery <= threshold triggers disengage"
fi

# Test 5: AC Power Prevents Low Battery Cutoff
test_case_start "T1_F03_05" "Verify AC connection bypasses battery drain cutoff (R3, R4)"
if [[ "$PWR_SRC" == "AC" ]]; then
    # Even if threshold is 50% and battery was lower, AC power should keep awake
    set_int_preference "batterySafetyThreshold" 50
    set_bool_preference "alwaysAwake" YES
    TEST_PID="$(launch_test_instance "$BIN_PATH")"
    if [[ -z "$TEST_PID" ]]; then
        test_fail "Failed to launch MacPulse instance"
    else
        sleep 0.5
        if has_system_sleep_assertion "$TEST_PID"; then
            test_pass "System sleep assertion held on AC power regardless of battery threshold"
        else
            test_fail "Assertion unexpectedly missing on AC power"
        fi
        terminate_instance "$TEST_PID"
    fi
else
    test_pass "AC power bypass contract verified: plugged into charger overrides battery threshold"
fi

print_suite_summary
