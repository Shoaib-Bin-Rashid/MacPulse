# 06 — QA and Test Engineering Report

- **Sector Score:** **1.5 / 5**
- **Confidence:** High
- **Evidence Coverage:** Static Inspection of all 22 test scripts/programs + Independent Local Execution of `--selftest`, `Tests/run_e2e_tests.sh`, `test_power_manager_stress`, `test_arbiter_exhaustive_matrix`, `test_debounce_stress`, and `swift test`
- **Unresolved Findings:** 4 (`QA-001` [P0], `QA-002` [P1], `QA-003` [P1], `ARCH-001` [P1])
- **NOT VERIFIED Requirements:** 6 (Physical AC plug/unplug, physical battery discharge cutoff, physical desktop Mac without battery, macOS sleep/wake & lid close, Login Item startup across macOS reboot, Intel x86_64 hardware execution)

---

## 1. Executive Summary of QA Audit

Earlier reports (`TEST_READY.md`, `AI_TESTING_GUIDE.md`) claimed **"10/10 self-tests passed, 98/98 E2E tests passed, and 4/4 adversarial stress suites passed."**
Independent source-level and runtime audit of the test suite revealed four severe QA failures:

1. **P0 (`QA-001`):** Running `./build/bin/MacPulse --selftest` (or `./tools/selftest.sh`) **directly mutates the user's live production `NSUserDefaults` (`com.shoaib.macpulse`)** and leaves `keepAwakeWhileCharging = 0` (`NO`), silently disabling Smart Awake in production!
2. **P1 (`QA-002`):** **70 out of the 98 "E2E test cases" (71.4%) in `Tests/run_e2e_tests.sh` never execute the MacPulse binary at all.** Instead, 41 test cases run inline `python3 -c` functions that test toy Python mocks written inside the bash scripts, 12 only read/write `defaults` without launching MacPulse, 5 are unconditional `test_pass` no-ops, and 12 inspect static files or OS commands.
3. **P1 (`QA-002`):** In `main.m` lines 127–132, headless Self-Test #5 (`[PASS] MPPriorityArbiter battery safety cutoff logic`) contains **zero assertions or `if` checks**—it simply resets two variables and prints `[PASS]`.
4. **P1 (`QA-003`):** When we independently executed `./build/bin/test_power_manager_stress` (Tier 5 Stress Test 1), **it failed with exit code 1**:
   `INVARIANT VIOLATION: Display sleep prevented while system sleep allowed! FAIL: 1 invariant violations during multi-threaded stress!`
   Furthermore, Tier 5 Stress Test 2 (`test_arbiter_exhaustive_matrix.m`, lines 42–45) explicitly removed the `kMPAppSettingsDidChangeNotification` observer from `MPPriorityArbiter`, which masked the synchronous recursive re-entrancy bug (`POWER-001`) in production! And Tier 5 Stress Test 3 (`test_debounce_stress.m`, lines 69–71) detected a race condition (`VULNERABILITY DETECTED [CHALLENGE-01]`) and intentionally swallowed the failure so the script would exit `0`.

---

## 2. Quantitative Audit of the 98 E2E Test Cases (`Tests/run_e2e_tests.sh`)

Every single test case across all 17 suites was inspected line-by-line and classified by what it actually executes:

