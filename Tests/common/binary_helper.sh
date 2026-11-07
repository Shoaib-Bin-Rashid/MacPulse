#!/bin/bash
# binary_helper.sh — Binary resolution and lifecycle management for MacPulse E2E tests
# Author: test_writer_e2e_1
# Constraints: Plain English output only. Zero Bangla/Bengali characters.

find_macpulse_binary() {
    if [[ -n "${MAC_PULSE_BIN:-}" && -x "$MAC_PULSE_BIN" ]]; then
        echo "$MAC_PULSE_BIN"
        return 0
    fi

    local project_root
    project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

    local candidates=(
        "$project_root/build/bin/MacPulse"
        "$project_root/bin/MacPulse"
        "$project_root/build/MacPulse.app/Contents/MacOS/MacPulse"
        "$project_root/MacPulse.app/Contents/MacOS/MacPulse"
        "/Applications/MacPulse.app/Contents/MacOS/MacPulse"
        "$HOME/Applications/MacPulse.app/Contents/MacOS/MacPulse"
    )

    for path in "${candidates[@]}"; do
        if [[ -x "$path" ]]; then
            echo "$path"
            return 0
        fi
    done

    echo ""
    return 1
}

find_macpulse_bundle() {
    if [[ -n "${MAC_PULSE_APP:-}" && -d "$MAC_PULSE_APP" ]]; then
        echo "$MAC_PULSE_APP"
        return 0
    fi

    local project_root
    project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

    local candidates=(
        "$project_root/build/MacPulse.app"
        "$project_root/MacPulse.app"
        "/Applications/MacPulse.app"
        "$HOME/Applications/MacPulse.app"
    )

    for path in "${candidates[@]}"; do
        if [[ -d "$path" ]]; then
            echo "$path"
            return 0
        fi
    done

    echo ""
    return 1
}

get_binary_architectures() {
    local bin_path="$1"
    if [[ ! -f "$bin_path" ]]; then
        echo "NOT_FOUND"
        return 1
    fi
    lipo -info "$bin_path" 2>/dev/null | sed -E 's/.*are: (.*)/\1/' | sed -E 's/.*architecture: (.*)/\1/'
}

is_universal_binary() {
    local bin_path="$1"
    local arches
    arches="$(get_binary_architectures "$bin_path")"
    if echo "$arches" | grep -qw "arm64" && echo "$arches" | grep -qw "x86_64"; then
        return 0
    fi
    return 1
}

launch_test_instance() {
    local bin_path="$1"
    shift
    local log_file="${TEST_TEMP_DIR}/app_${RANDOM}.log"

    "$bin_path" "$@" > "$log_file" 2>&1 &
    local pid=$!
    track_pid "$pid"

    # Give process 200ms to initialize
    sleep 0.2

    if kill -0 "$pid" 2>/dev/null; then
        echo "$pid"
        return 0
    else
        untrack_pid "$pid"
        echo ""
        return 1
    fi
}

terminate_instance() {
    local pid="$1"
    local timeout_sec="${2:-3}"

    if ! kill -0 "$pid" 2>/dev/null; then
        untrack_pid "$pid"
        return 0
    fi

    kill -TERM "$pid" 2>/dev/null || true

    local elapsed=0
    while kill -0 "$pid" 2>/dev/null && (( elapsed < timeout_sec * 10 )); do
        sleep 0.1
        elapsed=$((elapsed + 1))
    done

    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
    fi

    untrack_pid "$pid"
}

is_process_alive() {
    local pid="$1"
    kill -0 "$pid" 2>/dev/null
}
