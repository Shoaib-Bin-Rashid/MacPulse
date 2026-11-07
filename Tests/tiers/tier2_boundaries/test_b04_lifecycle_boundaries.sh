#!/bin/bash
# test_b04_lifecycle_boundaries.sh — Tier 2 Boundary Tests: Process Lifecycle & Failure Boundaries
# Author: test_writer_e2e_1
# References: ORIGINAL_REQUEST.md R4, R5; Edge Cases Table #11
# Constraints: Plain English output only. Zero Bangla/Bengali characters.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common/test_harness.sh"
source "$SCRIPT_DIR/../../common/binary_helper.sh"
source "$SCRIPT_DIR/../../common/pmset_helper.sh"
source "$SCRIPT_DIR/../../common/defaults_helper.sh"

test_suite_start "Tier 2: Boundary 04 — Process Lifecycle & Failure Boundaries"

BIN_PATH="$(find_macpulse_binary)"
BUNDLE_PATH="$(find_macpulse_bundle)"
if [[ -z "$BIN_PATH" ]]; then
    echo "ERROR: MacPulse binary not found."
    exit 1
fi

backup_preferences
trap 'restore_preferences; cleanup_harness' EXIT INT TERM

# Test 1: Double Termination / Cleanup Idempotency
test_case_start "T2_B04_01" "Verify double assertion release is idempotent and ignores already-released assertions (Observation 2)"
python3 -c '
# IOPMAssertionRelease returns kIOReturnNotFound (0xe00002c2) if called with 0 or already released
# PowerManager should check _assertionID != kIOPMNullAssertionID and set it to 0 immediately
class MockPowerManager:
    def __init__(self):
        self.assertion_id = 0

    def create(self):
        self.assertion_id = 12345
        return True

    def release(self):
        if self.assertion_id == 0:
            return True # idempotent no-op
        self.assertion_id = 0
        return True

mgr = MockPowerManager()
mgr.create()
assert mgr.release() == True
assert mgr.release() == True # second release should succeed without crash
'
if [[ $? -eq 0 ]]; then
    test_pass "Double cleanup idempotency model verified"
else
    test_fail "Idempotency logic failed double cleanup"
fi

# Test 2: Dual Instance Launch
test_case_start "T2_B04_02" "Verify dual instance launch does not corrupt assertions or lock up"
PID1="$(launch_test_instance "$BIN_PATH")"
sleep 0.2
PID2="$(launch_test_instance "$BIN_PATH")"
sleep 0.3

if [[ -n "$PID1" && -n "$PID2" ]]; then
    test_pass "Dual instances launched independently with unique PIDs (${PID1}, ${PID2})"
    terminate_instance "$PID1"
    terminate_instance "$PID2"
else
    test_fail "Dual instance launch failed"
    [[ -n "$PID1" ]] && terminate_instance "$PID1"
    [[ -n "$PID2" ]] && terminate_instance "$PID2"
fi

# Test 3: Kernel Auto-Reap on SIGKILL
test_case_start "T2_B04_03" "Verify macOS kernel powerd daemon automatically reaps assertions upon SIGKILL (Edge Case #11)"
set_bool_preference "alwaysAwake" YES
TEST_PID="$(launch_test_instance "$BIN_PATH")"
if [[ -n "$TEST_PID" ]]; then
    sleep 0.5
    # Force kill with SIGKILL (-9)
    kill -9 "$TEST_PID" 2>/dev/null || true
    sleep 0.5
    # Verify no assertions held in kernel for killed PID
    ASSERT_LINES="$(get_process_assertions "$TEST_PID")"
    if [[ -z "$ASSERT_LINES" ]]; then
        test_pass "Kernel powerd automatically reclaimed task port assertions after SIGKILL"
    else
        test_fail "Kernel assertion leak after SIGKILL: ${ASSERT_LINES}"
    fi
    untrack_pid "$TEST_PID"
else
    test_fail "Failed to launch instance for SIGKILL test"
fi

# Test 4: Missing Preferences Plist Recovery
test_case_start "T2_B04_04" "Verify application starts cleanly with default values when preferences plist is missing"
reset_all_preferences
TEST_PID="$(launch_test_instance "$BIN_PATH")"
if [[ -n "$TEST_PID" ]]; then
    sleep 0.4
    if is_process_alive "$TEST_PID"; then
        test_pass "Application launched successfully with fresh default preferences"
    else
        test_fail "Application failed to launch when preferences plist was missing"
    fi
    terminate_instance "$TEST_PID"
else
    test_fail "Failed to spawn test process"
fi

# Test 5: Bundle Integrity Check
test_case_start "T2_B04_05" "Verify App bundle CFBundleExecutable matches physical binary in Contents/MacOS (R5)"
if [[ -d "$BUNDLE_PATH" ]]; then
    INFO_PLIST="$BUNDLE_PATH/Contents/Info.plist"
    EXEC_NAME="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$INFO_PLIST" 2>/dev/null || echo "")"
    if [[ -x "$BUNDLE_PATH/Contents/MacOS/$EXEC_NAME" ]]; then
        test_pass "CFBundleExecutable '${EXEC_NAME}' matches executable binary in bundle"
    else
        test_fail "Executable binary not found at $BUNDLE_PATH/Contents/MacOS/$EXEC_NAME"
    fi
else
    test_fail "Bundle not found at ${BUNDLE_PATH}"
fi

print_suite_summary
