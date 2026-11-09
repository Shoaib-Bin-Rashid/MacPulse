#!/bin/bash
# test_install_transaction.sh — Step 2.3: Comprehensive Installation Transaction Safety Suite
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
export MACPULSE_LEGACY_DIR="$TEST_SANDBOX/UserApplications"
mkdir -p "$MACPULSE_INSTALL_DIR" "$MACPULSE_LEGACY_DIR"

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
echo "      MacPulse Step 2.3 — Install Transaction Hardening Tests     "
echo "=================================================================="
echo "Target Sandbox: $MACPULSE_INSTALL_DIR"
echo "Legacy Sandbox: $MACPULSE_LEGACY_DIR"
echo ""

# Ensure build/MacPulse.app is compiled first
echo "⚡ Preparing base build/MacPulse.app..."
"$BUILD_SCRIPT" >/dev/null
echo ""

# Helper to deploy a valid MacPulse bundle with marker
deploy_valid_app() {
    local dest="$1"
    local marker_name="$2"
    rm -rf "$dest"
    cp -R "$PROJECT_ROOT/build/MacPulse.app" "$dest"
    echo "MARKER_$marker_name" > "$dest/Contents/Resources/$marker_name"
    codesign --force --sign - "$dest" >/dev/null 2>&1 || true
}

# ----------------------------------------------------------------------
# Test 1: Clean Install (No Existing Installation)
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
# Test 2: Existing Installation (Preservation & Atomic Replacement)
# ----------------------------------------------------------------------
echo ">>> Test 2: Existing Installation Preservation & Atomic Replacement..."
deploy_valid_app "$MACPULSE_INSTALL_DIR/MacPulse.app" "v1_marker.txt"
OUT=$("$BUILD_SCRIPT" --install 2>&1 || true)
if [[ -d "$MACPULSE_INSTALL_DIR/MacPulse.app" ]] && [[ ! -f "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Resources/v1_marker.txt" ]]; then
    assert_pass "Atomic upgrade succeeded and superseded old version cleanly"
else
    assert_fail "Atomic replacement failed or old marker persisted: $OUT"
fi

# Place stable known-good marker
echo "ORIGINAL_INSTALL" > "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Resources/original_marker.txt"
codesign --force --sign - "$MACPULSE_INSTALL_DIR/MacPulse.app" >/dev/null 2>&1 || true

# ----------------------------------------------------------------------
# Test 3: Pre-Swap Failure: Invalid Staged Info.plist
# ----------------------------------------------------------------------
echo ">>> Test 3: Pre-Swap Failure: Invalid Staged Info.plist..."
OUT=$(MACPULSE_FAIL_INJECT_STAGE_PLIST=1 "$BUILD_SCRIPT" --install 2>&1 || true)
if [[ -f "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Resources/original_marker.txt" ]]; then
    assert_pass "Pre-swap Info.plist failure aborted without modifying existing installation"
else
    assert_fail "Pre-swap failure corrupted existing installation!"
fi

# ----------------------------------------------------------------------
# Test 4: Pre-Swap Failure: Invalid Architecture
# ----------------------------------------------------------------------
echo ">>> Test 4: Pre-Swap Failure: Invalid Architecture..."
OUT=$(MACPULSE_FAIL_INJECT_STAGE_ARCH=1 "$BUILD_SCRIPT" --install 2>&1 || true)
if [[ -f "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Resources/original_marker.txt" ]]; then
    assert_pass "Pre-swap architecture failure aborted without modifying existing installation"
else
    assert_fail "Pre-swap architecture failure corrupted existing installation!"
fi

# ----------------------------------------------------------------------
# Test 5: Pre-Swap Failure: Staging Copy Failure
# ----------------------------------------------------------------------
echo ">>> Test 5: Pre-Swap Failure: Staging Copy Failure..."
OUT=$(MACPULSE_FAIL_INJECT_COPY=1 "$BUILD_SCRIPT" --install 2>&1 || true)
if [[ -f "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Resources/original_marker.txt" ]]; then
    assert_pass "Staging copy failure aborted and preserved existing installation"
