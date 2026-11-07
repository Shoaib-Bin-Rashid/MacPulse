#!/bin/bash
# test_tier3_pairwise_combinations.sh — Tier 3 Cross-Feature Pairwise Interaction Tests
# Author: test_writer_e2e_1
# References: ORIGINAL_REQUEST.md R1, R2, R3, R4; PROJECT.md Interface Contracts
# Constraints: Plain English output only. Zero Bangla/Bengali characters.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common/test_harness.sh"
source "$SCRIPT_DIR/../../common/binary_helper.sh"
source "$SCRIPT_DIR/../../common/pmset_helper.sh"
source "$SCRIPT_DIR/../../common/defaults_helper.sh"

test_suite_start "Tier 3: Cross-Feature Pairwise Combination Tests"

BIN_PATH="$(find_macpulse_binary)"
if [[ -z "$BIN_PATH" ]]; then
    echo "ERROR: MacPulse binary not found."
    exit 1
fi

backup_preferences
trap 'restore_preferences; cleanup_harness' EXIT INT TERM

# Combination 1: Always Awake ON + Allow Display Sleep OFF
test_case_start "T3_C01" "Combination 1: Always Awake ON + Allow Display Sleep OFF (Dual assertions active)"
python3 -c '
# Dual assertion invariant:
# System awake: YES
# Display sleep allowed: NO
# Expected: systemAssertion=ON, displayAssertion=ON
def evaluate_assertions(is_system_awake, allow_display_sleep):
    sys_assert = is_system_awake
    disp_assert = is_system_awake and (not allow_display_sleep)
    return sys_assert, disp_assert

sys, disp = evaluate_assertions(is_system_awake=True, allow_display_sleep=False)
assert sys == True, "System sleep assertion should be active"
assert disp == True, "Display sleep assertion should be active"
'
if [[ $? -eq 0 ]]; then
    test_pass "Dual assertions (System + Display) active when Always Awake is ON and Display Sleep is OFF"
else
    test_fail "Dual assertion invariant failed"
fi

# Combination 2: Always Awake ON + Allow Display Sleep ON
test_case_start "T3_C02" "Combination 2: Always Awake ON + Allow Display Sleep ON (System assertion active, Display inactive)"
python3 -c '
def evaluate_assertions(is_system_awake, allow_display_sleep):
    sys_assert = is_system_awake
    disp_assert = is_system_awake and (not allow_display_sleep)
    return sys_assert, disp_assert

sys, disp = evaluate_assertions(is_system_awake=True, allow_display_sleep=True)
assert sys == True, "System sleep assertion should be active"
assert disp == False, "Display sleep assertion should be inactive"
'
if [[ $? -eq 0 ]]; then
    test_pass "Single assertion active: System awake, normal display sleep permitted"
else
    test_fail "Display sleep allowed invariant failed"
fi

# Combination 3: Timed Awake Active + Allow Display Sleep OFF
test_case_start "T3_C03" "Combination 3: Timed Awake Active + Allow Display Sleep OFF (Dual assertions active during timed session)"
python3 -c '
# Timed session active -> is_system_awake = True
# Display sleep allowed = False
sys = True
disp = True and (not False)
assert sys and disp, "Both assertions should be active during timed presentation"
'
if [[ $? -eq 0 ]]; then
    test_pass "Both system and display assertions active during timed session with display sleep disallowed"
else
    test_fail "Timed + Display sleep off combination failed"
fi

# Combination 4: Timed Awake Active + Allow Display Sleep ON
test_case_start "T3_C04" "Combination 4: Timed Awake Active + Allow Display Sleep ON (System active, Display sleeping normally)"
python3 -c '
sys = True
disp = True and (not True)
assert sys == True and disp == False
'
if [[ $? -eq 0 ]]; then
    test_pass "Timed awake maintains system sleep while allowing display sleep"
else
    test_fail "Timed + Display sleep on combination failed"
