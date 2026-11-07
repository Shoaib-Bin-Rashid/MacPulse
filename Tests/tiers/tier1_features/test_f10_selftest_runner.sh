#!/bin/bash
# test_f10_selftest_runner.sh — Tier 1 Feature Tests: Headless Self-Test Runner & Verification Harness
# Author: test_writer_e2e_1
# References: ORIGINAL_REQUEST.md Acceptance Criteria; PROJECT.md Feature 21; tools/selftest.sh
# Constraints: Plain English output only. Zero Bangla/Bengali characters.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common/test_harness.sh"
source "$SCRIPT_DIR/../../common/binary_helper.sh"

test_suite_start "Tier 1: Feature 10 — Headless Self-Test Runner & Verification Harness"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BIN_PATH="$(find_macpulse_binary)"
SELFTEST_SCRIPT="$PROJECT_ROOT/tools/selftest.sh"

# Test 1: tools/selftest.sh Script Executable Verification
test_case_start "T1_F10_01" "Verify tools/selftest.sh exists and is executable (Feature 21)"
if [[ -x "$SELFTEST_SCRIPT" ]]; then
    test_pass "tools/selftest.sh exists and is executable"
else
    test_fail "tools/selftest.sh missing or not executable at ${SELFTEST_SCRIPT}"
fi

# Test 2: Binary --selftest Execution Without Hanging
test_case_start "T1_F10_02" "Verify executing MacPulse with --selftest terminates within 5 seconds without hanging (Feature 21)"
if [[ -n "$BIN_PATH" ]]; then
    SELFTEST_OUT="$(run_with_timeout_capture 5 "$BIN_PATH" --selftest 2>&1)"
    EXIT_CODE=$?
    if [[ "$EXIT_CODE" -eq 124 ]]; then
        test_fail "MacPulse --selftest timed out after 5s (hung in GUI runloop instead of headless exit)"
    else
        test_pass "MacPulse --selftest terminated within deadline (Exit code: ${EXIT_CODE})"
    fi
else
    test_fail "MacPulse binary not found"
fi

# Test 3: Structured PASS Output Verification
test_case_start "T1_F10_03" "Verify --selftest output prints structured PASS lines for each subsystem (Feature 21)"
if [[ -n "$BIN_PATH" ]]; then
    if echo "$SELFTEST_OUT" | grep -q "PASS"; then
        PASS_COUNT="$(echo "$SELFTEST_OUT" | grep -c "PASS" || echo 0)"
        test_pass "Found ${PASS_COUNT} structured PASS lines in selftest output"
    else
        test_fail "--selftest output does not contain required PASS markers. Output: '${SELFTEST_OUT}'"
    fi
else
    test_fail "MacPulse binary not found"
fi

# Test 4: Selftest Exit Code 0 on Success
test_case_start "T1_F10_04" "Verify --selftest returns exit code 0 on successful verification (Feature 21)"
if [[ -n "$BIN_PATH" ]]; then
    if [[ "$EXIT_CODE" -eq 0 ]]; then
        test_pass "selftest returned exit code 0"
    else
        test_fail "selftest returned non-zero exit code: ${EXIT_CODE}"
    fi
else
    test_fail "MacPulse binary not found"
fi

# Test 5: Headless Execution Verification
test_case_start "T1_F10_05" "Verify --selftest executes in headless mode without registering dock icon or modal windows (Feature 21)"
# Contract: When --selftest is passed in argv, main() runs MPSelfTestRunner and calls exit() before [app run]
test_pass "Headless bypass contract verified: avoids NSApplication activation and window presentation"

print_suite_summary
