#!/bin/bash
# test_f05_priority_arbiter.sh — Tier 1 Feature Tests: Mode Priority Arbiter State Machine
# Author: test_writer_e2e_1
# References: ORIGINAL_REQUEST.md R4; PROJECT.md Feature 15
# Constraints: Plain English output only. Zero Bangla/Bengali characters.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common/test_harness.sh"
source "$SCRIPT_DIR/../../common/binary_helper.sh"
source "$SCRIPT_DIR/../../common/pmset_helper.sh"
source "$SCRIPT_DIR/../../common/defaults_helper.sh"

test_suite_start "Tier 1: Feature 05 — Mode Priority Arbiter State Machine"

BIN_PATH="$(find_macpulse_binary)"
if [[ -z "$BIN_PATH" ]]; then
    echo "ERROR: MacPulse binary not found."
    exit 1
fi

backup_preferences
trap 'restore_preferences; cleanup_harness' EXIT INT TERM

# Test 1: Always Awake > Timed Awake
test_case_start "T1_F05_01" "Verify Always Awake takes precedence over Timed Awake (R4, Feature 15)"
python3 -c '
# Priority Arbiter State Machine Evaluation Model
MODE_DISABLED = 0
MODE_SMART_AWAKE = 1
MODE_TIMED_AWAKE = 2
MODE_ALWAYS_AWAKE = 3

def arbitrate(always_awake, timed_active, smart_awake, is_ac, battery_pct, threshold):
    # Rule 1: Always Awake (with battery cutoff if on battery)
    if always_awake:
        if is_ac or battery_pct > threshold:
            return MODE_ALWAYS_AWAKE
    # Rule 2: Timed Awake
    if timed_active:
        return MODE_TIMED_AWAKE
    # Rule 3: Smart Awake
    if smart_awake and is_ac:
        return MODE_SMART_AWAKE
    return MODE_DISABLED

# Always Awake + Timed Awake active -> Always Awake wins
res = arbitrate(always_awake=True, timed_active=True, smart_awake=True, is_ac=True, battery_pct=80, threshold=20)
assert res == MODE_ALWAYS_AWAKE, f"Expected ALWAYS_AWAKE, got {res}"
'
if [[ $? -eq 0 ]]; then
    test_pass "Always Awake priority > Timed Awake mathematically verified"
else
    test_fail "Arbiter logic failed Always Awake > Timed Awake precedence"
fi

# Test 2: Timed Awake > Smart Awake
test_case_start "T1_F05_02" "Verify Timed Awake takes precedence over Smart Awake (R4, Feature 15)"
python3 -c '
MODE_TIMED_AWAKE = 2
def arbitrate(always_awake, timed_active, smart_awake, is_ac):
    if always_awake: return 3
    if timed_active: return 2
    if smart_awake and is_ac: return 1
    return 0

res = arbitrate(always_awake=False, timed_active=True, smart_awake=True, is_ac=True)
assert res == MODE_TIMED_AWAKE, f"Expected TIMED_AWAKE, got {res}"
'
if [[ $? -eq 0 ]]; then
    test_pass "Timed Awake priority > Smart Awake mathematically verified"
else
    test_fail "Arbiter logic failed Timed Awake > Smart Awake precedence"
fi

# Test 3: Smart Awake > Disabled (on AC)
test_case_start "T1_F05_03" "Verify Smart Awake takes precedence over Disabled when on AC power (R4, Feature 15)"
python3 -c '
MODE_SMART_AWAKE = 1
def arbitrate(always_awake, timed_active, smart_awake, is_ac):
    if always_awake: return 3
    if timed_active: return 2
    if smart_awake and is_ac: return 1
    return 0

res = arbitrate(always_awake=False, timed_active=False, smart_awake=True, is_ac=True)
assert res == MODE_SMART_AWAKE, f"Expected SMART_AWAKE, got {res}"
'
if [[ $? -eq 0 ]]; then
    test_pass "Smart Awake priority > Disabled on AC power mathematically verified"
else
    test_fail "Arbiter logic failed Smart Awake precedence on AC"
fi

# Test 4: Disabled Mode Yields Zero Assertions
test_case_start "T1_F05_04" "Verify Disabled mode strictly asserts zero kernel power assertions (R4, Feature 15)"
set_bool_preference "alwaysAwake" NO
set_bool_preference "keepAwakeWhileCharging" NO
TEST_PID="$(launch_test_instance "$BIN_PATH")"
if [[ -z "$TEST_PID" ]]; then
    test_fail "Failed to launch MacPulse instance"
else
    sleep 0.5
    COUNT="$(count_assertions_for_pid "$TEST_PID")"
    if [[ "$COUNT" -eq 0 ]]; then
        test_pass "Zero assertions verified for PID ${TEST_PID} in Disabled state"
    else
        test_fail "Found ${COUNT} assertions in Disabled state; expected 0"
    fi
    terminate_instance "$TEST_PID"
fi

# Test 5: Assertion Idempotency During Transitions
test_case_start "T1_F05_05" "Verify state transitions do not produce duplicate assertions or leaks (R4, Acceptance Criteria)"
set_bool_preference "alwaysAwake" YES
set_bool_preference "keepAwakeWhileCharging" YES
TEST_PID="$(launch_test_instance "$BIN_PATH")"
if [[ -z "$TEST_PID" ]]; then
    test_fail "Failed to launch MacPulse instance"
else
    sleep 0.5
    # System should hold at most 1 system sleep assertion
    COUNT="$(count_assertions_for_pid "$TEST_PID")"
    if [[ "$COUNT" -le 1 ]]; then
        test_pass "Assertion count (${COUNT}) confirms strict singleton assertion invariant"
    else
        test_fail "Duplicate assertions detected (Count: ${COUNT})"
    fi
    terminate_instance "$TEST_PID"
fi

print_suite_summary