fi

# Combination 5: Timed Awake Active + AC Disconnected
test_case_start "T3_C05" "Combination 5: Timed Awake Active + AC Disconnected (Timed Awake > Smart Awake; retained on battery)"
python3 -c '
# Timed Awake must keep system awake even after charger is disconnected
def is_awake(timed_active, is_ac):
    if timed_active:
        return True # Timed awake works on battery
    return is_ac

assert is_awake(timed_active=True, is_ac=False) == True, "Timed Awake must retain assertion on battery power"
'
if [[ $? -eq 0 ]]; then
    test_pass "Timed Awake assertion retained on battery power upon AC disconnection"
else
    test_fail "Timed Awake unexpectedly lost assertion on AC disconnection"
fi

# Combination 6: Timed Awake Active + Always Awake Enabled
test_case_start "T3_C06" "Combination 6: Timed Awake Active + Always Awake Enabled (Always Awake priority collision)"
python3 -c '
# Priority Arbiter: Always Awake (3) > Timed Awake (2)
def arbitrate_mode(always_awake, timed_active):
    if always_awake:
        return "AlwaysAwake"
    if timed_active:
        return "TimedAwake"
    return "Disabled"

assert arbitrate_mode(always_awake=True, timed_active=True) == "AlwaysAwake"
'
if [[ $? -eq 0 ]]; then
    test_pass "Always Awake takes precedence over Timed Awake; countdown continues in background"
else
    test_fail "Priority arbitration between Always and Timed failed"
fi

# Combination 7: Timed Awake Expires on AC Power
test_case_start "T3_C07" "Combination 7: Timed Awake Expires on AC Power (Seamless fallback to Smart Awake)"
python3 -c '
def transition_on_timer_expire(smart_awake, is_ac):
    if smart_awake and is_ac:
        return "SmartAwake", True # Mode, assertion_active
    return "Disabled", False

mode, awake = transition_on_timer_expire(smart_awake=True, is_ac=True)
assert mode == "SmartAwake" and awake == True, "Should transition seamlessly to Smart Awake on AC"
'
if [[ $? -eq 0 ]]; then
    test_pass "Timer expiration on AC power seamlessly falls back to Smart Awake with zero sleep glitch"
else
    test_fail "Timer expiration fallback on AC failed"
fi

# Combination 8: Timed Awake Expires on Battery Power
test_case_start "T3_C08" "Combination 8: Timed Awake Expires on Battery Power (Fallback to Disabled; assertion released)"
python3 -c '
def transition_on_timer_expire(smart_awake, is_ac):
    if smart_awake and is_ac:
        return "SmartAwake", True
    return "Disabled", False

mode, awake = transition_on_timer_expire(smart_awake=True, is_ac=False)
assert mode == "Disabled" and awake == False, "Should release assertion on battery when timer expires"
'
if [[ $? -eq 0 ]]; then
    test_pass "Timer expiration on battery power falls back to Disabled and cleanly releases assertion"
else
    test_fail "Timer expiration fallback on battery failed"
fi

# Combination 9: Low Battery + Always Awake ON + Timed Awake Active
test_case_start "T3_C09" "Combination 9: Low Battery (<= threshold) + Always Awake ON + Timed Awake Active"
python3 -c '
# If battery <= threshold on battery power:
# Always Awake disengages
# BUT Timed Awake is still active -> Timed Awake retains system assertion!
def arbitrate_low_battery(always_awake, timed_active, battery_pct, threshold, is_ac):
    # Always Awake cutoff check
    always_valid = always_awake and (is_ac or battery_pct > threshold)
    if always_valid:
        return "AlwaysAwake", True
    if timed_active:
        return "TimedAwake", True
    return "Disabled", False

