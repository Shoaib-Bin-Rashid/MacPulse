# MacPulse — Engineering Review 01

* **Reviewer:** Senior macOS Systems & Software Engineering Mentor
* **Date:** 2026-11-06
* **Target Project:** MacPulse (`/Users/shoaib/Workspace/Projects/MacPulse`)
* **Status:** Review Complete (Pending Approval for Remediation)

---

## 1. Executive Summary

MacPulse has reached an operational proof-of-concept milestone. The core system architecture successfully boots as a native macOS menu bar utility (`LSUIElement = true`), communicates with hardware power sources via `IOPSNotificationCreateRunLoopSource` without busy-polling, and holds active `kIOPMAssertionTypePreventUserIdleSystemSleep` kernel assertions verified via `pmset -g assertions`.

However, an exhaustive engineering audit of the codebase reveals **several critical architectural divergences, functional defects, and distribution gaps** that must be resolved before this can be considered production-ready software:

1. **Dual-Codebase Fragmentation:** The project currently maintains two parallel, disconnected implementations: a pure Swift SPM module (`Sources/MacPulseKit` + `Sources/MacPulse`) and an Objective-C / AppKit monolithic file (`Sources/MacPulseNative/main.m`). Only the Objective-C binary is currently built and shipped in `build.sh`.
2. **Display Sleep Setting Is Non-Functional (Confirmed Defect):** While the UI offers an "Allow Display Sleep" toggle, the assertion engine never creates or releases `kIOPMAssertionTypePreventUserIdleDisplaySleep`. Disabling this toggle currently does nothing.
3. **Single-Architecture Build (arm64 Only):** The roadmap mandates a Universal Binary (`arm64 + x86_64`), but the current compiler invocation emits a single-architecture arm64 slice, breaking Intel compatibility.
4. **Missing Timed Awake Mode:** The roadmap's P1 feature ("Timed Awake: 30m, 1h, 2h") is entirely absent from the codebase.
5. **Missing Project Assets & Metadata:** `LICENSE` (MIT) and `README.md` are missing from the project root; `MacPulse.xcodeproj` was not created.

---

## 2. Architecture Diagram & Codebase Analysis

### Current Execution Path

```text
[Hardware AC Event]
       │
       ▼ (CFRunLoopSource interrupt)
[IOPSNotificationCreateRunLoopSource] ──► [MPPowerSourceMonitor]
                                                 │
                                                 ▼ (Main Thread Dispatch)
                                      [MPStatusMenuController]
                                                 │
                                                 ▼ evaluateAwakeState
                                         [MPPowerManager]
                                                 │
                                                 ▼ IOPMAssertionCreateWithName
                           [kIOPMAssertionTypePreventUserIdleSystemSleep]
```

### Module Boundary Breakdown

| Module | Language | Role in Project | Current Problem |
| :--- | :--- | :--- | :--- |
| `Sources/MacPulseNative/main.m` | Objective-C (ARC) | Contains the actual shipped executable | Monolithic file combining UI, Settings, IOKit, and RunLoop monitoring in 520 lines. Bypasses Swift tests. |
| `Sources/MacPulseKit/` | Swift 6 | Planned core library | Separated into clean classes (`PowerManager`, `PowerSourceMonitor`, `AppSettings`, `LoginItemManager`), but completely unlinked from the running `.app`. |
| `Sources/MacPulse/` | Swift 6 | Planned SwiftUI/AppKit app | Contains `App.swift` and `StatusMenuController.swift`, but unused by `build.sh`. |
| `scripts/` | Shell / Bun (TS) | Build and packaging pipelines | `build.sh` and `scripts/package.sh` work directly; `scripts/build.ts` and `package.ts` exist but require Bun runtime. |

---

## 3. Critical Issues