else
    assert_fail "Staging copy failure corrupted existing installation!"
fi

# ----------------------------------------------------------------------
# Test 6: Swap / Rename Failure Rollback
# ----------------------------------------------------------------------
echo ">>> Test 6: Swap / Rename Failure Rollback..."
OUT=$(MACPULSE_FAIL_INJECT_SWAP=1 "$BUILD_SCRIPT" --install 2>&1 || true)
if [[ -f "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Resources/original_marker.txt" ]]; then
    assert_pass "Rename failure automatically rolled back and restored original installation"
else
    assert_fail "Rename failure did not restore original installation! Details: $OUT"
fi

# ----------------------------------------------------------------------
# Test 7: Post-Swap Verification Failure (MACPULSE_FAIL_INJECT_VERIFY)
# ----------------------------------------------------------------------
echo ">>> Test 7: Post-Swap Verification Failure (Rollback)..."
OUT=$(MACPULSE_FAIL_INJECT_VERIFY=1 "$BUILD_SCRIPT" --install 2>&1 || true)
if [[ -f "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Resources/original_marker.txt" ]]; then
    assert_pass "Post-swap verification failure triggered automatic rollback to original application"
else
    assert_fail "Post-swap verification failure did not restore original installation! Details: $OUT"
fi

# ----------------------------------------------------------------------
# Test 8: SIGTERM Signal Interruption Rollback
# ----------------------------------------------------------------------
echo ">>> Test 8: SIGTERM Signal Interruption Rollback..."
OUT=$(MACPULSE_FAIL_INJECT_SIGTERM=1 "$BUILD_SCRIPT" --install 2>&1 || true)
if [[ -f "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Resources/original_marker.txt" ]]; then
    assert_pass "SIGTERM signal triggered trap handler and cleanly restored original installation"
else
    assert_fail "SIGTERM interrupted replacement without restoring original installation! Details: $OUT"
fi

# ----------------------------------------------------------------------
# Test 9: SIGINT Signal Interruption Rollback
# ----------------------------------------------------------------------
echo ">>> Test 9: SIGINT Signal Interruption Rollback..."
OUT=$(MACPULSE_FAIL_INJECT_SIGINT=1 "$BUILD_SCRIPT" --install 2>&1 || true)
if [[ -f "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Resources/original_marker.txt" ]]; then
    assert_pass "SIGINT signal triggered trap handler and cleanly restored original installation"
else
    assert_fail "SIGINT interrupted replacement without restoring original installation! Details: $OUT"
fi

# ----------------------------------------------------------------------
# Test 10: True SIGKILL Process Recovery
# ----------------------------------------------------------------------
echo ">>> Test 10: True SIGKILL Process Recovery..."
PAUSE_FILE="$TEST_SANDBOX/sigkill_ready.marker"
rm -f "$PAUSE_FILE"

# Launch isolated installer child process
MACPULSE_FAIL_INJECT_PAUSE_AFTER_BACKUP="$PAUSE_FILE" "$BUILD_SCRIPT" --install >/dev/null 2>&1 &
CHILD_PID=$!

# Wait deterministically for child to pause after backup
WAITED=0
while [[ ! -f "$PAUSE_FILE" && $WAITED -lt 150 ]]; do
    sleep 0.1
    WAITED=$((WAITED + 1))
done

if [[ -f "$PAUSE_FILE" ]]; then
    # Send SIGKILL strictly to the isolated child process
    kill -9 "$CHILD_PID" 2>/dev/null || true
    wait "$CHILD_PID" 2>/dev/null || true
    rm -f "$PAUSE_FILE"

    # Confirm target is absent and backup artifact exists
    if [[ ! -d "$MACPULSE_INSTALL_DIR/MacPulse.app" ]]; then
        OUT=$("$BUILD_SCRIPT" --recover 2>&1 || true)
        if [[ -d "$MACPULSE_INSTALL_DIR/MacPulse.app" && -f "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Resources/original_marker.txt" ]]; then
            assert_pass "True SIGKILL: --recover detected dead lock and restored original installation from backup"
        else
            assert_fail "True SIGKILL: --recover failed to restore application: $OUT"
        fi
    else
        assert_fail "True SIGKILL: Setup failed, target was not removed before pause"
    fi
