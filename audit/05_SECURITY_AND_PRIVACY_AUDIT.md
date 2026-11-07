# 05 — Security and Privacy Audit

- **Sector Score:** **3.5 / 5**
- **Confidence:** High
- **Evidence Coverage:** Static Inspection (100% of source files, `Info.plist.in`, build/package scripts), Automated Binary Inspection (`otool -L`, `codesign -dvvv`, `spctl --assess`, `strings`)
- **Unresolved Findings:** 3 (`REL-001` [P0], `QA-001` [P0], `SEC-001` [P3])
- **NOT VERIFIED Requirements:** 0

---

## 1. Privacy Verification (§2 Privacy Direction)

Every privacy requirement from the Canonical Product Context was independently verified against the compiled binary (`build/bin/MacPulse`) and source tree (`Sources/`):

| Privacy Requirement | Verification Method | Evidence | Status |
|---|---|---|---|
| **No user account** | Static inspection of all `.m`/`.swift` files | Zero authentication, account, or user profile structures exist. | **VERIFIED** |
| **No cloud synchronization** | Static inspection + `Info.plist.in` | No iCloud (`NSUbiquitousKeyValueStore` / CloudKit) entitlements or APIs used. | **VERIFIED** |
| **No analytics or telemetry** | Static inspection + `otool -L` | Zero third-party SDKs linked; no crash reporters or telemetry endpoints. | **VERIFIED** |
| **No network communication** | `otool -L build/bin/MacPulse` + symbol table inspection | Links only `Cocoa`, `IOKit`, `ServiceManagement`, `Foundation`, `AppKit`, `CoreFoundation`, `libobjc`, `libSystem`. Zero references to `NSURLSession`, `NSURLConnection`, `CFNetwork`, `NWConnection`, or `socket`. | **VERIFIED (100% Offline)** |
| **No backend dependency** | Static + Runtime inspection | Operates 100% locally via `IOKit` (`powerd`) and `NSUserDefaults`. | **VERIFIED** |
| **No personal data collection** | Static inspection of `MPAppSettings.m` | Stores only 4 local keys in `~/Library/Preferences/com.shoaib.macpulse.plist`: `keepAwakeWhileCharging` (bool), `alwaysAwake` (bool), `allowDisplaySleep` (bool), `batterySafetyThreshold` (int), plus temporary `activeTimedDuration` (int). | **VERIFIED** |

---

## 2. Permissions, Entitlements, and Code Signing Audit

### 2.1 Code Signing & Gatekeeper Status (`REL-001` — P0 Release Blocker)

Read-only inspection of `build/MacPulse.app` and `dist/MacPulse.dmg` yielded:

```text
$ codesign -dvvv build/MacPulse.app
Identifier=com.shoaib.macpulse
Format=app bundle with Mach-O universal (x86_64 arm64)
CodeDirectory v=20400 size=492 flags=0x2(adhoc) hashes=9+3 location=embedded
Signature=adhoc
TeamIdentifier=not set

$ spctl --assess --type execute -vv build/MacPulse.app
build/MacPulse.app: rejected
source=no usable signature

$ spctl --assess --type open --context context:primary-signature -vv dist/MacPulse.dmg
dist/MacPulse.dmg: rejected
source=no usable signature

$ xcrun stapler validate build/MacPulse.app
MacPulse.app does not have a ticket stapled to it.
```

**Security Risks of Current Signing Configuration:**
1. **No Hardened Runtime (`flags=0x2(adhoc)` instead of `0x10000(runtime)`):** Without `--options runtime`, the process is not protected by macOS Hardened Runtime against dynamic library injection (`DYLD_INSERT_LIBRARIES`), code-signing enforcement on pages, or debugging attachment by untrusted processes under the same UID.
2. **Ad-Hoc Signature (`--sign -`):** Anyone can modify the binary and re-sign it ad-hoc; macOS Gatekeeper immediately blocks execution when the app has the `com.apple.quarantine` attribute (downloaded via Safari/Chrome from GitHub Releases).
3. **No Apple Notarization or Stapled Ticket:** Required by macOS 10.15+ for all Developer ID-distributed software outside the Mac App Store.

### 2.2 App Sandbox & Entitlements Analysis
- **Current State:** No `.entitlements` file exists in the repository; the app runs unsandboxed as a standard user-level `LSUIElement` agent.
- **Does MacPulse Need Special Entitlements?**
  - `IOPMAssertionCreateWithName` / `IOPMAssertionRelease` (`kIOPMAssertionTypePreventUserIdleSystemSleep`), `IOPSCopyPowerSourcesInfo`, `IOPSNotificationCreateRunLoopSource`, and `SMAppService.mainApp` all work as an unprivileged standard user without root privileges, without Accessibility (`AXIsProcessTrusted`) permissions, and without Full Disk Access.
  - For direct distribution outside the Mac App Store (GitHub Releases / DMG / Homebrew Cask), Hardened Runtime (`--options runtime`) with an empty entitlements plist (disallowing debugging/injection) is sufficient and recommended.

---

## 3. Supply Chain & Dependency Inventory