### Issue C-01: "Allow Display Sleep" Toggle Is Completely Inert (Confirmed Defect)
* **File:** `Sources/MacPulseNative/main.m` (and duplicated in `Sources/MacPulse/StatusMenuController.swift`)
* **Functions:** `-[MPStatusMenuController toggleAllowDisplaySleep]`, `-[MPStatusMenuController evaluateAwakeState]`
* **Why it matters:** The UI explicitly displays a toggle: `"Allow Display Sleep"`. When a user unchecks it, their intent is to keep the screen powered on (e.g. monitoring a long-running compile or presentation). However, `evaluateAwakeState` only evaluates:
  ```objc
  BOOL shouldBeAwake = _settings.alwaysAwake || (_settings.keepAwakeWhileCharging && _powerMonitor.isACConnected);
  if (shouldBeAwake) {
      [_powerManager createPreventSystemSleepAssertionWithReason:reason];
  }
  ```
  Neither `MPPowerManager` nor `PowerManager.swift` possesses any logic or API to create `kIOPMAssertionTypePreventUserIdleDisplaySleep`. The user setting changes in `NSUserDefaults`, the checkmark toggles, but the display will still turn off.
* **How to verify:**
  1. Open MacPulse and uncheck "Allow Display Sleep".
  2. Run `pmset -g assertions`.
  3. Notice `PreventUserIdleDisplaySleep` count remains `0`.
* **Recommended fix:**
  Add a dedicated `displayAssertionID` (`IOPMAssertionID`) to `PowerManager`. When `!allowDisplaySleep && isAwake`, create `kIOPMAssertionTypePreventUserIdleDisplaySleep`. When `allowDisplaySleep` is enabled or system sleep assertion is released, release the display assertion.

---

