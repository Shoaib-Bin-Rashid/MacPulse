#!/bin/bash
# test_install_transaction.sh — Step 2.2: Comprehensive Installation Transaction Safety Suite
# Author: shoaib
# Constraints: Plain English output only. Zero Bangla/Bengali characters.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_SCRIPT="$PROJECT_ROOT/build.sh"

TEST_SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/macpulse_tx_test.XXXXXX")"
cleanup() {
    rm -rf "$TEST_SANDBOX"
}
trap cleanup EXIT INT TERM

export MACPULSE_INSTALL_DIR="$TEST_SANDBOX/Applications"
mkdir -p "$MACPULSE_INSTALL_DIR"

PASS_COUNT=0
FAIL_COUNT=0

assert_pass() {
    echo "  ✅ [PASS] $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

assert_fail() {
    echo "  ❌ [FAIL] $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

echo "=================================================================="
echo "      MacPulse Step 2.2 — Install Transaction Safety Tests        "
echo "=================================================================="
echo "Target Sandbox: $MACPULSE_INSTALL_DIR"
echo ""

# Ensure build/MacPulse.app is compiled first
echo "⚡ Preparing base build/MacPulse.app..."
"$BUILD_SCRIPT" >/dev/null
echo ""

# ----------------------------------------------------------------------
# Test 1: No existing installation (Clean Install)
# ----------------------------------------------------------------------
echo ">>> Test 1: Clean Install (No Existing Installation)..."
rm -rf "$MACPULSE_INSTALL_DIR/MacPulse.app"
OUT=$("$BUILD_SCRIPT" --install 2>&1 || true)
if [[ -d "$MACPULSE_INSTALL_DIR/MacPulse.app" ]] && plutil -lint "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Info.plist" >/dev/null 2>&1; then
    assert_pass "Clean installation succeeded into empty directory"
else
    assert_fail "Clean installation failed to deploy valid app bundle: $OUT"
fi

# ----------------------------------------------------------------------
# Test 2: Existing installation (Preservation & Replacement)
# ----------------------------------------------------------------------
echo ">>> Test 2: Existing Installation Preservation..."
# Create a marker inside existing installation
touch "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Resources/marker_v1.txt"
if [[ -f "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Resources/marker_v1.txt" ]]; then
    assert_pass "Marker placed in existing installation"
else
    assert_fail "Failed to place marker"
fi

# ----------------------------------------------------------------------
# Test 3: Successful replacement (Upgrade from v1 to v2)
# ----------------------------------------------------------------------
echo ">>> Test 3: Successful Replacement (Atomic Upgrade)..."
OUT=$("$BUILD_SCRIPT" --install 2>&1 || true)
if [[ -d "$MACPULSE_INSTALL_DIR/MacPulse.app" ]] && [[ ! -f "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Resources/marker_v1.txt" ]]; then
    assert_pass "Target successfully replaced with clean new bundle (marker cleanly superseded)"
else
    assert_fail "Replacement failed or marker unexpectedly lingered: $OUT"
fi

# Place a fresh marker representing existing good installation
echo "ORIGINAL_INSTALL" > "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Resources/original_marker.txt"

# ----------------------------------------------------------------------
# Test 4: Invalid staged Info.plist (Pre-Swap Validation Failure)
# ----------------------------------------------------------------------
echo ">>> Test 4: Invalid Staged Info.plist (Pre-Swap Failure)..."
OUT=$(MACPULSE_FAIL_INJECT_STAGE_PLIST=1 "$BUILD_SCRIPT" --install 2>&1 || true)
if [[ -f "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Resources/original_marker.txt" ]]; then
    assert_pass "Pre-swap Info.plist failure aborted without modifying existing installation"
else
    assert_fail "Pre-swap failure corrupted or deleted existing installation!"
fi

# ----------------------------------------------------------------------
# Test 5: Invalid architecture (Pre-Swap Architecture Failure)
# ----------------------------------------------------------------------
echo ">>> Test 5: Invalid Architecture (Missing Slice Pre-Swap Failure)..."
OUT=$(MACPULSE_FAIL_INJECT_STAGE_ARCH=1 "$BUILD_SCRIPT" --install 2>&1 || true)
if [[ -f "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Resources/original_marker.txt" ]]; then
    assert_pass "Pre-swap architecture failure aborted without modifying existing installation"
else
    assert_fail "Pre-swap architecture failure corrupted existing installation!"
fi

# ----------------------------------------------------------------------
# Test 6: Simulated Copy Failure (Staging Failure)
# ----------------------------------------------------------------------
echo ">>> Test 6: Simulated Copy Failure During Staging..."
OUT=$(MACPULSE_FAIL_INJECT_COPY=1 "$BUILD_SCRIPT" --install 2>&1 || true)
if [[ -f "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Resources/original_marker.txt" ]]; then
    assert_pass "Staging copy failure aborted and preserved existing installation"
else
    assert_fail "Staging copy failure corrupted existing installation!"
fi

# ----------------------------------------------------------------------
# Test 7: Simulated Rename / Swap Failure (Rollback from Backup)
# ----------------------------------------------------------------------
echo ">>> Test 7: Simulated Rename/Swap Failure (Automatic Rollback)..."
OUT=$(MACPULSE_FAIL_INJECT_SWAP=1 "$BUILD_SCRIPT" --install 2>&1 || true)
if [[ -f "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Resources/original_marker.txt" ]]; then
    assert_pass "Rename failure automatically rolled back and restored original installation"
else
    assert_fail "Rename failure did not restore original installation! Details: $OUT"
fi

# ----------------------------------------------------------------------
# Test 8: SIGTERM During Replacement (Trap Handler Rollback)
# ----------------------------------------------------------------------
echo ">>> Test 8: SIGTERM Interruption During Replacement..."
OUT=$(MACPULSE_FAIL_INJECT_SIGTERM=1 "$BUILD_SCRIPT" --install 2>&1 || true)
if [[ -f "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Resources/original_marker.txt" ]]; then
    assert_pass "SIGTERM signal triggered trap handler and cleanly restored original installation"
else
    assert_fail "SIGTERM interrupted replacement without restoring original installation! Details: $OUT"
fi

# ----------------------------------------------------------------------
# Test 9: SIGINT During Replacement (Trap Handler Rollback)
# ----------------------------------------------------------------------
echo ">>> Test 9: SIGINT Interruption During Replacement..."
OUT=$(MACPULSE_FAIL_INJECT_SIGINT=1 "$BUILD_SCRIPT" --install 2>&1 || true)
if [[ -f "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Resources/original_marker.txt" ]]; then
    assert_pass "SIGINT signal triggered trap handler and cleanly restored original installation"
else
    assert_fail "SIGINT interrupted replacement without restoring original installation! Details: $OUT"
fi

# ----------------------------------------------------------------------
# Test 10: Process Interruption Recovery (--recover)
# ----------------------------------------------------------------------
echo ">>> Test 10: Post-Crash Recovery (--recover)..."
# Simulate an untrapped hard crash (e.g. power loss or SIGKILL) where target is missing and backup remains
FAKE_BACKUP="$MACPULSE_INSTALL_DIR/.MacPulse.backup.99999.app"
mv "$MACPULSE_INSTALL_DIR/MacPulse.app" "$FAKE_BACKUP"
if [[ ! -d "$MACPULSE_INSTALL_DIR/MacPulse.app" && -d "$FAKE_BACKUP" ]]; then
    OUT=$("$BUILD_SCRIPT" --recover 2>&1 || true)
    if [[ -d "$MACPULSE_INSTALL_DIR/MacPulse.app" && -f "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Resources/original_marker.txt" ]]; then
        assert_pass "--recover detected lingering backup and restored the application"
    else
        assert_fail "--recover failed to restore application from backup: $OUT"
    fi
else
    assert_fail "Failed to setup simulation for Test 10"
fi

# ----------------------------------------------------------------------
# Test 11: Guard Against Overwriting Unrelated Applications
# ----------------------------------------------------------------------
echo ">>> Test 11: Protection Against Overwriting Unrelated Applications..."
# Create a dummy foreign application in target
FOREIGN_APP="$MACPULSE_INSTALL_DIR/MacPulse.app"
rm -rf "$FOREIGN_APP"
mkdir -p "$FOREIGN_APP/Contents"
cat << 'EOF' > "$FOREIGN_APP/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.othercompany.differentapp</string>
    <key>CFBundleName</key>
    <string>DifferentApp</string>
</dict>
</plist>
EOF

OUT=$("$BUILD_SCRIPT" --install 2>&1 || true)
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$FOREIGN_APP/Contents/Info.plist" 2>/dev/null || true)
if [[ "$BUNDLE_ID" == "com.othercompany.differentapp" ]]; then
    assert_pass "Refused to overwrite unrelated application (retained com.othercompany.differentapp)"
else
    assert_fail "Failed to protect unrelated application! Overwritten: $OUT"
fi

echo ""
echo "=================================================================="
echo "Test Execution Summary: $PASS_COUNT Passed, $FAIL_COUNT Failed"
echo "=================================================================="

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
fi
exit 0
