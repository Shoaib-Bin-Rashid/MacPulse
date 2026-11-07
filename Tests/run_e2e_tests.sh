#!/bin/bash
# run_e2e_tests.sh — Master E2E Test Suite Runner for MacPulse
# Author: test_writer_e2e_1
# Constraints: Plain English output only. Zero Bangla/Bengali characters.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Styling
if [[ -t 1 ]]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_GREEN='\033[32m'
    C_RED='\033[31m'
    C_YELLOW='\033[33m'
    C_CYAN='\033[36m'
    C_MAGENTA='\033[35m'
else
    C_RESET=''
    C_BOLD=''
    C_GREEN=''
    C_RED=''
    C_YELLOW=''
    C_CYAN=''
    C_MAGENTA=''
fi

TARGET_TIER="all"
FILTER_PATTERN=""
VERBOSE=false

show_help() {
    cat << EOF
MacPulse E2E Test Suite Runner

Usage:
  ./tests/run_e2e_tests.sh [options]

Options:
  --tier <1|2|3|4|all>   Run only tests belonging to specified tier (default: all)
  --filter <pattern>      Run only test files matching substring pattern
  --list                 List all available test suites without executing
  --verbose              Print verbose diagnostic output during test execution
  --help                 Show this help message

Test Tiers:
  Tier 1: Feature Coverage (>=5 per feature across isolated subsystems)
  Tier 2: Boundary & Corner Cases (0%, 10%, 20%, 50%, 100% battery, debounce, CLI args)
  Tier 3: Cross-Feature Combinations (Pairwise interactions across modes and power states)
  Tier 4: Real-World Application Scenarios (End-to-end user workflows)

EOF
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tier)
            TARGET_TIER="$2"
            shift 2
            ;;
        --filter)
            FILTER_PATTERN="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --list)
            echo "Available MacPulse E2E Test Suites:"
            find "$SCRIPT_DIR/tiers" -name "*.sh" | sort
            exit 0
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

echo -e "${C_BOLD}${C_MAGENTA}================================================================${C_RESET}"
echo -e "${C_BOLD}${C_MAGENTA}             MacPulse E2E Automated Test Suite                  ${C_RESET}"
echo -e "${C_BOLD}${C_MAGENTA}================================================================${C_RESET}"
echo "Project Root: $PROJECT_ROOT"
echo "Target Tier:  $TARGET_TIER"
if [[ -n "$FILTER_PATTERN" ]]; then
    echo "Filter:       $FILTER_PATTERN"
fi
echo ""

# Discover test files
TEST_FILES=()

add_tier() {
    local tier_dir="$1"
    if [[ -d "$tier_dir" ]]; then
        while IFS= read -r file; do
            [[ -n "$file" ]] && TEST_FILES+=("$file")
        done < <(find "$tier_dir" -name "test_*.sh" | sort)
    fi
}

case "$TARGET_TIER" in
    1)
        add_tier "$SCRIPT_DIR/tiers/tier1_features"
        ;;
    2)
        add_tier "$SCRIPT_DIR/tiers/tier2_boundaries"
        ;;
    3)
        add_tier "$SCRIPT_DIR/tiers/tier3_combinations"
        ;;
    4)
        add_tier "$SCRIPT_DIR/tiers/tier4_scenarios"
        ;;
    all)
        add_tier "$SCRIPT_DIR/tiers/tier1_features"
        add_tier "$SCRIPT_DIR/tiers/tier2_boundaries"
        add_tier "$SCRIPT_DIR/tiers/tier3_combinations"
        add_tier "$SCRIPT_DIR/tiers/tier4_scenarios"
        ;;
    *)
        echo "Error: Invalid tier '$TARGET_TIER'. Expected 1, 2, 3, 4, or all."
        exit 1
        ;;
esac

# Apply filter pattern if specified
FINAL_TEST_FILES=()
for tf in "${TEST_FILES[@]}"; do
    if [[ -z "$FILTER_PATTERN" ]] || echo "$tf" | grep -q "$FILTER_PATTERN"; then
        FINAL_TEST_FILES+=("$tf")
    fi
done

