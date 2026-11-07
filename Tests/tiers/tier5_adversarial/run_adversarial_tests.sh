#!/bin/bash
# run_adversarial_tests.sh — Master Tier 5 Adversarial & Empirical Stress Test Suite
# Constraints: Plain English output only. Zero Bangla/Bengali characters.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BIN_DIR="$PROJECT_ROOT/build/bin"
mkdir -p "$BIN_DIR"

echo "=================================================================="
echo "      MacPulse Tier 5 Adversarial & Empirical Stress Suite        "
echo "=================================================================="

# 1. Compile test harnesses
echo "⚡ Compiling test_power_manager_stress..."
xcrun clang -fobjc-arc -O2 \
    -arch arm64 \
    -mmacosx-version-min=13.0 \
    -framework Cocoa -framework IOKit \
    -I"$PROJECT_ROOT/Sources/MacPulseNative" \
    "$PROJECT_ROOT/Sources/MacPulseNative/MPPowerManager.m" \
    "$SCRIPT_DIR/test_power_manager_stress.m" \
    -o "$BIN_DIR/test_power_manager_stress"

echo "⚡ Compiling test_arbiter_exhaustive_matrix..."
xcrun clang -fobjc-arc -O2 \
    -arch arm64 \
    -mmacosx-version-min=13.0 \
    -framework Cocoa -framework IOKit \
    -I"$PROJECT_ROOT/Sources/MacPulseNative" \
    "$PROJECT_ROOT/Sources/MacPulseNative/MPPowerManager.m" \
    "$PROJECT_ROOT/Sources/MacPulseNative/MPAppSettings.m" \
    "$PROJECT_ROOT/Sources/MacPulseNative/MPPowerSourceMonitor.m" \
    "$PROJECT_ROOT/Sources/MacPulseNative/MPPriorityArbiter.m" \
    "$SCRIPT_DIR/test_arbiter_exhaustive_matrix.m" \
    -o "$BIN_DIR/test_arbiter_exhaustive_matrix"

echo "⚡ Compiling test_debounce_stress..."
xcrun clang -fobjc-arc -O2 \
    -arch arm64 \
    -mmacosx-version-min=13.0 \
    -framework Cocoa -framework IOKit \
    -I"$PROJECT_ROOT/Sources/MacPulseNative" \
    "$PROJECT_ROOT/Sources/MacPulseNative/MPPowerSourceMonitor.m" \
    "$SCRIPT_DIR/test_debounce_stress.m" \
    -o "$BIN_DIR/test_debounce_stress"

echo "✅ All test harnesses compiled successfully."
echo ""

# 2. Run Stress Test 1: MPPowerManager Concurrency & Idempotency
echo "------------------------------------------------------------------"
echo "Running Stress Test 1: MPPowerManager Concurrency & Idempotency"
echo "------------------------------------------------------------------"
"$BIN_DIR/test_power_manager_stress"
echo "✅ Stress Test 1 Passed."
echo ""

# 3. Run Stress Test 2: MPPriorityArbiter Exhaustive State Matrix
echo "------------------------------------------------------------------"
echo "Running Stress Test 2: MPPriorityArbiter Exhaustive State Matrix"
echo "------------------------------------------------------------------"
"$BIN_DIR/test_arbiter_exhaustive_matrix"
echo "✅ Stress Test 2 Passed."
echo ""

# 4. Run Stress Test 3: MPPowerSourceMonitor Debounce
echo "------------------------------------------------------------------"
echo "Running Stress Test 3: MPPowerSourceMonitor Debounce"
echo "------------------------------------------------------------------"
"$BIN_DIR/test_debounce_stress"
echo "✅ Stress Test 3 Passed."
echo ""

# 5. Run Stress Test 4: Kernel Power Assertion Lifecycle Verification
echo "------------------------------------------------------------------"
echo "Running Stress Test 4: Kernel Power Assertion Lifecycle"
echo "------------------------------------------------------------------"
"$SCRIPT_DIR/test_pmset_lifecycle.sh"
echo "✅ Stress Test 4 Passed."
echo ""

echo "=================================================================="
echo "    >>> ALL TIER 5 ADVERSARIAL STRESS TESTS PASSED CLEANLY <<<    "
echo "=================================================================="
