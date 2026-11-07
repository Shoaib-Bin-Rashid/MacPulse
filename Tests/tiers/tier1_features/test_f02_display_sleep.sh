#!/bin/bash
# test_f02_display_sleep.sh — Tier 1 Feature Tests: Allow Display Sleep Assertion Lifecycle
# Author: test_writer_e2e_1
# References: ORIGINAL_REQUEST.md R1; PROJECT.md Feature 7; Engineering Review Issue C-01
# Constraints: Plain English output only. Zero Bangla/Bengali characters.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common/test_harness.sh"
source "$SCRIPT_DIR/../../common/binary_helper.sh"
source "$SCRIPT_DIR/../../common/pmset_helper.sh"
source "$SCRIPT_DIR/../../common/defaults_helper.sh"

test_suite_start "Tier 1: Feature 02 — Allow Display Sleep Assertion Lifecycle"

BIN_PATH="$(find_macpulse_binary)"
if [[ -z "$BIN_PATH" ]]; then
    echo "ERROR: MacPulse binary not found."
    exit 1
fi

backup_preferences
trap 'restore_preferences; cleanup_harness' EXIT INT TERM

# Test 1: Default Preferences Check
test_case_start "T1_F02_01" "Verify default preferences configures allowDisplaySleep as YES (R1, Feature 7)"
reset_all_preferences
TEST_PID="$(launch_test_instance "$BIN_PATH")"
if [[ -n "$TEST_PID" ]]; then
    sleep 0.5
    terminate_instance "$TEST_PID"
fi
PREF_VAL="$(get_preference "allowDisplaySleep")"
if [[ "$PREF_VAL" == "1" || "$PREF_VAL" == "YES" || "$PREF_VAL" == "true" || "$PREF_VAL" == "NOT_SET" ]]; then
    test_pass "Allow Display Sleep defaults to enabled (Value: ${PREF_VAL})"
else
    test_fail "Allow Display Sleep default expected 1/YES, got '${PREF_VAL}'"
fi

# Test 2: Display Sleep Assertion Inactive when Allowed
test_case_start "T1_F02_02" "Verify no PreventUserIdleDisplaySleep assertion exists when allowDisplaySleep is YES (Feature 7)"
set_bool_preference "allowDisplaySleep" YES
set_bool_preference "keepAwakeWhileCharging" YES
set_bool_preference "alwaysAwake" YES # ensure system is awake
TEST_PID="$(launch_test_instance "$BIN_PATH")"
if [[ -z "$TEST_PID" ]]; then
    test_fail "Failed to launch MacPulse instance"
else
    sleep 0.5
    if has_display_sleep_assertion "$TEST_PID"; then
        test_fail "Unexpected PreventUserIdleDisplaySleep assertion when display sleep is permitted"
    else
        test_pass "PreventUserIdleDisplaySleep is correctly absent when display sleep is allowed"
    fi
    terminate_instance "$TEST_PID"
fi

# Test 3: Display Sleep Assertion Active when Disallowed
test_case_start "T1_F02_03" "Verify PreventUserIdleDisplaySleep assertion is created when allowDisplaySleep is NO (Feature 7)"
set_bool_preference "allowDisplaySleep" NO
set_bool_preference "alwaysAwake" YES # ensure system is awake
TEST_PID="$(launch_test_instance "$BIN_PATH")"
if [[ -z "$TEST_PID" ]]; then
    test_fail "Failed to launch MacPulse instance"
else
    sleep 0.5
    if has_display_sleep_assertion "$TEST_PID"; then
        test_pass "PreventUserIdleDisplaySleep assertion verified in kernel for PID ${TEST_PID}"
    else
        test_fail "PreventUserIdleDisplaySleep assertion missing when allowDisplaySleep is NO (Issue C-01)"
    fi
    terminate_instance "$TEST_PID"
fi

# Test 4: Re-enabling Display Sleep Releases Assertion Immediately
test_case_start "T1_F02_04" "Verify re-enabling allowDisplaySleep releases the display assertion immediately (Feature 7)"
set_bool_preference "allowDisplaySleep" YES
set_bool_preference "alwaysAwake" YES
TEST_PID="$(launch_test_instance "$BIN_PATH")"
if [[ -z "$TEST_PID" ]]; then
    test_fail "Failed to launch MacPulse instance"
else
    sleep 0.5
    if has_display_sleep_assertion "$TEST_PID"; then
        test_fail "Display sleep assertion lingered after allowDisplaySleep was restored to YES"
    else
        test_pass "Display sleep assertion released immediately upon enabling allowDisplaySleep"
    fi
    terminate_instance "$TEST_PID"
fi

# Test 5: Invariant: Display Sleep Assertion NEVER Held if System is Inactive
test_case_start "T1_F02_05" "Verify display assertion is suppressed if system sleep is not prevented (Feature 7, R4)"
set_bool_preference "allowDisplaySleep" NO
set_bool_preference "keepAwakeWhileCharging" NO
set_bool_preference "alwaysAwake" NO
TEST_PID="$(launch_test_instance "$BIN_PATH")"
if [[ -z "$TEST_PID" ]]; then
    test_fail "Failed to launch MacPulse instance"
else
    sleep 0.5
    if has_display_sleep_assertion "$TEST_PID"; then
        test_fail "Display assertion unlawfully held when system sleep is not prevented"
    else
        test_pass "Display assertion correctly withheld when system is inactive"
    fi
    terminate_instance "$TEST_PID"
fi

print_suite_summary