### Issue C-02: Codebase Duplication & Drift (Swift vs. Objective-C)
* **Files:** Entire `Sources/MacPulseKit/` vs. `Sources/MacPulseNative/main.m`
* **Why it matters:** There are two independent implementations of `PowerManager`, `PowerSourceMonitor`, `AppSettings`, and `StatusMenuController`. If a bug is fixed or a feature is added in `MacPulseKit`, the shipped application (which builds from `main.m`) remains untouched. This violates DRY (Don't Repeat Yourself) and makes automated testing misleading.
* **How to verify:** Inspect `build.sh` lines 12–18. It compiles `main.m` directly with `clang` and ignores `Sources/MacPulse/` and `Sources/MacPulseKit/`.
* **Recommended fix:**
  Establish a single source of truth:
  - If Swift toolchain is required per Roadmap, resolve the local toolchain conflict or use an Xcode project target to compile the Swift codebase directly.
  - If Objective-C is retained for footprint reasons, decompose `main.m` into clean modular headers (`MPPowerManager.h/.m`, etc.) and delete the dead Swift duplicates to prevent maintenance drift.

---

## 4. High-Priority Issues

### Issue H-01: Non-Universal Binary Emitted (`arm64` Only)
* **File:** `build.sh` (line 13)
* **Function:** `xcrun clang` invocation
* **Why it matters:** Roadmap Section 1 and Prompt M0 explicitly mandate: `Architectures: Apple Silicon + Intel (arm64 + x86_64)`. The current compilation command does not specify target architectures:
  ```bash
  xcrun clang -fobjc-arc -O2 -framework Cocoa ... -o "$bin_dir/$name"
  ```
  Running `lipo -info build/bin/MacPulse` yields:
  ```text
  Non-fat file: build/bin/MacPulse is architecture: arm64
  ```
  This binary will crash on Intel Macs with `Bad CPU type in executable`.
* **How to verify:** Run `lipo -info ~/Applications/MacPulse.app/Contents/MacOS/MacPulse`.
* **Recommended fix:**
  Add explicit multi-architecture flags to `clang`:
  ```bash
  xcrun clang -fobjc-arc -O2 -arch arm64 -arch x86_64 ...
  ```

---

### Issue H-02: Missing "Timed Awake" Feature (Roadmap Scope Gap)
* **File:** `Sources/MacPulseNative/main.m` & `Sources/MacPulse/StatusMenuController.swift`
* **Why it matters:** Roadmap Section 2 and M3 define four core modes:
  1. Smart Awake
  2. Always Awake
  3. **Timed Awake (30m, 1h, 2h)**
  4. Normal
  Currently, Timed Awake does not exist in any file. There is no submenu, no `NSTimer` or `DispatchSourceTimer`, and no countdown cancellation logic.
* **Recommended fix:**
  Implement a `TimedAwakeController` that accepts durations, creates the assertion, runs a background countdown timer, and safely drops back to the default power state upon expiration.

---

### Issue H-03: Desktop Mac Power Source Detection Flaw
* **File:** `Sources/MacPulseNative/main.m` (lines 208–214) and `Sources/MacPulseKit/PowerSourceMonitor.swift` (lines 64–72)
* **Function:** `refreshPowerSourceStatus`
* **Why it matters:** On Mac mini, Mac Studio, Mac Pro, and iMac machines, there is no battery hardware. In certain macOS versions, `IOPSGetProvidingPowerSourceType(snapshot)` can return NULL or non-standard values when no internal battery exists. If `sourceType` is NULL or doesn't match `kIOPSACPowerValue`, `_isACConnected` defaults to `NO`. On a Mac desktop, MacPulse would believe it is permanently unplugged and never engage Smart Awake.
* **Recommended fix:**
  Inspect power source descriptions for `kIOPMBatteryPowerKey` or determine if the hardware is a portable Mac (`AppleARMPE` / `IOPMPowerSource`). If running on a desktop Mac with wall power, treat as AC connected.

---

## 5. Medium & Low-Priority Improvements

### Issue M-01: Silent Login Item Failure
* **File:** `Sources/MacPulseNative/main.m` (lines 272–284)
* **Function:** `toggleLaunchAtLogin`
* **Observation:** When `SMAppService.mainAppService registerAndReturnError:` encounters `SMAppServiceStatusRequiresApproval`, it returns an error. The current code ignores the error description and simply returns `NO`.
* **Improvement:** If registration fails due to user approval required, present an alert or guide the user to **System Settings > General > Login Items & Extensions**.

### Issue M-02: Missing Project Root Files (`LICENSE`, `README.md`)
* **Observation:** Roadmap M0 requires MIT `LICENSE` and `README.md` at the project root. Neither file exists in `/Users/shoaib/Workspace/Projects/MacPulse/`.
* **Fix:** Add standard MIT License and a concise, professional developer `README.md`.

### Issue M-03: Xcode Project Missing (`MacPulse.xcodeproj`)
* **Observation:** Roadmap M0 specifies `MacPulse.xcodeproj`. The project is currently driven entirely by command-line shell scripts and `Package.swift`.
* **Fix:** Create a clean Xcode project or XcodeGen specification (`project.yml`) so developers can build and profile directly in Xcode.

---

## 6. Test Results With Actual Commands Executed

During this review, the following tests were physically executed on the machine:

### 1. Compilation & Architecture Verification
```bash
$ xcrun clang -fobjc-arc -O2 -framework Cocoa -framework IOKit -framework ServiceManagement Sources/MacPulseNative/main.m -o /tmp/macpulse_test
Result: Exit code 0 (Success in 0.42s)

$ lipo -info build/bin/MacPulse
Result: Non-fat file: build/bin/MacPulse is architecture: arm64  (MISSING x86_64)

$ xcrun clang -fobjc-arc -O2 -arch arm64 -arch x86_64 -framework Cocoa -framework IOKit -framework ServiceManagement Sources/MacPulseNative/main.m -o /tmp/macpulse_fat
$ lipo -info /tmp/macpulse_fat
Result: Architectures in the fat file: /tmp/macpulse_fat are: x86_64 arm64 (Universal verified)
```

### 2. Live Kernel Assertion Test
```bash
$ open ~/Applications/MacPulse.app
$ pmset -g assertions | grep -A 2 -i "MacPulse"
Result:
pid 75038(MacPulse): [0x0003af080001a4c4] 00:00:07 PreventUserIdleSystemSleep named: "MacPulse: Keeping system awake while charging"
```
**Conclusion:** Power assertion creation for system idle sleep works properly when AC is connected.

### 3. Termination Release Test
```bash
$ osascript -e 'quit app "MacPulse"'
$ sleep 1
$ pmset -g assertions | grep -i "MacPulse"
Result: Clean exit. No lingering assertions detected.
```
**Conclusion:** `applicationWillTerminate` assertion cleanup functions correctly.

### 4. DMG Filesystem Integrity Test
```bash
$ hdiutil attach dist/MacPulse.dmg -nobrowse -mountpoint /tmp/macpulse_dmg_mount
Result: Verified checksum CRC32 $08733025. APFS filesystem mounts cleanly with MacPulse.app and /Applications symlink.
$ hdiutil detach /tmp/macpulse_dmg_mount
```

---

## 7. Missing Test Cases & Manual Hardware Checklist

The following test suites must be created to achieve production stability:

- [ ] **Display Sleep Verification Test:** Verify that when "Allow Display Sleep" is unchecked, `pmset -g assertions` reports `PreventUserIdleDisplaySleep`.
- [ ] **Physical Charger Pull Test:** Disconnect the USB-C / MagSafe charger physically. Confirm that `bolt.fill` switches to `bolt.slash` within 500ms and `pmset -g assertions` drops to 0.
- [ ] **Rapid Charger Plug/Unplug Bounce:** Repeatedly plug and unplug power 5 times in 3 seconds. Confirm that no orphan assertion IDs are leaked in IOKit.
- [ ] **Clamshell Mode Verification:** Test lid-closure behavior with and without external monitors.
- [ ] **Login Item Approval State:** Test toggling "Launch at Login" when disabled by administrative policy.

---

## 8. Security & Reliability Risks

1. **Gatekeeper Quarantine on Untrusted Macs:**
   The current DMG and `.app` are signed ad-hoc (`codesign --sign -`). When downloaded via browser on a second Mac, Gatekeeper will attach `com.apple.quarantine` and block execution. A paid Apple Developer ID certificate and `xcrun notarytool` notarization are required for public release.
2. **Hardened Runtime Flag Missing:**
   The `codesign` command in `build.sh` does not specify `--options runtime`. Notarization requires Hardened Runtime to be enabled.

---

## 9. Prioritized Remediation Plan

To advance MacPulse from prototype to production, the issues should be resolved in this sequence:

1. **Priority 1 (Functionality):** Fix Issue C-01 — Wire `kIOPMAssertionTypePreventUserIdleDisplaySleep` into the assertion lifecycle when "Allow Display Sleep" is toggled off.
2. **Priority 2 (Architecture):** Unify the codebase. Either compile the Swift 6 modules into the final bundle, or structure the native C/ObjC engine into clean modular classes.
3. **Priority 3 (Compatibility):** Fix Issue H-01 — Update `build.sh` and `package.sh` to generate true Universal Binaries (`arm64 + x86_64`).
4. **Priority 4 (Feature Completeness):** Implement Timed Awake mode (30m, 1h, 2h durations with countdown).
5. **Priority 5 (Distribution):** Add root `LICENSE`, `README.md`, and configure Hardened Runtime codesigning flags.

---

## 10. Educational Concepts for Developer Mastery

As an aspiring macOS software engineer, here are the key architectural takeaways from this review:

1. **`kIOPMAssertionTypePreventUserIdleSystemSleep` vs. `PreventUserIdleDisplaySleep`:**
   macOS handles screen dimming and kernel sleep as two independent power tiers. A system sleep assertion keeps the CPU, Wi-Fi, and background daemons running even if the screen turns off. A display sleep assertion prevents the panel backlight and GPU from entering low-power states. They must be managed as separate assertion IDs.
2. **Core Foundation Memory Ownership ("The Create / Get Rule"):**
   Functions containing `Create` or `Copy` (e.g. `IOPSCopyPowerSourcesInfo`) return retained objects that your code **must** release with `CFRelease`. Functions containing `Get` (e.g. `IOPSGetProvidingPowerSourceType`) return borrowed references that must **not** be released.
3. **Universal Mach-O Binaries (Fat Binaries):**
   A standard Mach-O binary contains machine code for a single CPU architecture. A Universal binary packages both `arm64` (Apple Silicon) and `x86_64` (Intel) slices inside one file header. Toolchains like `lipo` combine them, and the macOS dynamic linker (`dyld`) selects the appropriate architecture at launch.
4. **App Sandbox vs. Accessory Utilities:**
   `LSUIElement = true` utilities live in the status bar without a Dock icon. Power assertions (`IOPMAssertion`) do not require special entitlements or sandbox exceptions, making MacPulse completely native, secure, and non-intrusive.
