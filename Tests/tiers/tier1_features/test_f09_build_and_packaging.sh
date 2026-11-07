#!/bin/bash
# test_f09_build_and_packaging.sh — Tier 1 Feature Tests: Universal Compilation & Packaging
# Author: test_writer_e2e_1
# References: ORIGINAL_REQUEST.md R5; PROJECT.md Features 19, 20
# Constraints: Plain English output only. Zero Bangla/Bengali characters.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common/test_harness.sh"
source "$SCRIPT_DIR/../../common/binary_helper.sh"

test_suite_start "Tier 1: Feature 09 — Universal Compilation & Packaging"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BIN_PATH="$(find_macpulse_binary)"
BUILD_SCRIPT="$PROJECT_ROOT/build.sh"
PACKAGE_SCRIPT="$PROJECT_ROOT/scripts/package.sh"
DMG_PATH="$PROJECT_ROOT/dist/MacPulse.dmg"

# Test 1: build.sh Executable Verification
test_case_start "T1_F09_01" "Verify build.sh script exists and has executable permissions (R5, Feature 19)"
if [[ -x "$BUILD_SCRIPT" ]]; then
    test_pass "build.sh exists and is executable"
else
    test_fail "build.sh missing or not executable at ${BUILD_SCRIPT}"
fi

# Test 2: Binary arm64 Architecture Slice
test_case_start "T1_F09_02" "Verify compiled binary contains arm64 architecture slice (R5, Feature 19)"
if [[ -n "$BIN_PATH" ]]; then
    ARCHES="$(get_binary_architectures "$BIN_PATH")"
    if echo "$ARCHES" | grep -qw "arm64"; then
        test_pass "arm64 architecture slice verified (Detected: ${ARCHES})"
    else
        test_fail "arm64 slice missing from binary: ${ARCHES}"
    fi
else
    test_fail "MacPulse binary not found"
fi

# Test 3: Binary x86_64 Architecture Slice (Universal Fat Binary)
test_case_start "T1_F09_03" "Verify compiled binary contains x86_64 architecture slice for Intel compatibility (R5, Feature 19)"
if [[ -n "$BIN_PATH" ]]; then
    ARCHES="$(get_binary_architectures "$BIN_PATH")"
    if echo "$ARCHES" | grep -qw "x86_64"; then
        test_pass "x86_64 architecture slice verified (Detected: ${ARCHES})"
    else
        test_fail "x86_64 slice missing; binary is single-architecture (Detected: ${ARCHES}, required: Universal fat binary arm64+x86_64)"
    fi
else
    test_fail "MacPulse binary not found"
fi

# Test 4: Packaging Script Executable Verification
test_case_start "T1_F09_04" "Verify scripts/package.sh exists and is executable (R5, Feature 20)"
if [[ -x "$PACKAGE_SCRIPT" ]]; then
    test_pass "scripts/package.sh exists and is executable"
else
    test_fail "scripts/package.sh missing or not executable at ${PACKAGE_SCRIPT}"
fi

# Test 5: DMG Disk Image Structure Verification
test_case_start "T1_F09_05" "Verify dist/MacPulse.dmg is a valid UDZO disk image containing MacPulse.app (R5, Feature 20)"
if [[ -f "$DMG_PATH" ]]; then
    MOUNT_DIR="${TEST_TEMP_DIR}/dmg_mount"
    mkdir -p "$MOUNT_DIR"
    ATTACH_OUT="$(hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_DIR" "$DMG_PATH" 2>&1 || true)"
    if [[ -d "$MOUNT_DIR/MacPulse.app" ]]; then
        test_pass "MacPulse.dmg attached successfully and contains MacPulse.app"
    else
        test_fail "MacPulse.app not found inside mounted DMG image: ${ATTACH_OUT}"
    fi
    hdiutil detach "$MOUNT_DIR" -force > /dev/null 2>&1 || true
else
    test_fail "DMG image not found at ${DMG_PATH}"
fi

print_suite_summary
