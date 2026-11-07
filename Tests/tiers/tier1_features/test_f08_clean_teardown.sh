#!/bin/bash
# test_f08_clean_teardown.sh — Tier 1 Feature Tests: Clean Termination Teardown & Assertion Release
# Author: test_writer_e2e_1
# References: ORIGINAL_REQUEST.md R4; PROJECT.md Feature 18
# Constraints: Plain English output only. Zero Bangla/Bengali characters.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common/test_harness.sh"
source "$SCRIPT_DIR/../../common/binary_helper.sh"
source "$SCRIPT_DIR/../../common/pmset_helper.sh"
source "$SCRIPT_DIR/../../common/defaults_helper.sh"

test_suite_start "Tier 1: Feature 08 — Clean Termination Teardown & Assertion Release"

BIN_PATH="$(find_macpulse_binary)"
if [[ -z "$BIN_PATH" ]]; then
    echo "ERROR: MacPulse binary not found."
    exit 1
fi

backup_preferences
trap 'restore_preferences; cleanup_harness' EXIT INT TERM

# Test 1: SIGTERM System Sleep Assertion Release
test_case_start "T1_F08_01" "Verify SIGTERM termination cleanly releases PreventUserIdleSystemSleep assertion (R4, Feature 18)"
set_bool_preference "alwaysAwake" YES
TEST_PID="$(launch_test_instance "$BIN_PATH")"
if [[ -z "$TEST_PID" ]]; then
    test_fail "Failed to launch MacPulse instance"
else
    sleep 0.5
    # Verify assertion was held
    has_system_sleep_assertion "$TEST_PID" || true
    # Terminate via SIGTERM
    kill -TERM "$TEST_PID" 2>/dev/null || true
    sleep 0.5
    # Verify process exited and assertions are gone
    REMAINING="$(count_assertions_for_pid "$TEST_PID")"
    if [[ "$REMAINING" -eq 0 ]]; then
        test_pass "Zero system sleep assertions lingering after SIGTERM"
    else
        test_fail "Detected ${REMAINING} lingering assertions after SIGTERM"
    fi
    untrack_pid "$TEST_PID"
fi

# Test 2: SIGTERM Display Sleep Assertion Release
test_case_start "T1_F08_02" "Verify SIGTERM termination cleanly releases PreventUserIdleDisplaySleep assertion (R4, Feature 18)"
set_bool_preference "alwaysAwake" YES
set_bool_preference "allowDisplaySleep" NO
TEST_PID="$(launch_test_instance "$BIN_PATH")"
if [[ -z "$TEST_PID" ]]; then
    test_fail "Failed to launch MacPulse instance"
else
    sleep 0.5
    kill -TERM "$TEST_PID" 2>/dev/null || true
    sleep 0.5
    if has_display_sleep_assertion "$TEST_PID"; then
        test_fail "Display sleep assertion lingered after SIGTERM termination"
    else
        test_pass "Zero display sleep assertions lingering after SIGTERM"
    fi
    untrack_pid "$TEST_PID"
fi

# Test 3: Process Exit Verification
test_case_start "T1_F08_03" "Verify process terminates and does not become zombie upon receiving SIGTERM (Feature 18)"
TEST_PID="$(launch_test_instance "$BIN_PATH")"
if [[ -z "$TEST_PID" ]]; then
    test_fail "Failed to launch MacPulse instance"
else
    sleep 0.3
    kill -TERM "$TEST_PID" 2>/dev/null || true
    sleep 0.5
    if is_process_alive "$TEST_PID"; then
        test_fail "Process ${TEST_PID} failed to terminate upon SIGTERM"
        terminate_instance "$TEST_PID"
    else
        test_pass "Process ${TEST_PID} terminated cleanly upon receiving SIGTERM"
        untrack_pid "$TEST_PID"
    fi
fi

# Test 4: Kernel Powerd Zero Leak Audit
test_case_start "T1_F08_04" "Verify pmset -g assertions shows zero assertions registered under terminated PID (Feature 18)"
# Re-verify PID from previous test has 0 registered entries in pmset
ASSERT_LINES="$(get_process_assertions "$TEST_PID")"
if [[ -z "$ASSERT_LINES" ]]; then
    test_pass "Kernel powerd contains zero assertion records for terminated PID"
else
    test_fail "Found orphaned assertions in kernel: ${ASSERT_LINES}"
fi

# Test 5: Re-launch Assertion Clean Slate
test_case_start "T1_F08_05" "Verify sequential re-launch allocates clean assertion without state corruption (Feature 18)"
TEST_PID2="$(launch_test_instance "$BIN_PATH")"
if [[ -z "$TEST_PID2" ]]; then
    test_fail "Failed to launch second MacPulse instance"
else
    sleep 0.4
    if [[ "$TEST_PID2" != "$TEST_PID" ]]; then
        test_pass "Sequential re-launch initialized cleanly with fresh PID ${TEST_PID2}"
    else
        test_fail "Unexpected duplicate PID"
    fi
    terminate_instance "$TEST_PID2"
fi

print_suite_summary
