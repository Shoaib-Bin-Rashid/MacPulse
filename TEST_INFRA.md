# MacPulse E2E Test Infrastructure & Test Architecture

## 1. Overview
This document specifies the end-to-end (E2E) automated verification infrastructure for MacPulse. MacPulse is a native macOS automatic keep-awake utility with optional advanced controls. The test suite exercises the compiled application binary and its interactions with the macOS kernel power management daemon (`powerd`), system power sources (`IOPowerSources`), ServiceManagement (`SMAppService`), user preferences (`NSUserDefaults`), and distribution packaging.

The test suite follows an opaque-box, requirement-driven methodology across 4 distinct tiers:
- **Tier 1 — Feature Coverage**: Basic happy path verifying each feature in isolation via CLI, process execution, environment simulation, and kernel assertion inspection.
- **Tier 2 — Boundary & Corner Cases**: Boundary conditions (0%, 10%, 20%, 50%, 100% battery; rapid plug/unplug; invalid args; desktop Mac without battery; double quit; rapid toggle).
- **Tier 3 — Cross-Feature Combinations**: Pairwise interactions (Always Awake + Display Sleep; Timed Awake + AC unplug; Always Awake + Timed Awake priority collision; Low Battery + Timed Awake).
- **Tier 4 — Real-World Application Scenarios**: End-to-end realistic user workflows (presentations, overnight downloads, mobile café working session with auto-cutoff protection, fresh install lifecycle).

---

## 2. Test Suite Architecture & Directory Layout

The test suite resides in `/Users/shoaib/Workspace/Projects/MacPulse/tests/` and is organized into modular components:

```text
/Users/shoaib/Workspace/Projects/MacPulse/tests/
├── run_e2e_tests.sh                                # Master executable test runner
├── common/
│   ├── test_harness.sh                             # Assertions, timeout runners, test reporting
│   ├── binary_helper.sh                            # Binary path resolution, lipo checks, launch/kill
│   ├── pmset_helper.sh                             # Kernel power assertion query (pmset -g assertions)
│   └── defaults_helper.sh                          # NSUserDefaults isolation, backup, and restore
└── tiers/
    ├── tier1_features/
    │   ├── test_f01_smart_awake.sh                 # Features 4, 6, 22, 23 (Smart Awake & Power Status)
    │   ├── test_f02_display_sleep.sh               # Feature 7 (Allow Display Sleep Assertion)
    │   ├── test_f03_always_awake.sh                # Features 12, 13, 14 (Always Awake & Cutoff)
    │   ├── test_f04_timed_awake.sh                 # Features 2, 8, 9, 10, 11 (Timed Awake & Countdown)
    │   ├── test_f05_priority_arbiter.sh            # Feature 15 (Priority Arbiter State Machine)
    │   ├── test_f06_ui_and_about.sh                # Features 1, 3, 5, 17 (Icons, Header, About)
    │   ├── test_f07_launch_at_login.sh             # Feature 16 (SMAppService.mainApp Lifecycle)
    │   ├── test_f08_clean_teardown.sh              # Feature 18 (SIGTERM & Zero Leaks Teardown)
    │   ├── test_f09_build_and_packaging.sh         # Features 19, 20 (Universal Fat Binary & DMG)
    │   └── test_f10_selftest_runner.sh             # Feature 21 (Headless --selftest Runner)
    ├── tier2_boundaries/
    │   ├── test_b01_battery_boundaries.sh          # Battery 0%, 10%, 20%, 21%, 50%, 100% boundaries
    │   ├── test_b02_rapid_transitions.sh           # AC bounce debouncing, rapid button toggles
    │   ├── test_b03_cli_arguments.sh               # Unknown flags, empty args, help requests
    │   ├── test_b04_lifecycle_boundaries.sh        # Double quit, dual instances, SIGKILL auto-reap
    │   └── test_b05_timed_boundaries.sh            # 0s duration, negative duration, monotonic clock
    ├── tier3_combinations/
    │   └── test_tier3_pairwise_combinations.sh     # 14 pairwise cross-feature combination tests
    └── tier4_scenarios/
        └── test_tier4_real_world_scenarios.sh      # 6 real-world user workflow scenarios
```

---

## 3. How to Run the Tests

### 3.1 Run the Full 4-Tier Test Suite
```bash
cd /Users/shoaib/Workspace/Projects/MacPulse
./tests/run_e2e_tests.sh
```

### 3.2 Run a Specific Tier
```bash
# Run Tier 1 only (Feature Coverage)
./tests/run_e2e_tests.sh --tier 1

# Run Tier 2 only (Boundary & Corner Cases)
./tests/run_e2e_tests.sh --tier 2

# Run Tier 3 only (Cross-Feature Combinations)
./tests/run_e2e_tests.sh --tier 3

# Run Tier 4 only (Real-World Application Scenarios)
./tests/run_e2e_tests.sh --tier 4
```

### 3.3 Run with Filtering
```bash
# Filter test suites matching pattern
./tests/run_e2e_tests.sh --filter "display_sleep"
./tests/run_e2e_tests.sh --filter "battery"
```

### 3.4 Verbose Mode
```bash
./tests/run_e2e_tests.sh --verbose
```

