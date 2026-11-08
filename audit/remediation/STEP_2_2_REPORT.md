# MacPulse — Step 2.2: Installation Transaction Safety Report

**Date:** 2026-11-08  
**Baseline Commit:** `e5ac87b` (feat(step-2.1): build script safety, test reconciliation, legal wording, and timer scope)  
**Author:** Shoaib Bin Rashid  
**Status:** Verification Complete & Ready for Review  

---

## Executive Summary

Step 2.2 hardens the installation transaction lifecycle in `build.sh` to eliminate failure and data loss risks during application upgrades.

In commit `e5ac87b`, an installation rollback design flaw was identified:
1. `install_target` was backed up to a temporary directory in `/tmp`.
2. `install_target` was deleted using `rm -rf`.
3. The new bundle was copied to `install_target`.
4. The signal trap handler deleted the temporary backup directory on exit.
5. If an interruption (SIGINT, SIGTERM, crash, or power loss) occurred after target deletion but before copy completion, the trap handler would purge the backup directory, destroying the only copy of the working application.

Step 2.2 replaces this pattern with an **atomic, same-filesystem transactional swap and rollback architecture**:
- **Same-Filesystem Staging:** Staging occurs directly on the destination directory/volume (`$target_dir/.MacPulse.staging.$$.app`).
- **Comprehensive Pre-Swap Validation:** Info.plist, CFBundleIdentifier, dual fat Mach-O architectures (`arm64` + `x86_64`), and code signatures are validated before the target is touched.
- **Foreign Application Protection:** Replaces only if the destination is unassigned or verified as `com.shoaib.macpulse`. Never overwrites foreign applications.
- **Sibling Atomic Renaming:** Existing target is preserved by renaming to sibling backup (`mv "$install_target" "$backup_app"`).
- **Atomic Swap:** Staged bundle is renamed into target position (`mv "$stage_app" "$install_target"`), completing in a single POSIX filesystem metadata update.
- **Post-Replacement Integrity Check:** The installed app is re-verified (`plutil`, executable bit, `codesign`) before the transaction commits.
- **Fail-Safe Rollback Trap:** On any failure or signal interruption (EXIT, INT, TERM, HUP) prior to commit, the previous installation is restored. The backup is never deleted while the target is invalid or missing.
- **Crash Recovery (`--recover`):** Stale backups or staging directories from abnormal terminations (e.g. SIGKILL or power outage) are detected and restored.

---

## 1. Vulnerability Analysis & Transaction Safety Protocol

### Identified Vulnerability in Baseline Commit `e5ac87b`
```
Target -> rm -rf (target missing) -> cp -R (interrupted!) -> trap deletes backup -> Data Loss!
```
1. **Window of Vulnerability:** Between `rm -rf "$install_target"` and `cp -R`, the application was nonexistent on disk.
2. **Unsafe Trap Cleanup:** The trap handler `cleanup_stage` cleaned up `$backup_dir` indiscriminately on `EXIT INT TERM`.
3. **Cross-Volume Non-Atomicity:** Copying across filesystems was non-atomic and prone to partial disk writes.

### Step 2.2 Transaction Architecture
```
[Phase 1] Verify target is MacPulse (abort if foreign bundle ID)
[Phase 2] Stage in target_dir/.MacPulse.staging.$$.app (same filesystem)
[Phase 3] Pre-Swap Validation (plutil, bundle ID, arm64+x86_64 lipo, codesign)
[Phase 4] Rename target -> target_dir/.MacPulse.backup.$$.app (atomic sibling rename)
[Phase 5] Rename staging -> target (atomic POSIX rename)
[Phase 6] Post-Replacement Verification (verify executable, plist, codesign)
[Phase 7] Commit Transaction (COMMITTED state set)
[Phase 8] Registration with LaunchServices & mdimport
[Cleanup] Remove temporary staging and backup only after verification succeeds
```

---

## 2. Test Execution & Controlled Failure Injection Matrix

An automated end-to-end transaction test suite was developed in `Tests/test_install_transaction.sh` using controlled failure injection hooks within an isolated sandbox environment (`MACPULSE_INSTALL_DIR`). Production applications in `/Applications` were never touched during testing.

| Test # | Scenario | Injected Condition / Action | Observed Behavior | Status |
| :---: | :--- | :--- | :--- | :---: |
| **1** | Clean Install | Target directory is empty | Application staged, validated, and deployed cleanly | **PASS** |
| **2** | Existing Installation | Existing valid installation present | Marker placed; existing installation verified prior to swap | **PASS** |
| **3** | Successful Replacement | Clean upgrade from v1 to v2 | Atomic rename executed; marker cleanly superseded; new bundle verified | **PASS** |
| **4** | Invalid Info.plist | `MACPULSE_FAIL_INJECT_STAGE_PLIST=1` | Pre-swap validation aborted; target untouched; original marker intact | **PASS** |
| **5** | Missing Architecture | `MACPULSE_FAIL_INJECT_STAGE_ARCH=1` | Architecture check failed; target untouched; original marker intact | **PASS** |
| **6** | Staging Copy Failure | `MACPULSE_FAIL_INJECT_COPY=1` | Staging aborted; target untouched; original marker intact | **PASS** |
| **7** | Swap / Rename Failure | `MACPULSE_FAIL_INJECT_SWAP=1` | Swap failed; trap automatically restored backup to target; original marker intact | **PASS** |
| **8** | SIGTERM Interruption | `MACPULSE_FAIL_INJECT_SIGTERM=1` | Signal caught after backup rename; trap restored backup to target; marker intact | **PASS** |
| **9** | SIGINT Interruption | `MACPULSE_FAIL_INJECT_SIGINT=1` | Signal caught after backup rename; trap restored backup to target; marker intact | **PASS** |
| **10** | Crash Recovery | Simulated SIGKILL with orphan backup | `./build.sh --recover` detected lingering backup and restored the application | **PASS** |
| **11** | Foreign App Protection | Target exists with different bundle ID | Script detected `com.othercompany.differentapp` and refused to overwrite | **PASS** |

**Transaction Suite Result:** 11/11 Passed, 0 Failed.

---

## 3. Regression Suite Verification

- **In-App Headless Selftest:** 10/10 PASS
- **Tier 1 Automated Regression Suites:** 10 suites, 52 test cases (`./Tests/run_e2e_tests.sh --tier 1`) — 52/52 PASS
- **Normal Build Isolation:** Running `./build.sh` without flags modifies strictly `build/MacPulse.app` and touches zero files outside `build/`.
