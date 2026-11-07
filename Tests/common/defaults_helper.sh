#!/bin/bash
# defaults_helper.sh — NSUserDefaults management and test isolation for MacPulse E2E tests
# Author: test_writer_e2e_1
# Constraints: Plain English output only. Zero Bangla/Bengali characters.

PREFS_DOMAIN="com.shoaib.macpulse"
PREFS_BACKUP_FILE="${TEST_TEMP_DIR}/macpulse_prefs_backup.plist"

backup_preferences() {
    if defaults read "$PREFS_DOMAIN" > /dev/null 2>&1; then
        defaults export "$PREFS_DOMAIN" "$PREFS_BACKUP_FILE" > /dev/null 2>&1 || true
    fi
}

restore_preferences() {
    if [[ -f "$PREFS_BACKUP_FILE" ]]; then
        defaults import "$PREFS_DOMAIN" "$PREFS_BACKUP_FILE" > /dev/null 2>&1 || true
    else
        defaults delete "$PREFS_DOMAIN" > /dev/null 2>&1 || true
    fi
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