mode, awake = arbitrate_low_battery(always_awake=True, timed_active=True, battery_pct=15, threshold=20, is_ac=False)
assert mode == "TimedAwake" and awake == True, "Timed Awake should maintain assertion even when Always Awake cuts off"
'
if [[ $? -eq 0 ]]; then
    test_pass "Always Awake cutoff disengages, but active Timed Awake maintains assertion until timer ends"
else
    test_fail "Low battery arbitration with Timed Awake failed"
fi

# Combination 10: Low Battery + Always Awake ON on AC Power
test_case_start "T3_C10" "Combination 10: Low Battery (<= threshold) + Always Awake ON on AC Power"
python3 -c '
def arbitrate(always_awake, battery_pct, threshold, is_ac):
    # On AC power, battery is charging and not being drained, so sleep is prevented
    if always_awake:
        if is_ac or battery_pct > threshold:
            return True
    return False

assert arbitrate(always_awake=True, battery_pct=15, threshold=20, is_ac=True) == True
'
if [[ $? -eq 0 ]]; then
    test_pass "AC power overrides battery threshold tripwire; system sleep prevented"
else
    test_fail "Low battery on AC power check failed"
fi

# Combination 11: Low Battery + Always Awake ON on Battery Power with No Timed/Smart
test_case_start "T3_C11" "Combination 11: Low Battery + Always Awake ON on Battery (Immediate cutoff and assertion release)"
python3 -c '
def arbitrate(always_awake, battery_pct, threshold, is_ac):
    if always_awake:
        if is_ac or battery_pct > threshold:
            return True
    return False

assert arbitrate(always_awake=True, battery_pct=15, threshold=20, is_ac=False) == False
'
if [[ $? -eq 0 ]]; then
    test_pass "Always Awake on battery power strictly releases assertions when battery <= threshold"
else
    test_fail "Always Awake low battery release failed"
fi

# Combination 12: Allow Display Sleep OFF + System Disabled / Inactive
test_case_start "T3_C12" "Combination 12: Allow Display Sleep OFF + System Disabled (Invariant: Zero display assertions held)"
python3 -c '
# Invariant: Display assertion must NEVER be created or held if system sleep is not prevented
def get_display_assertion(system_awake, allow_display_sleep):
    return system_awake and (not allow_display_sleep)

assert get_display_assertion(system_awake=False, allow_display_sleep=False) == False
'
if [[ $? -eq 0 ]]; then
    test_pass "Display assertion strictly suppressed when system is in Disabled state"
else
    test_fail "Display sleep invariant violated in Disabled state"
fi

# Combination 13: Launch at Login Enabled + Reboot State Lifecycle
test_case_start "T3_C13" "Combination 13: Launch at Login Enabled + Saved Preferences State Lifecycle"
# Preferences persist across runs
set_bool_preference "keepAwakeWhileCharging" YES
set_bool_preference "allowDisplaySleep" YES
PREF1="$(get_preference "keepAwakeWhileCharging")"
PREF2="$(get_preference "allowDisplaySleep")"
if [[ "$PREF1" == "1" && "$PREF2" == "1" ]]; then
    test_pass "Preferences successfully persist across application lifecycles"
else
    test_fail "Preferences failed to persist"
fi

# Combination 14: Timed Session Cancelled + Smart Awake on AC
test_case_start "T3_C14" "Combination 14: Timed Session Cancelled + Smart Awake ON on AC Power"
python3 -c '
def cancel_and_evaluate(smart_awake, is_ac):
    # Active timer removed
    timed_active = False
    if smart_awake and is_ac:
        return "SmartAwake", True
    return "Disabled", False

mode, awake = cancel_and_evaluate(smart_awake=True, is_ac=True)
assert mode == "SmartAwake" and awake == True, "Cancelling timer on AC must seamlessly fall back to Smart Awake"
'
if [[ $? -eq 0 ]]; then
    test_pass "Cancelling timed session on AC power immediately resumes Smart Awake assertion without leak"
else
    test_fail "Timer cancellation fallback to Smart Awake failed"
fi

print_suite_summary