### 3.5 List All Available Suites
```bash
./tests/run_e2e_tests.sh --list
```

---

## 4. Test Verification Methodology

### 4.1 Kernel Assertion Inspection (`pmset`)
MacPulse controls system sleep by interacting directly with the macOS kernel power management daemon (`powerd`). The test harness uses `pmset_helper.sh` to inspect actual assertions registered under the process PID:
- `pmset -g assertions | grep "pid <PID>"`
- Verifies that `PreventUserIdleSystemSleep` is active when sleep should be prevented.
- Verifies that `PreventUserIdleDisplaySleep` is active if and only if system sleep is prevented AND display sleep is disabled.
- Verifies that terminating the process releases all assertions immediately with zero lingering entries.

### 4.2 Universal Binary Architecture (`lipo`)
The build pipeline requirement mandates a Universal Fat Mach-O binary containing both `arm64` and `x86_64` slices. The harness verifies this via `lipo -info <binary>` to guarantee full native support on Apple Silicon and Intel Macs.

### 4.3 Headless Execution & Timeout Enforcement
To guarantee tests never hang when testing a GUI application:
- `run_with_timeout` wraps commands with python3 subprocess timeout (5 seconds default).
- If the binary fails to implement headless mode or blocks in `[NSApp run]`, the timeout kills the child process, returns exit code 124, and reports a clear test failure rather than stalling the runner.

### 4.4 Process Isolation & Non-Destructive Preferences
- The harness backs up existing preferences for `com.shoaib.macpulse` before test execution and restores them on exit via bash `trap`.
- Process tracking records all spawned child PIDs and guarantees clean SIGTERM/SIGKILL teardown on test completion or interruption.

---

## 5. Test Suite Inventory & Traceability Matrix

| Tier | Suite | Cases | Requirements Covered | Description |
|---|---|---|---|---|
| **Tier 1** | `test_f01_smart_awake.sh` | 6 | R1, F4, F6, F22, F23 | Smart Awake default, AC detection, assertion creation, disable, desktop support |
| **Tier 1** | `test_f02_display_sleep.sh` | 5 | R1, F7, Issue C-01 | Allow Display Sleep toggle, display sleep assertion, independence from system sleep |
| **Tier 1** | `test_f03_always_awake.sh` | 5 | R3, F12, F13, F14 | Always Awake toggle, battery threshold submenu (10-50%), auto-cutoff logic |
| **Tier 1** | `test_f04_timed_awake.sh` | 6 | R2, F2, F8, F9, F10, F11 | 30m, 1h, 2h presets, live countdown title format, cancellation, expiration fallback |
| **Tier 1** | `test_f05_priority_arbiter.sh` | 5 | R4, F15 | Always > Timed > Smart > Disabled hierarchy, singleton assertion invariant |
| **Tier 1** | `test_f06_ui_and_about.sh` | 5 | R1, R5, F1, F3, F5, F17 | SF Symbols template resolution, branding header, status formatting, About dialog |
| **Tier 1** | `test_f07_launch_at_login.sh` | 5 | R1, R5, F16 | SMAppService.mainApp availability, Info.plist BundleID, LSUIElement=1, error handling |
| **Tier 1** | `test_f08_clean_teardown.sh` | 5 | R4, F18 | SIGTERM assertion teardown, process exit, zero kernel leaks, re-launch clean slate |
| **Tier 1** | `test_f09_build_and_packaging.sh` | 5 | R5, F19, F20 | Universal binary compilation (arm64 + x86_64), build.sh, package.sh, DMG structure |
| **Tier 1** | `test_f10_selftest_runner.sh` | 5 | R5, F21 | Headless --selftest runner, tools/selftest.sh execution, structured PASS markers |
| **Tier 2** | `test_b01_battery_boundaries.sh` | 6 | R3, F13, F14 | 0%, 10% min, 20% default boundary equality, 21% boundary +1, 50% max, 100% capacity |
| **Tier 2** | `test_b02_rapid_transitions.sh` | 5 | R4, Edge Cases #5, #12 | AC bounce debouncing (150ms), rapid Smart Awake, Always Awake, Display Sleep toggles |
| **Tier 2** | `test_b03_cli_arguments.sh` | 5 | R5, Edge Case #13 | Unknown CLI flags, empty string args, selftest extra args, --help, malformed env |
| **Tier 2** | `test_b04_lifecycle_boundaries.sh` | 5 | R4, R5, Edge Case #11 | Double termination idempotency, dual instance launch, SIGKILL kernel auto-reap |
| **Tier 2** | `test_b05_timed_boundaries.sh` | 5 | R2, Edge Cases #1, #4 | 0s duration boundary, negative duration rejection, inactive cancellation, monotonic clock |
| **Tier 3** | `test_tier3_pairwise_combinations.sh` | 14 | R1, R2, R3, R4 | Pairwise mode interactions (Always+Display, Timed+Display, Timed+AC, Low Battery) |
| **Tier 4** | `test_tier4_real_world_scenarios.sh` | 6 | R1, R2, R3, R4, R5 | Keynote Presentation, Overnight Download, Café Battery Shield, Emergency Recovery, Re-login |

**Total Test Suites**: 17  
**Total Automated Test Cases**: 98  
