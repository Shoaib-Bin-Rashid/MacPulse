#!/bin/bash
# pmset_helper.sh — Power assertion and hardware power state inspection for MacPulse E2E tests
# Author: test_writer_e2e_1
# Constraints: Plain English output only. Zero Bangla/Bengali characters.

get_process_assertions() {
    local pid="$1"
    pmset -g assertions 2>/dev/null | grep -E "pid ${pid}\(" || true
}

has_system_sleep_assertion() {
    local pid="$1"
    local max_retries="${2:-10}"
    local count=0
    while true; do
        local assertions
        assertions="$(get_process_assertions "$pid")"
        if echo "$assertions" | grep -q "PreventUserIdleSystemSleep"; then
            return 0
        fi
        if (( count >= max_retries )); then
            break
        fi
        sleep 0.1
        count=$((count + 1))
    done
    return 1
}

has_display_sleep_assertion() {
    local pid="$1"
    local max_retries="${2:-10}"
    local count=0
    while true; do
        local assertions
        assertions="$(get_process_assertions "$pid")"
        if echo "$assertions" | grep -q "PreventUserIdleDisplaySleep"; then
            return 0
        fi
        if (( count >= max_retries )); then
            break
        fi
        sleep 0.1
        count=$((count + 1))
    done
    return 1
}

count_assertions_for_pid() {
    local pid="$1"
    local assertions
    assertions="$(get_process_assertions "$pid")"
    if [[ -z "$assertions" ]]; then
        echo "0"
    else
        echo "$assertions" | grep -c "pid ${pid}" || echo "0"
    fi
}

get_system_power_source() {
    local ps_output
    ps_output="$(pmset -g ps 2>/dev/null)"
    if echo "$ps_output" | grep -qi "AC Power"; then
        echo "AC"
    elif echo "$ps_output" | grep -qi "Battery Power"; then
        echo "Battery"
    else
        echo "Unknown"
    fi
}

get_system_battery_percent() {
    local ps_output
    ps_output="$(pmset -g ps 2>/dev/null)"
    local pct
    pct="$(echo "$ps_output" | grep -Eo '[0-9]+%' | tr -d '%' | head -n 1)"
    if [[ -n "$pct" ]]; then
        echo "$pct"
    else
        echo "-1"
    fi
}

is_system_charging() {
    local ps_output
    ps_output="$(pmset -g ps 2>/dev/null)"
    if echo "$ps_output" | grep -qi "charging"; then
        return 0
    fi
    return 1
}

is_desktop_mac() {
    local ps_output
    ps_output="$(pmset -g ps 2>/dev/null)"
    if ! echo "$ps_output" | grep -qi "InternalBattery"; then
        return 0
    fi
    return 1
}