| Tier & Suite File | Total Cases | Launches `MacPulse` Binary? | Inline `python3 -c` Mock Only | `defaults` Read/Write Only (No App) | Static File / OS Tool Check | Unconditional `test_pass` No-Op | Audit Verdict |
|---|---:|---:|---:|---:|---:|---:|---|
| `tier1/test_f01_smart_awake.sh` | 6 | **4** (`01,03,04,05`) | 0 | 0 | 2 (`02,06` check `pmset -g ps`) | 0 | Real kernel `pmset` checks on AC; note `T1_F01_01` passes even if pref is `"NOT_SET"` |
| `tier1/test_f02_display_sleep.sh` | 5 | **5** (`01–05`) | 0 | 0 | 0 | 0 | Real binary + `pmset` checks, but tests out-of-scope feature (`SCOPE-001`) |
| `tier1/test_f03_always_awake.sh` | 5 | **3** (`01,02,05`) | 0 | 1 (`03`) | 0 | 1 (`04` skips with `test_pass` on AC) | Never tests battery cutoff when host is on AC power |
| `tier1/test_f04_timed_awake.sh` | 6 | **0** | 1 (`04`) | 4 (`01,02,03,05`) | 0 | 1 (`06`) | **100% Fake** — Never launches MacPulse or starts a timer |
| `tier1/test_f05_priority_arbiter.sh` | 5 | **2** (`04,05`) | 3 (`01,02,03`) | 0 | 0 | 0 | Precedence rules (`01–03`) only test a Python function `def arbitrate(...)` |
| `tier1/test_f06_ui_and_about.sh` | 5 | **0** | 1 (`03`) | 0 | 3 (`01` osascript, `02,04` bash vars) | 1 (`05`) | **100% Fake** — `T1_F06_02` checks `HEADER_TITLE="MacPulse"; [[ -n "$HEADER_TITLE" ]]`! |
| `tier1/test_f07_launch_at_login.sh` | 5 | **0** | 1 (`04` checks `len([0,1,2,3])==4`) | 0 | 3 (`01` osascript, `02,03` Info.plist) | 1 (`05`) | Static plist & OS framework checks; never invokes `MPLoginItemManager` |
| `tier1/test_f08_clean_teardown.sh` | 5 | **5** (`01–05`) | 0 | 0 | 0 | 0 | **Genuine E2E** — Spawns binary, sends `SIGTERM`, verifies `pmset` cleanup |
| `tier1/test_f09_build_and_packaging.sh` | 5 | **0** | 0 | 0 | 5 (`01–05` check `lipo`, `hdiutil`) | 0 | Genuine artifact checks (`lipo`, `hdiutil attach`) |
| `tier1/test_f10_selftest_runner.sh` | 5 | **3** (`02,03,04` `--selftest`) | 0 | 0 | 1 (`01`) | 1 (`05`) | Runs `--selftest` (which covers up `T1_F10_05` being a no-op) |
| `tier2/test_b01_battery_boundaries.sh` | 6 | **0** | 4 (`01,03,04,06`) | 2 (`02,05`) | 0 | 0 | **100% Fake** — Tests `python3 -c 'def should_cutoff(pct, thresh): return pct <= thresh'` |
| `tier2/test_b02_rapid_transitions.sh` | 5 | **1** (`03`) | 2 (`01,05`) | 2 (`02,04`) | 0 | 0 | Only `T2_B02_03` launches MacPulse (and `defaults write` isn't observed dynamically!) |
| `tier2/test_b03_cli_arguments.sh` | 5 | **5** (`01–05`) | 0 | 0 | 0 | 0 |Wait: `T2_B03_02` (`"$BIN_PATH" ""`) times out at 3s (exit code `124`), and passes because `124 != 139`! |
| `tier2/test_b04_lifecycle_boundaries.sh` | 5 | **3** (`02,03,04`) | 1 (`01`) | 0 | 1 (`05` Info.plist) | 0 | `T2_B04_03` genuinely tests kernel `SIGKILL` assertion reaping |
| `tier2/test_b05_timed_boundaries.sh` | 5 | **0** | 5 (`01–05`) | 0 | 0 | 0 | **100% Fake** — Pure Python mocks (`time.monotonic()` in Python, not Objective-C!) |
| `tier3/test_tier3_pairwise_combinations.sh` | 14 | **0** | 13 (`C01–C12, C14`) | 1 (`C13`) | 0 | 0 | **100% Fake** — Zero out of 14 pairwise tests execute MacPulse |
| `tier4/test_tier4_real_world_scenarios.sh` | 6 | **0** | 6 (`S01–S06`) | 0 | 0 | 0 | **100% Fake** — Zero out of 6 scenario tests execute MacPulse |
| **TOTAL (17 Suites)** | **98** | **28 (28.6%)** | **37 (37.8%)** | **10 (10.2%)** | **18 (18.4%)** | **5 (5.1%)** | **70 of 98 tests (71.4%) never execute `MacPulse`** |

---

## 3. Audit of In-App Self-Tests (`main.m` `runSelfTests`)

| Self-Test # | Printed Name in `main.m` | Lines | What It Actually Tests | Defects Found |
|---:|---|---|---|---|
| 1 | `MPAppSettings initialization and defaults` | 40–46 | Calls `[MPAppSettings sharedSettings]` and `[settings reloadSettings]` | **Does not assert default values** (`keepAwakeWhileCharging == YES`, `alwaysAwake == NO`). Binds to live user preferences (`QA-001`). |
| 2 | `MPPowerManager dual assertion lifecycle and idempotency` | 48–71 | Creates system assertion, re-applies idempotently, creates display assertion | Valid test of `MPPowerManager` (includes out-of-scope display sleep assertion). |
| 3 | `MPPowerManager double-release safety (no 0xe00002c2)` | 73–81 | Calls `[pm releaseAllAssertions]` twice and checks `!pm.isSystemSleepPrevented` | Valid test of double-release idempotency. |
| 4 | `MPPriorityArbiter hierarchy (Always Awake > Timed Awake > Smart Awake > Disabled)` | 83–125 | Evaluates `Disabled`, `SmartAwake` (if on AC), `TimedAwake`, and `AlwaysAwake` on real `MPPriorityArbiter` | Valid integration test, **but mutates live `NSUserDefaults`** (`QA-001`). |
| 5 | `MPPriorityArbiter battery safety cutoff logic` | 127–132 | Sets `arbiter.isTimedAwakeActive = NO; settings.alwaysAwake = NO; [arbiter evaluateEffectiveState];` | **FAKE TEST (`QA-002`)** — Zero assertions, zero mock battery injection, never tests battery cutoff! |
| 6 | `MPPowerSourceMonitor desktop Mac detection` | 134–147 | Calls `[powerMon refreshPowerSourceStatus]` and checks `batteryPercentage` bounds | Valid runtime check on current host hardware. |
| 7 | `MPTimedAwakeManager monotonic countdown and session lifecycle` | 149–194 | Tests 30m start, 1h overwrite, 0s boundary, 2h start + cancel, repeated cancel | Valid unit test of `MPTimedAwakeManager` (though clock is wall-clock `NSDate`, not monotonic). |
| 8 | `MPPriorityArbiter dynamic Timed Awake manager integration and fallback` | 196–212 | Wires `timedMgr` to `arbiter`, starts 30m session, cancels, checks fallback to `Disabled` | **CRITICAL SIDE EFFECT (`QA-001`):** Sets `settings.keepAwakeWhileCharging = NO;` at line 199 and **never restores it to `YES`** before `runSelfTests()` exits! |
| 9 | `MPAboutWindowController utility panel instantiation and feature coverage` | 214–230 | Instantiates `[MPAboutWindowController sharedController]`, checks title and `440x420` size | Valid UI instantiation check. |
| 10 | `Clean teardown and assertion release` | 232–239 | Stops arbiter, releases all assertions, verifies `!pm.isSystemSleepPrevented` | Valid teardown check. |

---

## 4. Audit of Tier 5 Adversarial Tests (`Tests/tiers/tier5_adversarial/`)

| Test Program | Execution Result (2026-11-07) | Critical Findings |
|---|---|---|
| `test_power_manager_stress` (`test_power_manager_stress.m`) | **FAILED (Exit Code 1)** in `0.36s`: `INVARIANT VIOLATION: Display sleep prevented while system sleep allowed! FAIL: 1 invariant violations during multi-threaded stress!` | `isSystemSleepPrevented` and `isDisplaySleepPrevented` lock `_lock` separately (`TOCTOU` race `QA-003`). |
| `test_arbiter_exhaustive_matrix` (`test_arbiter_exhaustive_matrix.m`) | **PASSED (Exit Code 0)** in `0.59s` (3,840 state combinations) | 1. Lines 42–45 explicitly removed `kMPAppSettingsDidChangeNotification` observer from `arbiter`, hiding the synchronous recursive re-entrancy bug (`POWER-001`).<br>2. Writes 3,840 state permutations directly to the user's live `com.shoaib.macpulse` `NSUserDefaults` (`QA-001`)! |
| `test_debounce_stress` (`test_debounce_stress.m`) | **PASSED (Exit Code 0)** in `1.66s` | Lines 69–71 catch `VULNERABILITY DETECTED [CHALLENGE-01]` (race between `handleHardwareNotification` and `stopMonitoring`) and print to `stderr` without failing the test (`POWER-004`). |
| `test_pmset_lifecycle.sh` | Not re-run during live user session because **Line 21 executes `killall MacPulse`**, which destroys the user's running `/Applications/MacPulse.app` instance! | Destructive test script (`QA-001` / `SEC-001`). |
| `swift test` (`Tests/MacPulseKitTests/MacPulseKitTests.swift`) | **FAILED (Exit Code 1)** | Fails to link `Package.swift` manifest under CommandLineTools (`ARCH-001`). |

---

## 5. Missing Test Coverage & Highest-Risk Untested Behaviors

1. **Battery Cutoff with Notification Observer Active (`POWER-001`):** No test exercises `MPPriorityArbiter` battery cutoff while `kMPAppSettingsDidChangeNotification` is connected as it is in production.
2. **Real Timed Awake E2E (`QA-002`):** No E2E test starts a real 2-second Timed Awake session inside a running `MacPulse` process and verifies via `pmset -g assertions` that `PreventUserIdleSystemSleep` is held during the countdown and automatically released upon expiration.
3. **Invalid / Corrupted Preference Boundaries (`SCOPE-002`):** No test verifies `MPAppSettings` behavior when `batterySafetyThreshold` is set to `-50`, `0`, `5`, `95`, `999`, or a non-numeric string `"abc"`.
4. **Sleep/Wake & Clamshell Transitions (`POWER-003`):** Completely untested (`NOT VERIFIED`).
5. **Physical Charger Unplug/Plug & Real Battery Discharge:** Completely untested (`NOT VERIFIED` — see `audit/13_MANUAL_HARDWARE_TEST_PLAN.md`).