TOTAL_SUITES=${#FINAL_TEST_FILES[@]}
if [[ $TOTAL_SUITES -eq 0 ]]; then
    echo -e "${C_YELLOW}No test suites found matching criteria.${C_RESET}"
    exit 0
fi

echo -e "Found ${C_BOLD}${TOTAL_SUITES}${C_RESET} test suite script(s) to execute."
echo ""

SUITES_PASSED=0
SUITES_FAILED=0
TOTAL_CASES_PASSED=0
TOTAL_CASES_FAILED=0
TOTAL_CASES_SKIPPED=0

START_TIME=$(date +%s)

for script in "${FINAL_TEST_FILES[@]}"; do
    rel_path="${script#$SCRIPT_DIR/}"
    echo -e "${C_CYAN}Running suite: ${rel_path}${C_RESET}"

    # Ensure executable
    chmod +x "$script"

    # Run suite script and capture output
    OUTPUT_FILE="$(mktemp /tmp/suite_out.XXXXXX)"
    if $VERBOSE; then
        "$script" 2>&1 | tee "$OUTPUT_FILE"
        SUITE_EXIT=${PIPESTATUS[0]}
    else
        "$script" > "$OUTPUT_FILE" 2>&1
        SUITE_EXIT=$?
    fi

    # Parse counts from output
    CASES_P=$(grep -c "\[PASS\]" "$OUTPUT_FILE" 2>/dev/null || true)
    CASES_P=${CASES_P:-0}
    CASES_F=$(grep -c "\[FAIL\]" "$OUTPUT_FILE" 2>/dev/null || true)
    CASES_F=${CASES_F:-0}
    CASES_S=$(grep -c "\[SKIP\]" "$OUTPUT_FILE" 2>/dev/null || true)
    CASES_S=${CASES_S:-0}

    TOTAL_CASES_PASSED=$((TOTAL_CASES_PASSED + CASES_P))
    TOTAL_CASES_FAILED=$((TOTAL_CASES_FAILED + CASES_F))
    TOTAL_CASES_SKIPPED=$((TOTAL_CASES_SKIPPED + CASES_S))

    if [[ $SUITE_EXIT -eq 0 && $CASES_F -eq 0 ]]; then
        SUITES_PASSED=$((SUITES_PASSED + 1))
        echo -e "  ↳ ${C_GREEN}Suite Passed${C_RESET} (${CASES_P} passed, ${CASES_S} skipped)"
    else
        SUITES_FAILED=$((SUITES_FAILED + 1))
        echo -e "  ↳ ${C_RED}Suite Failed${C_RESET} (${CASES_F} failed, ${CASES_P} passed)"
        if ! $VERBOSE; then
            echo -e "${C_RED}--- Failure Output for ${rel_path} ---${C_RESET}"
            grep -E "\[FAIL\]|ERROR" "$OUTPUT_FILE" || cat "$OUTPUT_FILE"
            echo -e "${C_RED}---------------------------------------${C_RESET}"
        fi
    fi
    rm -f "$OUTPUT_FILE"
    echo ""
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo -e "${C_BOLD}${C_MAGENTA}================================================================${C_RESET}"
echo -e "${C_BOLD}${C_MAGENTA}                   Overall Test Execution Summary               ${C_RESET}"
echo -e "${C_BOLD}${C_MAGENTA}================================================================${C_RESET}"
echo -e "Duration:               ${DURATION}s"
echo -e "Total Suites Executed:  ${TOTAL_SUITES}"
echo -e "  ${C_GREEN}Suites Passed:        ${SUITES_PASSED}${C_RESET}"
if [[ $SUITES_FAILED -gt 0 ]]; then
    echo -e "  ${C_RED}Suites Failed:        ${SUITES_FAILED}${C_RESET}"
else
    echo -e "  Suites Failed:        0"
fi
echo ""
TOTAL_CASES=$((TOTAL_CASES_PASSED + TOTAL_CASES_FAILED + TOTAL_CASES_SKIPPED))
echo -e "Total Test Cases:       ${TOTAL_CASES}"
echo -e "  ${C_GREEN}Cases Passed:         ${TOTAL_CASES_PASSED}${C_RESET}"
if [[ $TOTAL_CASES_FAILED -gt 0 ]]; then
    echo -e "  ${C_RED}Cases Failed:         ${TOTAL_CASES_FAILED}${C_RESET}"
else
    echo -e "  Cases Failed:         0"
fi
if [[ $TOTAL_CASES_SKIPPED -gt 0 ]]; then
    echo -e "  ${C_YELLOW}Cases Skipped:        ${TOTAL_CASES_SKIPPED}${C_RESET}"
fi
echo -e "${C_BOLD}${C_MAGENTA}================================================================${C_RESET}"

if [[ $SUITES_FAILED -eq 0 && $TOTAL_CASES_FAILED -eq 0 ]]; then
    echo -e "${C_BOLD}${C_GREEN}>>> ALL MACPULSE E2E TESTS PASSED SUCCESSFULLY! <<<${C_RESET}"
    exit 0
else
    echo -e "${C_BOLD}${C_RED}>>> MACPULSE E2E TEST RUN ENCOUNTERED FAILURES <<<${C_RESET}"
    exit 1
fi