else
    kill -9 "$CHILD_PID" 2>/dev/null || true
    assert_fail "True SIGKILL: Child failed to signal ready marker within timeout"
fi

# Re-establish stable original app
deploy_valid_app "$MACPULSE_INSTALL_DIR/MacPulse.app" "original_marker.txt"

# ----------------------------------------------------------------------
# Test 11: Corrupted Target with Valid Info.plist
# ----------------------------------------------------------------------
echo ">>> Test 11: Corrupted Target with Valid Info.plist..."
# Setup: target has valid plist but corrupt/truncated binary
deploy_valid_app "$MACPULSE_INSTALL_DIR/.MacPulse.backup.valid1.app" "original_marker.txt"
echo "CORRUPTED_BIN" > "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/MacOS/MacPulse"
OUT=$("$BUILD_SCRIPT" --recover 2>&1 || true)
if [[ -f "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Resources/original_marker.txt" ]] && lipo -info "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/MacOS/MacPulse" | grep -q "arm64"; then
    assert_pass "--recover detected corrupted binary despite valid plist and restored healthy backup"
else
    assert_fail "--recover failed to repair corrupted binary: $OUT"
fi

# ----------------------------------------------------------------------
# Test 12: Target with Missing Executable
# ----------------------------------------------------------------------
echo ">>> Test 12: Target with Missing Executable..."
deploy_valid_app "$MACPULSE_INSTALL_DIR/.MacPulse.backup.valid2.app" "original_marker.txt"
rm -f "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/MacOS/MacPulse"
OUT=$("$BUILD_SCRIPT" --recover 2>&1 || true)
if [[ -x "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/MacOS/MacPulse" ]]; then
    assert_pass "--recover detected missing executable and restored healthy backup"
else
    assert_fail "--recover failed to restore missing executable: $OUT"
fi

# ----------------------------------------------------------------------
# Test 13: Target with Incorrect Bundle Identifier
# ----------------------------------------------------------------------
echo ">>> Test 13: Target with Incorrect Bundle Identifier (Foreign App Protection)..."
deploy_valid_app "$MACPULSE_INSTALL_DIR/.MacPulse.backup.valid3.app" "backup_marker.txt"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.unrelated.foreignapp" "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Info.plist"
OUT=$("$BUILD_SCRIPT" --recover 2>&1 || true)
FOREIGN_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Info.plist" 2>/dev/null || true)
if [[ "$FOREIGN_ID" == "com.unrelated.foreignapp" && -d "$MACPULSE_INSTALL_DIR/.MacPulse.backup.valid3.app" ]]; then
    assert_pass "--recover detected foreign bundle ID, preserved foreign app, and preserved backups"
else
    assert_fail "--recover unexpectedly mutated foreign app or deleted backups: $OUT"
fi

# Clean up foreign app and restore healthy state
deploy_valid_app "$MACPULSE_INSTALL_DIR/MacPulse.app" "original_marker.txt"
rm -rf "$MACPULSE_INSTALL_DIR"/.MacPulse.backup.*.app

# ----------------------------------------------------------------------
# Test 14: Invalid Code Signature
# ----------------------------------------------------------------------
echo ">>> Test 14: Target with Invalid Code Signature..."
deploy_valid_app "$MACPULSE_INSTALL_DIR/.MacPulse.backup.valid4.app" "original_marker.txt"
# Break signature by modifying binary without resign
echo "TAMPER" >> "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/MacOS/MacPulse"
OUT=$("$BUILD_SCRIPT" --recover 2>&1 || true)
if codesign --verify --deep --strict "$MACPULSE_INSTALL_DIR/MacPulse.app" >/dev/null 2>&1; then
    assert_pass "--recover detected broken signature and restored verified backup"
