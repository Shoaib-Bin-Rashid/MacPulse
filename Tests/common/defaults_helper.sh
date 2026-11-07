#!/bin/bash
# defaults_helper.sh — NSUserDefaults management and test isolation for MacPulse E2E tests
# Author: test_writer_e2e_1
# Constraints: Plain English output only. Zero Bangla/Bengali characters.

PREFS_DOMAIN="com.shoaib.macpulse.tests"
export MACPULSE_DEFAULTS_SUITE="com.shoaib.macpulse.tests"
PREFS_BACKUP_FILE="${TEST_TEMP_DIR}/macpulse_test_prefs_backup.plist"

backup_preferences() {
    # Isolate test suite before running
    defaults delete "$PREFS_DOMAIN" > /dev/null 2>&1 || true
}

restore_preferences() {
    # Clean up ephemeral test suite
    defaults delete "$PREFS_DOMAIN" > /dev/null 2>&1 || true
}

get_preference() {
    local key="$1"
    defaults read "$PREFS_DOMAIN" "$key" 2>/dev/null || echo "NOT_SET"
}

set_bool_preference() {
    local key="$1"
    local value="$2" # YES / NO or true / false
    defaults write "$PREFS_DOMAIN" "$key" -bool "$value"
}

set_int_preference() {
    local key="$1"
    local value="$2"
    defaults write "$PREFS_DOMAIN" "$key" -int "$value"
}

delete_preference() {
    local key="$1"
    defaults delete "$PREFS_DOMAIN" "$key" 2>/dev/null || true
}

reset_all_preferences() {
    defaults delete "$PREFS_DOMAIN" 2>/dev/null || true
}
