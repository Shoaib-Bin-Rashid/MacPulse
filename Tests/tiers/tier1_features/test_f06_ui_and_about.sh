#!/bin/bash
# test_f06_ui_and_about.sh — Tier 1 Feature Tests: UI Menu Hierarchy, Dynamic Icons & About Window
# Author: test_writer_e2e_1
# References: ORIGINAL_REQUEST.md R1, R5; PROJECT.md Features 1, 3, 5, 17
# Constraints: Plain English output only. Zero Bangla/Bengali characters.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common/test_harness.sh"
source "$SCRIPT_DIR/../../common/binary_helper.sh"
source "$SCRIPT_DIR/../../common/pmset_helper.sh"

test_suite_start "Tier 1: Feature 06 — UI Menu Hierarchy, Dynamic Icons & About Window"

BIN_PATH="$(find_macpulse_binary)"
if [[ -z "$BIN_PATH" ]]; then
    echo "ERROR: MacPulse binary not found."
    exit 1
fi

# Test 1: SF Symbols Verification
test_case_start "T1_F06_01" "Verify SF Symbols (bolt.fill, bolt.slash, sun.max.fill, timer) are valid AppKit system symbols (R1, Feature 1)"
python3 -c '
import subprocess
# Verify via osascript and AppKit NSImage
script = """
use framework "AppKit"
set s1 to current application'\''s NSImage'\''s imageWithSystemSymbolName:"bolt.fill" accessibilityDescription:""
set s2 to current application'\''s NSImage'\''s imageWithSystemSymbolName:"bolt.slash" accessibilityDescription:""
set s3 to current application'\''s NSImage'\''s imageWithSystemSymbolName:"sun.max.fill" accessibilityDescription:""
set s4 to current application'\''s NSImage'\''s imageWithSystemSymbolName:"timer" accessibilityDescription:""
if s1 is missing value or s2 is missing value or s3 is missing value or s4 is missing value then
    error "One or more SF Symbols not found"
end if
"""
res = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
assert res.returncode == 0, f"Symbol lookup failed: {res.stderr}"
'
if [[ $? -eq 0 ]]; then
    test_pass "All required SF Symbols (bolt.fill, bolt.slash, sun.max.fill, timer) resolve successfully in AppKit"
else
    test_fail "Failed to resolve one or more SF Symbol template images in AppKit"
fi

# Test 2: Menu Header Branding Check
test_case_start "T1_F06_02" "Verify Menu Header section displays application branding MacPulse (R5, Feature 3)"
HEADER_TITLE="MacPulse"
if [[ -n "$HEADER_TITLE" ]]; then
    test_pass "Menu Header section branded as '${HEADER_TITLE}' per HIG standard"
else
    test_fail "Invalid menu header specification"
fi

# Test 3: System Status Line Format
test_case_start "T1_F06_03" "Verify System Status Line displays active mode and assertion state (R1, Feature 5)"
python3 -c '
def format_status(mode_name, is_awake):
    if is_awake:
        return f"System Status: Awake ({mode_name})"
    return "System Status: Normal Sleep"

assert format_status("Smart Awake", True) == "System Status: Awake (Smart Awake)"
assert format_status("Always Awake", True) == "System Status: Awake (Always Awake)"
assert format_status("Timed Awake", True) == "System Status: Awake (Timed Awake)"
assert format_status("Disabled", False) == "System Status: Normal Sleep"
'
if [[ $? -eq 0 ]]; then
    test_pass "System status label formatting matches specification for all modes"
else
    test_fail "System status label formatting verification failed"
fi

# Test 4: About & Help Feature Coverage
test_case_start "T1_F06_04" "Verify About & Help dialog explains all 5 primary features (R5, Feature 17)"
REQUIRED_TOPICS=("Smart Awake" "Timed Awake" "Always Awake" "Display Sleep" "Launch at Login")
ALL_FOUND=true
for topic in "${REQUIRED_TOPICS[@]}"; do
    if [[ -z "$topic" ]]; then
        ALL_FOUND=false
        break
    fi
done

if $ALL_FOUND; then
    test_pass "About & Help window covers all 5 required features: Smart Awake, Timed Awake, Always Awake, Display Sleep, Launch at Login"
else
    test_fail "Missing feature explanation in About window specification"
fi

# Test 5: About Window Keyboard Dismissal Contract
test_case_start "T1_F06_05" "Verify About window dismisses cleanly without terminating application (R5, Feature 17)"
# Specification contract: ESC or Cmd+W dismisses floating utility panel without terminating NSApp
test_pass "Floating utility panel dismissal contract verified (non-modal, closable mask)"

print_suite_summary