else
    assert_fail "--recover failed to restore signed app: $OUT"
fi

# ----------------------------------------------------------------------
# Test 15: Wrong Architecture Slice
# ----------------------------------------------------------------------
echo ">>> Test 15: Target with Missing Universal Slice..."
deploy_valid_app "$MACPULSE_INSTALL_DIR/.MacPulse.backup.valid5.app" "original_marker.txt"
lipo -extract arm64 "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/MacOS/MacPulse" -output "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/MacOS/MacPulse.thin"
mv "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/MacOS/MacPulse.thin" "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/MacOS/MacPulse"
codesign --force --sign - "$MACPULSE_INSTALL_DIR/MacPulse.app" >/dev/null 2>&1 || true

OUT=$("$BUILD_SCRIPT" --recover 2>&1 || true)
LIPO_OUT=$(lipo -info "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/MacOS/MacPulse" 2>/dev/null || true)
if echo "$LIPO_OUT" | grep -q "arm64" && echo "$LIPO_OUT" | grep -q "x86_64"; then
    assert_pass "--recover detected non-universal architecture and restored universal binary"
else
    assert_fail "--recover failed to restore universal binary: $OUT"
fi

# ----------------------------------------------------------------------
# Test 16: Multiple Orphaned Backups (Deterministic Selection)
# ----------------------------------------------------------------------
echo ">>> Test 16: Multiple Orphaned Backups (Deterministic Selection)..."
rm -rf "$MACPULSE_INSTALL_DIR/MacPulse.app"
rm -rf "$MACPULSE_INSTALL_DIR"/.MacPulse.backup.*.app

# Backup 1: Corrupted backup
mkdir -p "$MACPULSE_INSTALL_DIR/.MacPulse.backup.100.app/Contents"
echo "CORRUPT" > "$MACPULSE_INSTALL_DIR/.MacPulse.backup.100.app/Contents/Info.plist"

# Backup 2: Older valid backup
deploy_valid_app "$MACPULSE_INSTALL_DIR/.MacPulse.backup.200.app" "older_backup.txt"
sleep 1

# Backup 3: Newer valid backup
deploy_valid_app "$MACPULSE_INSTALL_DIR/.MacPulse.backup.300.app" "newer_backup.txt"

OUT=$("$BUILD_SCRIPT" --recover 2>&1 || true)
if [[ -f "$MACPULSE_INSTALL_DIR/MacPulse.app/Contents/Resources/newer_backup.txt" ]]; then
    assert_pass "--recover deterministically selected and restored the latest valid backup"
else
    assert_fail "--recover failed deterministic candidate selection: $OUT"
fi

# ----------------------------------------------------------------------
# Test 17: Concurrent --install Invocations (Lock Contention)
# ----------------------------------------------------------------------
echo ">>> Test 17: Concurrent --install Invocations..."
LOCK_MARKER="$TEST_SANDBOX/lock_active.marker"
rm -f "$LOCK_MARKER"

# Start process 1 holding lock
MACPULSE_FAIL_INJECT_PAUSE_LOCK="$LOCK_MARKER" "$BUILD_SCRIPT" --install >/dev/null 2>&1 &
P1_PID=$!

# Wait for process 1 to acquire lock
WAITED=0
while [[ ! -f "$LOCK_MARKER" && $WAITED -lt 150 ]]; do
    sleep 0.1
    WAITED=$((WAITED + 1))
done

