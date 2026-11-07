#!/bin/bash
# test_pmset_lifecycle.sh — Empirical Kernel Power Assertion & Lifecycle Verification
# Constraints: Plain English output only. Zero Bangla/Bengali characters.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BIN_PATH="$PROJECT_ROOT/build/bin/MacPulse"

if [[ ! -x "$BIN_PATH" ]]; then
    echo "ERROR: MacPulse binary not found at $BIN_PATH"
    exit 1
fi

BUNDLE_ID="com.shoaib.macpulse"

echo ">>> [STRESS 4] Starting Kernel Power Assertion Lifecycle Verification..."

# 1. Preserve original settings
ORIG_CHARGING=$(defaults read "$BUNDLE_ID" keepAwakeWhileCharging 2>/dev/null || echo "1")
ORIG_ALWAYS=$(defaults read "$BUNDLE_ID" alwaysAwake 2>/dev/null || echo "0")
ORIG_DISPLAY=$(defaults read "$BUNDLE_ID" allowDisplaySleep 2>/dev/null || echo "1")
ORIG_THRESHOLD=$(defaults read "$BUNDLE_ID" batterySafetyThreshold 2>/dev/null || echo "20")

restore_settings() {
    defaults write "$BUNDLE_ID" keepAwakeWhileCharging -bool "$ORIG_CHARGING" 2>/dev/null || true
    defaults write "$BUNDLE_ID" alwaysAwake -bool "$ORIG_ALWAYS" 2>/dev/null || true
    defaults write "$BUNDLE_ID" allowDisplaySleep -bool "$ORIG_DISPLAY" 2>/dev/null || true
    defaults write "$BUNDLE_ID" batterySafetyThreshold -int "$ORIG_THRESHOLD" 2>/dev/null || true
}
trap restore_settings EXIT

defaults write "$BUNDLE_ID" keepAwakeWhileCharging -bool YES
defaults write "$BUNDLE_ID" alwaysAwake -bool YES
defaults write "$BUNDLE_ID" allowDisplaySleep -bool YES
defaults write "$BUNDLE_ID" batterySafetyThreshold -int 20
sleep 0.5

# Launch MacPulse headless/background
"$BIN_PATH" &
APP_PID=$!
sleep 1.0

if ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "FAIL: MacPulse crashed on launch!"
    exit 1
fi

# Verify PreventUserIdleSystemSleep is active for PID in pmset
PMSET_OUT=$(pmset -g assertions)
echo "  [Step 4.1] Inspecting pmset assertions for PID $APP_PID..."

if echo "$PMSET_OUT" | grep -q "pid $APP_PID(MacPulse): \[.*PreventUserIdleSystemSleep"; then
    echo "  [Step 4.1 PASS] Kernel registered PreventUserIdleSystemSleep for PID $APP_PID."
else
    # Check alternate format in pmset -g assertions
    if echo "$PMSET_OUT" | grep -A 5 "PreventUserIdleSystemSleep" | grep -q "$APP_PID"; then
        echo "  [Step 4.1 PASS] Kernel registered PreventUserIdleSystemSleep for PID $APP_PID (alternate format)."
    else
        echo "FAIL: PreventUserIdleSystemSleep NOT found in pmset for PID $APP_PID!"
        echo "$PMSET_OUT" | grep -i "MacPulse" || echo "No MacPulse assertion found."
        kill -9 "$APP_PID" 2>/dev/null || true
        exit 1
    fi
fi

# Verify Display Sleep is NOT prevented
if echo "$PMSET_OUT" | grep -A 5 "PreventUserIdleDisplaySleep" | grep -q "$APP_PID"; then
    echo "FAIL: PreventUserIdleDisplaySleep should NOT be active when allowDisplaySleep=YES!"
    kill -9 "$APP_PID" 2>/dev/null || true
    exit 1
fi
echo "  [Step 4.2 PASS] Display sleep is allowed when allowDisplaySleep=YES."

# 2. Test graceful termination cleanup (SIGTERM)
echo "  [Step 4.3] Sending SIGTERM to PID $APP_PID and verifying kernel cleanup..."
kill -TERM "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true
sleep 0.5

PMSET_POST=$(pmset -g assertions)
if echo "$PMSET_POST" | grep -q "pid $APP_PID"; then
    echo "FAIL: Lingering assertion detected in kernel for PID $APP_PID after SIGTERM!"
    exit 1
fi
echo "  [Step 4.3 PASS] Zero lingering kernel assertions after graceful SIGTERM termination."

# 3. Test Display Sleep assertion in kernel
echo "  [Step 4.4] Testing Dual Assertion (System + Display) in kernel..."
defaults write "$BUNDLE_ID" alwaysAwake -bool YES
defaults write "$BUNDLE_ID" allowDisplaySleep -bool NO

"$BIN_PATH" &
APP_PID2=$!
sleep 0.8

if ! kill -0 "$APP_PID2" 2>/dev/null; then
    echo "FAIL: MacPulse crashed on launch!"
    exit 1
fi

PMSET_OUT2=$(pmset -g assertions)
HAS_SYS=false
HAS_DISP=false

if echo "$PMSET_OUT2" | grep -q "pid $APP_PID2(MacPulse): \[.*PreventUserIdleSystemSleep" || echo "$PMSET_OUT2" | grep -A 5 "PreventUserIdleSystemSleep" | grep -q "$APP_PID2"; then
    HAS_SYS=true
fi

if echo "$PMSET_OUT2" | grep -q "pid $APP_PID2(MacPulse): \[.*PreventUserIdleDisplaySleep" || echo "$PMSET_OUT2" | grep -A 5 "PreventUserIdleDisplaySleep" | grep -q "$APP_PID2"; then
    HAS_DISP=true
fi

if [[ "$HAS_SYS" == "true" && "$HAS_DISP" == "true" ]]; then
    echo "  [Step 4.4 PASS] Both PreventUserIdleSystemSleep and PreventUserIdleDisplaySleep registered in kernel."
else
    echo "FAIL: Expected dual assertions in kernel! HAS_SYS=$HAS_SYS HAS_DISP=$HAS_DISP"
    kill -9 "$APP_PID2" 2>/dev/null || true
    exit 1
fi

# 4. Test abnormal termination (SIGKILL) kernel Mach port cleanup
echo "  [Step 4.5] Sending SIGKILL (kill -9) to verify kernel Mach port teardown..."
kill -9 "$APP_PID2" 2>/dev/null || true
wait "$APP_PID2" 2>/dev/null || true
sleep 0.5

PMSET_POST2=$(pmset -g assertions)
if echo "$PMSET_POST2" | grep -q "pid $APP_PID2"; then
    echo "FAIL: Lingering assertion detected in kernel for PID $APP_PID2 after SIGKILL!"
    exit 1
fi
echo "  [Step 4.5 PASS] Kernel automatically purged all assertions on SIGKILL (no leaks)."

# Reset defaults
defaults write "$BUNDLE_ID" allowDisplaySleep -bool YES
defaults write "$BUNDLE_ID" alwaysAwake -bool NO

echo ">>> [STRESS 4 COMPLETE] Kernel power assertion lifecycle verification PASSED."
exit 0
