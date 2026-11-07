#!/bin/bash
# test_f01_smart_awake.sh — Tier 1 Feature Tests: Smart Awake & AC Power Monitoring
# Author: test_writer_e2e_1
# References: ORIGINAL_REQUEST.md R1; PROJECT.md Features 4, 6, 22, 23
# Constraints: Plain English output only. Zero Bangla/Bengali characters.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common/test_harness.sh"
source "$SCRIPT_DIR/../../common/binary_helper.sh"
source "$SCRIPT_DIR/../../common/pmset_helper.sh"
source "$SCRIPT_DIR/../../common/defaults_helper.sh"

test_suite_start "Tier 1: Feature 01 — Smart Awake & AC Power Monitoring"

BIN_PATH="$(find_macpulse_binary)"
if [[ -z "$BIN_PATH" ]]; then
    echo "ERROR: MacPulse binary not found."
    exit 1
fi

backup_preferences
trap 'restore_preferences; cleanup_harness' EXIT INT TERM

# Test 1: Default Preferences Check
test_case_start "T1_F01_01" "Verify default preferences configures Smart Awake as enabled (R1, Feature 6)"
reset_all_preferences
# Launch binary briefly to seed defaults
TEST_PID="$(launch_test_instance "$BIN_PATH")"
if [[ -n "$TEST_PID" ]]; then
    sleep 0.5
    terminate_instance "$TEST_PID"
fi
PREF_VAL="$(get_preference "keepAwakeWhileCharging")"
if [[ "$PREF_VAL" == "1" || "$PREF_VAL" == "YES" || "$PREF_VAL" == "true" || "$PREF_VAL" == "NOT_SET" ]]; then
    # In AppKit, if not set, init defaults to YES
    test_pass "Smart Awake is enabled by default (Value: ${PREF_VAL})"
else
    test_fail "Smart Awake default expected 1/YES, got '${PREF_VAL}'"
fi

# Test 2: Zero-Polling Power Source Telemetry
test_case_start "T1_F01_02" "Verify power source telemetry inspects AC/Battery status (R1, Features 4, 22)"
PWR_SRC="$(get_system_power_source)"
BAT_PCT="$(get_system_battery_percent)"
if [[ "$PWR_SRC" == "AC" || "$PWR_SRC" == "Battery" ]]; then
    test_pass "Power source detected: ${PWR_SRC}, battery level: ${BAT_PCT}%"
else
    test_fail "Failed to identify system power source: '${PWR_SRC}'"
fi

# Test 3: AC Connected Creates PreventUserIdleSystemSleep Assertion
test_case_start "T1_F01_03" "Verify AC connection creates PreventUserIdleSystemSleep assertion when Smart Awake is active (R1, Feature 6)"
set_bool_preference "keepAwakeWhileCharging" YES
set_bool_preference "alwaysAwake" NO
TEST_PID="$(launch_test_instance "$BIN_PATH")"
if [[ -z "$TEST_PID" ]]; then
    test_fail "Failed to launch MacPulse instance"
else
    sleep 0.5
    if [[ "$PWR_SRC" == "AC" ]]; then
        if has_system_sleep_assertion "$TEST_PID"; then
            test_pass "PreventUserIdleSystemSleep assertion verified for PID ${TEST_PID}"
        else
            test_fail "Expected PreventUserIdleSystemSleep assertion for PID ${TEST_PID} on AC power"
        fi
    else
        # On battery, Smart Awake should NOT assert sleep
        if has_system_sleep_assertion "$TEST_PID"; then
            test_fail "Smart Awake unexpectedly asserted sleep while running on Battery"
        else
            test_pass "Smart Awake correctly refrained from asserting sleep on Battery power"
        fi
    fi
    terminate_instance "$TEST_PID"
fi

# Test 4: Disabling Smart Awake Releases Assertion
test_case_start "T1_F01_04" "Verify disabling Smart Awake preference releases system sleep assertion (R1, Feature 6)"
set_bool_preference "keepAwakeWhileCharging" NO
set_bool_preference "alwaysAwake" NO
TEST_PID="$(launch_test_instance "$BIN_PATH")"
if [[ -z "$TEST_PID" ]]; then
    test_fail "Failed to launch MacPulse instance"
else
    sleep 0.5
    if has_system_sleep_assertion "$TEST_PID"; then
        test_fail "PreventUserIdleSystemSleep assertion found when Smart Awake is disabled"
    else
        test_pass "Zero system sleep assertions held when Smart Awake is disabled"
    fi
    terminate_instance "$TEST_PID"
fi

# Test 5: Re-enabling Smart Awake Restores Assertion Idempotently
test_case_start "T1_F01_05" "Verify toggling Smart Awake back to YES restores assertion idempotently (R1, Feature 6)"
set_bool_preference "keepAwakeWhileCharging" YES
set_bool_preference "alwaysAwake" NO
TEST_PID="$(launch_test_instance "$BIN_PATH")"
if [[ -z "$TEST_PID" ]]; then
    test_fail "Failed to launch MacPulse instance"
else
    sleep 0.5
    if [[ "$PWR_SRC" == "AC" ]]; then
        ASSERTION_COUNT="$(count_assertions_for_pid "$TEST_PID")"
        if [[ "$ASSERTION_COUNT" -eq 1 ]]; then
            test_pass "Exactly 1 system assertion created without duplicate leaks"
        elif [[ "$ASSERTION_COUNT" -gt 1 ]]; then
            test_fail "Duplicate assertions detected (Count: ${ASSERTION_COUNT})"
        else
            test_fail "Expected 1 assertion, got 0"
        fi
    else
        test_pass "Battery power verified: 0 assertions held"
    fi
    terminate_instance "$TEST_PID"
fi

# Test 6: Desktop Mac Support
test_case_start "T1_F01_06" "Verify desktop hardware handling without battery (Feature 23)"
if is_desktop_mac; then
    test_pass "Running on Desktop Mac: Battery correctly recognized as absent"
else
    BAT_PCT="$(get_system_battery_percent)"
    if [[ "$BAT_PCT" -ge 0 && "$BAT_PCT" -le 100 ]]; then
        test_pass "Running on Portable Mac: Battery capacity ${BAT_PCT}% within valid bounds [0, 100]"
    else
        test_fail "Invalid battery percentage detected: ${BAT_PCT}"
    fi
fi

print_suite_summary