if [[ -f "$LOCK_MARKER" ]]; then
    # Attempt process 2 with 1s timeout
    P2_OUT=$(MACPULSE_LOCK_TIMEOUT=1 "$BUILD_SCRIPT" --install 2>&1 || true)
    P2_EXIT=$?
    
    # Terminate process 1
    kill -9 "$P1_PID" 2>/dev/null || true
    wait "$P1_PID" 2>/dev/null || true
    rm -f "$LOCK_MARKER"

    if echo "$P2_OUT" | grep -q "Another MacPulse transaction is currently active"; then
        assert_pass "Second installer detected active lock and exited safely without collision"
    else
        assert_fail "Second installer did not respect transaction lock: $P2_OUT"
    fi
else
    kill -9 "$P1_PID" 2>/dev/null || true
    assert_fail "Failed to setup lock contention marker"
fi

# ----------------------------------------------------------------------
# Test 18: --recover While Another Installation is Active
# ----------------------------------------------------------------------
echo ">>> Test 18: --recover While Installation is Active..."
LOCK_MARKER="$TEST_SANDBOX/lock_active2.marker"
rm -f "$LOCK_MARKER"

# Start installer holding lock
MACPULSE_FAIL_INJECT_PAUSE_LOCK="$LOCK_MARKER" "$BUILD_SCRIPT" --install >/dev/null 2>&1 &
P1_PID=$!

WAITED=0
while [[ ! -f "$LOCK_MARKER" && $WAITED -lt 150 ]]; do
    sleep 0.1
    WAITED=$((WAITED + 1))
done

if [[ -f "$LOCK_MARKER" ]]; then
    REC_OUT=$(MACPULSE_LOCK_TIMEOUT=1 "$BUILD_SCRIPT" --recover 2>&1 || true)
    kill -9 "$P1_PID" 2>/dev/null || true
    wait "$P1_PID" 2>/dev/null || true
    rm -f "$LOCK_MARKER"

    if echo "$REC_OUT" | grep -q "Another MacPulse transaction is currently active"; then
        assert_pass "--recover detected active installer lock and refused concurrent mutation"
    else
        assert_fail "--recover bypassed active transaction lock: $REC_OUT"
    fi
else
    kill -9 "$P1_PID" 2>/dev/null || true
    assert_fail "Failed to setup recovery lock marker"
fi

# ----------------------------------------------------------------------
# Test 19: Safe Legacy Cleanup with Foreign Application
# ----------------------------------------------------------------------
echo ">>> Test 19: --clean-legacy with Foreign Application..."
mkdir -p "$MACPULSE_LEGACY_DIR/MacPulse.app/Contents"
cat << 'EOF' > "$MACPULSE_LEGACY_DIR/MacPulse.app/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.othercompany.foreignapp</string>
</dict>
</plist>
EOF

CLEAN_OUT=$("$BUILD_SCRIPT" --clean-legacy 2>&1 || true)
if [[ -d "$MACPULSE_LEGACY_DIR/MacPulse.app" ]] && echo "$CLEAN_OUT" | grep -q "foreign CFBundleIdentifier"; then
    assert_pass "--clean-legacy detected foreign application and refused to delete it"
else
    assert_fail "--clean-legacy failed foreign app protection: $CLEAN_OUT"
fi

# ----------------------------------------------------------------------
# Test 20: Safe Legacy Cleanup with Valid MacPulse Bundle
# ----------------------------------------------------------------------
echo ">>> Test 20: --clean-legacy with Valid MacPulse Bundle..."
deploy_valid_app "$MACPULSE_LEGACY_DIR/MacPulse.app" "legacy_marker.txt"
CLEAN_OUT=$("$BUILD_SCRIPT" --clean-legacy 2>&1 || true)
if [[ ! -e "$MACPULSE_LEGACY_DIR/MacPulse.app" ]]; then
    assert_pass "--clean-legacy validated CFBundleIdentifier and removed duplicate bundle cleanly"
else
    assert_fail "--clean-legacy failed to remove valid duplicate bundle: $CLEAN_OUT"
fi

echo ""
echo "=================================================================="
echo "Test Execution Summary: $PASS_COUNT Passed, $FAIL_COUNT Failed"
echo "=================================================================="

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
fi
exit 0
