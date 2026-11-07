#!/bin/bash
# test_harness.sh — Shared assertion and reporting framework for MacPulse E2E tests
# Author: test_writer_e2e_1
# Constraints: Plain English output only. Zero Bangla/Bengali characters.

set -u

# Terminal styling
if [[ -t 1 ]]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_GREEN='\033[32m'
    C_RED='\033[31m'
    C_YELLOW='\033[33m'
    C_BLUE='\033[34m'
    C_CYAN='\033[36m'
else
    C_RESET=''
    C_BOLD=''
    C_GREEN=''
    C_RED=''
    C_YELLOW=''
    C_BLUE=''
    C_CYAN=''
fi

# Test Execution Counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

CURRENT_TEST_ID=""
CURRENT_TEST_DESC=""

# Temporary directory for test execution
TEST_TEMP_DIR="$(mktemp -d /tmp/macpulse_test.XXXXXX)"

cleanup_harness() {
    local exit_code=$?
    # Terminate any child processes launched by this test run
    if [[ -n "${TRACKED_PIDS:-}" ]]; then
        for pid in $TRACKED_PIDS; do
            if kill -0 "$pid" 2>/dev/null; then
                kill -TERM "$pid" 2>/dev/null || true
                sleep 0.1
                kill -9 "$pid" 2>/dev/null || true
            fi
        done
    fi
    rm -rf "$TEST_TEMP_DIR"
    exit $exit_code
}
trap cleanup_harness EXIT INT TERM

TRACKED_PIDS=""

track_pid() {
    local pid="$1"
    TRACKED_PIDS="${TRACKED_PIDS} $pid"
}

untrack_pid() {
    local target_pid="$1"
    local new_pids=""
    for pid in $TRACKED_PIDS; do
        if [[ "$pid" != "$target_pid" ]]; then
            new_pids="${new_pids} $pid"
        fi
    done
    TRACKED_PIDS="$new_pids"
}

test_suite_start() {
    local name="$1"
    echo -e "${C_BOLD}${C_BLUE}================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}SUITE: ${name}${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}================================================================${C_RESET}"
}

test_case_start() {
    local id="$1"
    local desc="$2"
    CURRENT_TEST_ID="$id"
    CURRENT_TEST_DESC="$desc"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    echo -e "${C_CYAN}[RUN ]${C_RESET} ${CURRENT_TEST_ID}: ${CURRENT_TEST_DESC}"
}

test_pass() {
    local details="${1:-}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    if [[ -n "$details" ]]; then
        echo -e "${C_GREEN}[PASS]${C_RESET} ${CURRENT_TEST_ID} — ${details}"
    else
        echo -e "${C_GREEN}[PASS]${C_RESET} ${CURRENT_TEST_ID}"
    fi
}

test_fail() {
    local reason="$1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${C_RED}[FAIL]${C_RESET} ${CURRENT_TEST_ID} — ${reason}"
}

test_skip() {
    local reason="$1"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    echo -e "${C_YELLOW}[SKIP]${C_RESET} ${CURRENT_TEST_ID} — ${reason}"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-Values should be equal}"
    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        test_fail "${msg} (Expected: '${expected}', Got: '${actual}')"
        return 1
    fi
}

assert_not_equals() {
    local unexpected="$1"
    local actual="$2"
    local msg="${3:-Values should not be equal}"
    if [[ "$unexpected" != "$actual" ]]; then
        return 0
    else
        test_fail "${msg} (Unexpected value: '${actual}')"
        return 1
    fi
}

assert_matches() {
    local pattern="$1"
    local actual="$2"
    local msg="${3:-String should match regex}"
    if echo "$actual" | grep -Eq "$pattern"; then
        return 0
    else
        test_fail "${msg} (Pattern: '${pattern}', Got: '${actual}')"
        return 1
    fi
}

assert_file_exists() {
    local path="$1"
    local msg="${2:-File should exist}"
    if [[ -e "$path" ]]; then
        return 0
    else
        test_fail "${msg} (File not found: '${path}')"
        return 1
    fi
}

assert_is_executable() {
    local path="$1"
    local msg="${2:-File should be executable}"
    if [[ -x "$path" ]]; then
        return 0
    else
        test_fail "${msg} (Not executable: '${path}')"
        return 1
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-Exit code should match}"
    if [[ "$expected" -eq "$actual" ]]; then
        return 0
    else
        test_fail "${msg} (Expected exit code ${expected}, Got ${actual})"
        return 1
    fi
}

run_with_timeout() {
    local timeout_secs="$1"
    shift
    python3 -c "
import subprocess, sys
try:
    res = subprocess.run(sys.argv[2:], timeout=float(sys.argv[1]))
    sys.exit(res.returncode)
except subprocess.TimeoutExpired:
    sys.exit(124)
" "$timeout_secs" "$@"
}

run_with_timeout_capture() {
    local timeout_secs="$1"
    shift
    python3 -c "
import subprocess, sys
try:
    res = subprocess.run(sys.argv[2:], timeout=float(sys.argv[1]), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.stdout:
        sys.stdout.write(res.stdout)
    if res.stderr:
        sys.stderr.write(res.stderr)
    sys.exit(res.returncode)
except subprocess.TimeoutExpired:
    sys.stderr.write('Command timed out after ' + sys.argv[1] + ' seconds\n')
    sys.exit(124)
" "$timeout_secs" "$@"
}

print_suite_summary() {
    echo ""
    echo -e "${C_BOLD}Test Execution Summary:${C_RESET}"
    echo -e "  Total:   ${TESTS_TOTAL}"
    echo -e "  ${C_GREEN}Passed:  ${TESTS_PASSED}${C_RESET}"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "  ${C_RED}Failed:  ${TESTS_FAILED}${C_RESET}"
    else
        echo -e "  Failed:  0"
    fi
    if [[ $TESTS_SKIPPED -gt 0 ]]; then
        echo -e "  ${C_YELLOW}Skipped: ${TESTS_SKIPPED}${C_RESET}"
    fi
    echo ""
    if [[ $TESTS_FAILED -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}
