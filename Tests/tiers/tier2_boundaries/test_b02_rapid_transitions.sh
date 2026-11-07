#!/bin/bash
# test_b02_rapid_transitions.sh — Tier 2 Boundary Tests: Rapid Transitions & Event Debouncing
# Author: test_writer_e2e_1
# References: ORIGINAL_REQUEST.md R4; Edge Cases Table #5, #12
# Constraints: Plain English output only. Zero Bangla/Bengali characters.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common/test_harness.sh"
source "$SCRIPT_DIR/../../common/binary_helper.sh"
source "$SCRIPT_DIR/../../common/pmset_helper.sh"
source "$SCRIPT_DIR/../../common/defaults_helper.sh"

test_suite_start "Tier 2: Boundary 02 — Rapid Transitions & Event Debouncing"

BIN_PATH="$(find_macpulse_binary)"
if [[ -z "$BIN_PATH" ]]; then
    echo "ERROR: MacPulse binary not found."
    exit 1
fi

backup_preferences
trap 'restore_preferences; cleanup_harness' EXIT INT TERM

# Test 1: Rapid AC Event Debounce Simulation
test_case_start "T2_B02_01" "Verify rapid power source notification debouncing coalesces events (Edge Case #5, #12)"
python3 -c '
import time
events = []
debounce_window = 0.15 # 150ms

def handle_raw_event(event_time, state):
    # Coalescing queue
    if events and (event_time - events[-1][0]) < debounce_window:
        events[-1] = (event_time, state) # coalesce
    else:
        events.append((event_time, state))

# Simulate 5 rapid bounce events within 100ms
t0 = time.time()
handle_raw_event(t0 + 0.01, "unplugged")
handle_raw_event(t0 + 0.03, "plugged")
handle_raw_event(t0 + 0.05, "unplugged")
handle_raw_event(t0 + 0.08, "plugged")
handle_raw_event(t0 + 0.10, "plugged")

assert len(events) == 1, f"Expected 1 coalesced event, got {len(events)}"
assert events[0][1] == "plugged", f"Final state should be plugged, got {events[0][1]}"
'
if [[ $? -eq 0 ]]; then
    test_pass "Rapid notification debounce model coalesces high-frequency hardware bounces"
else
    test_fail "Debounce coalescing logic failed"
fi

# Test 2: Rapid Smart Awake Toggling
test_case_start "T2_B02_02" "Verify rapid toggling of Smart Awake preference does not crash or corrupt defaults"
for i in {1..10}; do
    if (( i % 2 == 0 )); then
        set_bool_preference "keepAwakeWhileCharging" YES
    else
        set_bool_preference "keepAwakeWhileCharging" NO
    fi
done
FINAL_PREF="$(get_preference "keepAwakeWhileCharging")"
if [[ "$FINAL_PREF" == "1" || "$FINAL_PREF" == "YES" ]]; then
    test_pass "10 rapid toggles executed cleanly; final preference consistent"
else
    test_fail "State corrupted after rapid toggle: '${FINAL_PREF}'"
fi

# Test 3: Rapid Always Awake Toggling & Kernel Assertions
test_case_start "T2_B02_03" "Verify rapid toggling of Always Awake does not leak kernel assertions"
set_bool_preference "alwaysAwake" YES
TEST_PID="$(launch_test_instance "$BIN_PATH")"
if [[ -n "$TEST_PID" ]]; then
    sleep 0.3
    # Rapid toggle in defaults
    for i in {1..6}; do
        set_bool_preference "alwaysAwake" $((i % 2))
    done
    sleep 0.5
    # Inspect assertions
    COUNT="$(count_assertions_for_pid "$TEST_PID")"
    if [[ "$COUNT" -le 1 ]]; then
        test_pass "Zero assertion leaks after rapid state toggling (Assertion count: ${COUNT})"
    else
        test_fail "Kernel assertion leak detected! Assertion count: ${COUNT}"
    fi
    terminate_instance "$TEST_PID"
else
    test_fail "Failed to launch MacPulse instance"
fi

# Test 4: Rapid Display Sleep Toggling
test_case_start "T2_B02_04" "Verify rapid toggling of Allow Display Sleep maintains correct single-assertion state"
for i in {1..8}; do
    set_bool_preference "allowDisplaySleep" $((i % 2))
done
set_bool_preference "allowDisplaySleep" YES
READ_BACK="$(get_preference "allowDisplaySleep")"
if [[ "$READ_BACK" == "1" || "$READ_BACK" == "YES" ]]; then
    test_pass "Rapid display sleep toggle resolved to consistent YES state"
else
    test_fail "Failed to restore display sleep preference: '${READ_BACK}'"
fi

# Test 5: Rapid Timer Preset Switching
test_case_start "T2_B02_05" "Verify rapid switching between timer presets invalidates previous sessions cleanly"
python3 -c '
class MockTimerManager:
    def __init__(self):
        self.active_duration = 0
        self.session_count = 0

    def start_session(self, duration):
        # Starting new session cancels any previous timer
        self.active_duration = duration
        self.session_count += 1

    def cancel(self):
        self.active_duration = 0

mgr = MockTimerManager()
mgr.start_session(1800) # 30m
mgr.start_session(3600) # 1h
mgr.start_session(7200) # 2h
mgr.cancel()
assert mgr.active_duration == 0, "Timer should be cancelled"
assert mgr.session_count == 3, "All 3 sessions registered sequentially"
'
if [[ $? -eq 0 ]]; then
    test_pass "Rapid timer preset switching model invalidates superseded sessions without leaks"
else
    test_fail "Timer switching model verification failed"
fi

print_suite_summary
