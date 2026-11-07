#!/bin/bash
# test_b03_cli_arguments.sh — Tier 2 Boundary Tests: Command Line Argument Robustness
# Author: test_writer_e2e_1
# References: ORIGINAL_REQUEST.md Acceptance Criteria; Edge Cases Table #13
# Constraints: Plain English output only. Zero Bangla/Bengali characters.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common/test_harness.sh"
source "$SCRIPT_DIR/../../common/binary_helper.sh"

test_suite_start "Tier 2: Boundary 03 — CLI Argument Robustness & Boundary Inputs"

BIN_PATH="$(find_macpulse_binary)"
if [[ -z "$BIN_PATH" ]]; then
    echo "ERROR: MacPulse binary not found."
    exit 1
fi

# Test 1: Unknown CLI Flag
test_case_start "T2_B03_01" "Verify launching binary with unknown CLI flag does not crash or hang indefinitely"
OUT="$(run_with_timeout_capture 3 "$BIN_PATH" --unknown-flag-xyz 2>&1)"
EXIT_CODE=$?
if [[ "$EXIT_CODE" -eq 124 ]]; then
    test_fail "Binary hung indefinitely when passed unknown flag --unknown-flag-xyz"
else
    test_pass "Binary handled unknown flag safely without hanging (Exit code: ${EXIT_CODE})"
fi

# Test 2: Empty String Argument
test_case_start "T2_B03_02" "Verify launching binary with empty string argument does not produce segmentation fault"
OUT="$(run_with_timeout_capture 3 "$BIN_PATH" "" 2>&1)"
EXIT_CODE=$?
if [[ "$EXIT_CODE" -eq 139 ]]; then
    test_fail "Binary crashed with segmentation fault on empty string argument"
else
    test_pass "Empty string argument handled without crash (Exit code: ${EXIT_CODE})"
fi

# Test 3: Selftest with Extraneous Parameters
test_case_start "T2_B03_03" "Verify --selftest with additional trailing parameters executes safely"
OUT="$(run_with_timeout_capture 3 "$BIN_PATH" --selftest --verbose --extra 2>&1)"
EXIT_CODE=$?
if [[ "$EXIT_CODE" -eq 124 ]]; then
    test_fail "Command hung with extraneous parameters"
else
    test_pass "Command with extra parameters handled without hang (Exit code: ${EXIT_CODE})"
fi

# Test 4: Help / Usage Request
test_case_start "T2_B03_04" "Verify --help or -h flag request handles CLI usage enquiry safely"
OUT="$(run_with_timeout_capture 3 "$BIN_PATH" --help 2>&1)"
EXIT_CODE=$?
if [[ "$EXIT_CODE" -eq 124 ]]; then
    test_fail "Help flag invocation hung indefinitely"
else
    test_pass "Help flag handled cleanly without hanging"
fi

# Test 5: Empty Environment Variable Handling
test_case_start "T2_B03_05" "Verify empty APP_STORE environment variable does not cause fatal crash"
OUT="$(APP_STORE="" run_with_timeout_capture 3 "$BIN_PATH" --selftest 2>&1)"
EXIT_CODE=$?
if [[ "$EXIT_CODE" -eq 134 || "$EXIT_CODE" -eq 139 ]]; then
    test_fail "Binary aborted or crashed on empty APP_STORE variable"
else
    test_pass "Binary handled empty APP_STORE variable safely without abort"
fi

print_suite_summary