| Dependency / Tool | Scope | Shipped in `.app`? | Justification & Risk Assessment |
|---|---|---|---|
| `Cocoa.framework` / `AppKit.framework` | Runtime | System Framework | Required for `NSApplication`, `NSStatusItem`, `NSMenu`, `NSPanel`. |
| `IOKit.framework` | Runtime | System Framework | Required for `IOPMAssertion` and `IOPowerSources`. |
| `ServiceManagement.framework` | Runtime | System Framework | Required for `SMAppService.mainApp` Login Item management. |
| `Foundation.framework` / `CoreFoundation.framework` | Runtime | System Framework | Standard Objective-C/C runtime foundation. |
| `package.json` (`scripts/build.ts`, `scripts/package.ts`) | Dev Tooling | **No** | Zero `dependencies` or `devDependencies` in `package.json`. Wraps `build.sh` and `hdiutil`. Redundant with `build.sh` and `scripts/package.sh` (`REL-003`). |

**Supply Chain Verdict:** Zero third-party libraries, zero CocoaPods, zero Swift Package external dependencies, and zero npm packages. Attack surface from third-party dependencies is **zero**.

---

## 4. Threat Model

### 4.1 Assets
1. **Host System Power State Availability:** Ensuring the Mac sleeps when on low battery (preventing battery exhaustion or thermal wear inside a closed bag) and stays awake when expected.
2. **User Preferences Integrity:** `~/Library/Preferences/com.shoaib.macpulse.plist`.
3. **Application Binary Integrity:** `/Applications/MacPulse.app/Contents/MacOS/MacPulse` (especially when registered as a persistent Login Item via `SMAppService.mainApp`).

### 4.2 Trust Boundaries
1. **User Process (`MacPulse`) ↔ macOS Kernel (`powerd` / `IOKit`):** Crosses via Mach traps (`IOPMAssertionCreateWithName`, `IOPSCopyPowerSourcesInfo`).
2. **User Process (`MacPulse`) ↔ `cfprefsd` (`NSUserDefaults`):** Untrusted or corrupted local preference plist values read into `MPAppSettings`.
3. **User Process (`MacPulse`) ↔ `smd` / `launchd` (`SMAppService`):** Login item registration for `com.shoaib.macpulse`.
4. **External Download (`GitHub / DMG`) ↔ macOS Gatekeeper (`syspolicyd`):** Signature and notarization verification upon download.

### 4.3 Plausible Threats, Mitigations, and Residual Risks

| Threat ID | Plausible Threat | Existing Mitigation | Missing Mitigation / Vulnerability | Severity / Finding ID |
|---|---|---|---|---|
| **T-01** | **Tampered binary or Gatekeeper rejection on download** | `hdiutil` UDZO checksum | Ad-hoc signed (`--sign -`), no Hardened Runtime (`--options runtime`), no Developer ID signature, no Notarization. | **P0 (`REL-001`)** |
| **T-02** | **Test CLI flag (`--selftest`) invoked in production corrupts user settings** | None | `--selftest` is compiled unconditionally into the production binary and mutates live `com.shoaib.macpulse` preferences, leaving `keepAwakeWhileCharging = NO`. | **P0 (`QA-001`)** |
| **T-03** | **Corrupted or out-of-range `batterySafetyThreshold` in `NSUserDefaults`** | `MPAppSettings.m` line 91 checks `threshold > 0` | Does not clamp upper or lower bounds (`[10, 50]`). If `batterySafetyThreshold` is set to `5` (below safe reserve) or `100` (always cuts off on battery), `MPAppSettings` accepts it unconditionally. | **P2 (`SCOPE-002`)** |
| **T-04** | **Unintended screen-lock bypass via Display Sleep prevention** | `allowDisplaySleep` defaults to `YES` | Out-of-scope `"Allow Display Sleep"` toggle (`PreventUserIdleDisplaySleep`) prevents screen dimming and automatic screen lock after idle timeout if unchecked by the user. | **P1 (`SCOPE-001`)** |
| **T-05** | **Multiple concurrent instances holding duplicate assertions** | `LSMultipleInstancesProhibited` not set | Launching binary from CLI or duplicate bundle paths (`/Applications` vs `~/Applications`) creates multiple processes and status bar icons. | **P3 (`SEC-001`)** |
| **T-06** | **Login Item bundle hijacking via writable `~/Applications/MacPulse.app`** | None | `build.sh` installs and registers both `~/Applications/MacPulse.app` and `/Applications/MacPulse.app` with LaunchServices (`lsregister -f`). | **P1 (`REL-002`)** |

---

## 5. Additional Security Inspection Checks

- **Secrets in Repository:** Inspected working tree and git commit `6461428`. Zero API keys, certificates, passwords, or private tokens exist in the repository.
- **Shell Command Execution in App:** Production Objective-C code (`Sources/MacPulseNative/*.m`) never calls `system()`, `popen()`, `NSTask`, or `posix_spawn()`.
- **Temporary File Usage in Build/Test Scripts:** `tools/selftest.sh` uses hardcoded `/tmp/MacPulse-self.store` (`rm -f /tmp/MacPulse-self.store`), whereas `Tests/common/test_harness.sh` and `tools/make_icon.sh` properly use `mktemp -d`.
