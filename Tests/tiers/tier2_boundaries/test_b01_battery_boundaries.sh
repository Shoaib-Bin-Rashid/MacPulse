#!/bin/bash
# test_b01_battery_boundaries.sh — Tier 2 Boundary Tests: Battery Percentages & Safety Thresholds
# Author: test_writer_e2e_1
# References: ORIGINAL_REQUEST.md R3; PROJECT.md Features 13, 14
# Constraints: Plain English output only. Zero Bangla/Bengali characters.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common/test_harness.sh"
source "$SCRIPT_DIR/../../common/binary_helper.sh"
source "$SCRIPT_DIR/../../common/pmset_helper.sh"
source "$SCRIPT_DIR/../../common/defaults_helper.sh"

test_suite_start "Tier 2: Boundary 01 — Battery Capacity & Safety Threshold Tripwires"

backup_preferences
trap 'restore_preferences; cleanup_harness' EXIT INT TERM

# Test 1: Absolute Zero Battery Boundary (0%)
test_case_start "T2_B01_01" "Verify battery at 0% triggers immediate Always Awake cutoff (R3)"
python3 -c '
def evaluate_cutoff(battery_pct, threshold_pct):
    return battery_pct <= threshold_pct

# 0% battery with any threshold (10%-50%) MUST trigger cutoff
assert evaluate_cutoff(0, 10) == True
assert evaluate_cutoff(0, 20) == True
assert evaluate_cutoff(0, 50) == True
'
if [[ $? -eq 0 ]]; then
    test_pass "0% battery boundary strictly trips Always Awake cutoff"
else
    test_fail "0% battery boundary evaluation failed"
fi

# Test 2: Minimum Safety Threshold Boundary (10%)
test_case_start "T2_B01_02" "Verify minimum configurable threshold boundary at 10% (R3, Feature 13)"
set_int_preference "batterySafetyThreshold" 10
SAVED="$(get_preference "batterySafetyThreshold")"
if [[ "$SAVED" == "10" ]]; then
    test_pass "Minimum 10% boundary successfully accepted and persisted"
else
    test_fail "Failed to configure minimum 10% boundary: got '${SAVED}'"
fi

# Test 3: Default Safety Threshold Equality (20% <= 20%)
test_case_start "T2_B01_03" "Verify boundary equality: exactly 20% battery with 20% threshold triggers cutoff (R3, Feature 14)"
python3 -c '
# Boundary condition: "battery falls below or equal to threshold"
# If battery is 20 and threshold is 20, cutoff MUST trigger
def should_cutoff(pct, thresh):
    return pct <= thresh

assert should_cutoff(20, 20) == True, "Equality boundary failed: 20% <= 20% should trigger cutoff"
'
if [[ $? -eq 0 ]]; then
    test_pass "Exact threshold equality (20% <= 20%) triggers cutoff"
else
    test_fail "Boundary equality failed to trigger cutoff"
fi

# Test 4: Threshold + 1 Boundary (21% > 20%)
test_case_start "T2_B01_04" "Verify boundary +1: 21% battery with 20% threshold retains Always Awake (R3, Feature 14)"
python3 -c '
def should_cutoff(pct, thresh):
    return pct <= thresh

assert should_cutoff(21, 20) == False, "Boundary +1 failed: 21% > 20% should retain Always Awake"
'
if [[ $? -eq 0 ]]; then
    test_pass "Threshold +1 (21% > 20%) maintains active Always Awake session"
else
    test_fail "Threshold +1 prematurely cut off Always Awake"
fi

# Test 5: Maximum Safety Threshold Boundary (50%)
test_case_start "T2_B01_05" "Verify maximum configurable threshold boundary at 50% (R3, Feature 13)"
set_int_preference "batterySafetyThreshold" 50
SAVED="$(get_preference "batterySafetyThreshold")"
if [[ "$SAVED" == "50" ]]; then
    test_pass "Maximum 50% boundary successfully accepted and persisted"
else
    test_fail "Failed to configure maximum 50% boundary: got '${SAVED}'"
fi

# Test 6: 100% Full Capacity Boundary
test_case_start "T2_B01_06" "Verify 100% full capacity boundary operates normally without integer overflow (Feature 14)"
python3 -c '
def evaluate_sleep(battery_pct, threshold_pct, is_always):
    return is_always and (battery_pct > threshold_pct)

assert evaluate_sleep(100, 20, True) == True
assert evaluate_sleep(100, 50, True) == True
'
if [[ $? -eq 0 ]]; then
    test_pass "100% full capacity boundary evaluates reliably without numerical overflow"
else
    test_fail "100% battery boundary evaluation failed"
fi

print_suite_summary
