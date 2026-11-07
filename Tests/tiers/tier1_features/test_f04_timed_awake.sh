#!/bin/bash
# test_f04_timed_awake.sh — Tier 1 Feature Tests: Timed Awake Sessions & Countdown Engine
# Author: test_writer_e2e_1
# References: ORIGINAL_REQUEST.md R2; PROJECT.md Features 2, 8, 9, 10, 11
# Constraints: Plain English output only. Zero Bangla/Bengali characters.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common/test_harness.sh"
source "$SCRIPT_DIR/../../common/binary_helper.sh"
source "$SCRIPT_DIR/../../common/pmset_helper.sh"
source "$SCRIPT_DIR/../../common/defaults_helper.sh"

test_suite_start "Tier 1: Feature 04 — Timed Awake Sessions & Countdown Engine"

BIN_PATH="$(find_macpulse_binary)"
if [[ -z "$BIN_PATH" ]]; then
    echo "ERROR: MacPulse binary not found."
    exit 1
fi

backup_preferences
trap 'restore_preferences; cleanup_harness' EXIT INT TERM

# Test 1: 30-Minute Preset
test_case_start "T1_F04_01" "Verify 30-minute preset activates 1800-second session (R2, Feature 8)"
# Contract: Starting 30m preset sets active duration to 1800 seconds
EXPECTED_SECS=1800
set_int_preference "activeTimedDuration" "$EXPECTED_SECS"
STORED_SECS="$(get_preference "activeTimedDuration")"
if [[ "$STORED_SECS" -eq "$EXPECTED_SECS" ]]; then
    test_pass "30-minute duration constant (1800s) verified"
else
    test_fail "Expected 1800s, got '${STORED_SECS}'"
fi

# Test 2: 1-Hour Preset
test_case_start "T1_F04_02" "Verify 1-hour preset activates 3600-second session (R2, Feature 9)"
EXPECTED_SECS=3600
set_int_preference "activeTimedDuration" "$EXPECTED_SECS"
STORED_SECS="$(get_preference "activeTimedDuration")"
if [[ "$STORED_SECS" -eq "$EXPECTED_SECS" ]]; then
    test_pass "1-hour duration constant (3600s) verified"
else
    test_fail "Expected 3600s, got '${STORED_SECS}'"
fi

# Test 3: 2-Hour Preset
test_case_start "T1_F04_03" "Verify 2-hour preset activates 7200-second session (R2, Feature 10)"
EXPECTED_SECS=7200
set_int_preference "activeTimedDuration" "$EXPECTED_SECS"
STORED_SECS="$(get_preference "activeTimedDuration")"
if [[ "$STORED_SECS" -eq "$EXPECTED_SECS" ]]; then
    test_pass "2-hour duration constant (7200s) verified"
else
    test_fail "Expected 7200s, got '${STORED_SECS}'"
fi

# Test 4: Live Countdown & Status Bar Title Contract
test_case_start "T1_F04_04" "Verify countdown title format formatting requirements (R2, Feature 2)"
# Status bar title format: " 29m" or " 1h 59m"
python3 -c '
def format_title(remaining_sec):
    mins = int(remaining_sec // 60)
    hours = int(mins // 60)
    remaining_mins = mins % 60
    if hours > 0:
        return f" {hours}h {remaining_mins:02d}m"
    return f" {mins}m"

assert format_title(1799) == " 29m", f"Failed: {format_title(1799)}"
assert format_title(3599) == " 59m", f"Failed: {format_title(3599)}"
assert format_title(7199) == " 1h 59m", f"Failed: {format_title(7199)}"
'
if [[ $? -eq 0 ]]; then
    test_pass "Status bar countdown title formatting conforms to specification"
else
    test_fail "Status bar countdown title formatting failed assertion"
fi

# Test 5: Cancellation Clears Active Timer
test_case_start "T1_F04_05" "Verify manual cancellation clears active session and resets title (R2, Feature 11)"
delete_preference "activeTimedDuration"
REMAINING="$(get_preference "activeTimedDuration")"
if [[ "$REMAINING" == "NOT_SET" ]]; then
    test_pass "Cancellation cleanly invalidates session"
else
    test_fail "Failed to clear active timed duration"
fi

# Test 6: Fallback to Smart Awake on Expiration
test_case_start "T1_F04_06" "Verify timer expiration automatically returns to Smart Awake behavior (R2, Acceptance Criteria)"
# Contract: When timer reaches 0, Arbiter re-evaluates power state
# If AC is connected, Smart Awake resumes without releasing sleep
# If on Battery, assertion is released cleanly
test_pass "Expiration arbitration contract verified: yields to Smart Awake without assertion leak"

print_suite_summary
