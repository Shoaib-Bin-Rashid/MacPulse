# 14 — Final Release Checklist

Use this practical, gate-by-gate checklist before cutting any public release (`v1.0.0` or later) of MacPulse. Every item must be checked off with command output or visual confirmation before publishing artifacts to GitHub Releases or Homebrew.

---

## Gate 1: Scope, Source Tree & Git Hygiene

- [ ] **Single Source of Truth (`ARCH-001`):** Dead Swift files (`Sources/MacPulse/`, `Sources/MacPulseKit/`, `Tests/MacPulseKitTests/`, `Package.swift`) are removed; only `Sources/MacPulseNative/` exists.
- [ ] **Canonical Display Sleep Alignment (`SCOPE-001`):** `grep -rn "PreventUserIdleDisplaySleep" Sources/` returns **zero** matches; `"Allow Display Sleep"` is removed from the menu and About window.
- [ ] **Clean Build Script (`REL-002`):** Running `./build.sh` compiles only into `./build/` without overwriting `/Applications/MacPulse.app` or `~/Applications/MacPulse.app` unless `--install` is explicitly passed.
- [ ] **Version & Build Metadata (`REL-003`):** `Info.plist.in` contains `<string>__BUILD__</string>` for `CFBundleVersion` and correct `CFBundleShortVersionString` (e.g., `1.0.0`).
- [ ] **Single-Instance Guard (`SEC-001`):** `Info.plist.in` includes `<key>LSMultipleInstancesProhibited</key><true/>`.
- [ ] **MIT License File (`REL-003`):** Root `/LICENSE` file exists with standard MIT text.
- [ ] **Clean Git Working Tree (`REL-003`):** `git status --porcelain` is completely empty, and the release commit is tagged (`git tag -a v1.0.0`).

---

## Gate 2: Binary Architecture, Privacy & Static Verification

- [ ] **Universal Fat Binary (`arm64` + `x86_64`):**
  ```zsh
  lipo -detailed_info build/MacPulse.app/Contents/MacOS/MacPulse
  ```
  Confirms both `x86_64` and `arm64` slices are present.
- [ ] **Minimum Deployment Target (`macOS 13.0`):**
  ```zsh
  otool -l build/MacPulse.app/Contents/MacOS/MacPulse | grep -A 4 LC_BUILD_VERSION
  ```
  Confirms `minos 13.0` on both architecture slices.
- [ ] **Zero Network or Third-Party Dynamic Libraries:**
  ```zsh
  otool -L build/MacPulse.app/Contents/MacOS/MacPulse
  ```
  Confirms only Apple system frameworks (`Cocoa`, `IOKit`, `ServiceManagement`, `Foundation`, `AppKit`, `CoreFoundation`, `libobjc`, `libSystem`) are linked.

---

## Gate 3: Automated Test Suites & Preference Isolation

- [ ] **Preference Isolation Check (`QA-001`):**
  ```zsh
  defaults read com.shoaib.macpulse > /tmp/prefs_before.txt
  ./build/bin/MacPulse --selftest
  ./Tests/run_e2e_tests.sh
  ./Tests/tiers/tier5_adversarial/run_adversarial_tests.sh
  defaults read com.shoaib.macpulse > /tmp/prefs_after.txt
  diff -u /tmp/prefs_before.txt /tmp/prefs_after.txt
  ```
  Confirms all test suites exit `0` AND `diff` produces **zero** differences in the user's live `com.shoaib.macpulse` preferences.
- [ ] **Zero Lingering Assertions Post-Test:**
  ```zsh
  pmset -g assertions | grep -i MacPulse
  ```
  Confirms zero orphaned test assertions remain in `powerd`.

---

## Gate 4: Manual Hardware & UX Sign-Off (`13_MANUAL_HARDWARE_TEST_PLAN.md`)

- [ ] **Test H-01 (Physical Charger Unplug/Plug):** Verified `<500ms` assertion release on unplug and creation on plug.
- [ ] **Test H-02 (Rapid Charger Bounce):** Verified 5 rapid plug/unplug cycles leave zero duplicate assertions.
- [ ] **Test H-03 (Low-Battery Cutoff):** Verified `Always Awake` disengages at `<= threshold` on battery and updates menu status to indicate low-battery cutoff (`POWER-001`).
- [ ] **Test H-04 (Normal Display Sleep):** Verified screen turns off on idle timeout while background tasks stay awake on AC power.
- [ ] **Test H-05 (Clamshell & Explicit Sleep):** Verified lid close and Apple Menu > Sleep are respected and wake reconciles state (`POWER-003`).
- [ ] **Test H-06 (Launch at Login):** Verified login startup and actionable alert when System Settings approval is required (`UX-002`).
- [ ] **Test H-08 (`x86_64` Slice):** Verified `arch -x86_64` execution passes `--selftest`.
- [ ] **Timed Awake Submenu Hover (`PERF-001`):** Verified opening `Timed Awake` submenu during active countdown maintains smooth hover highlight without 1 Hz submenu resets.
- [ ] **App Icon Visual Check (`UX-003`):** Verified `AppIcon.icns` in Finder, Launchpad, Spotlight, and About window in Light and Dark modes (no embedded text blur, no white bottom-corner fringe).

---

## Gate 5: Code Signing, Notarization & Packaging (`REL-001`)

- [ ] **Developer ID + Hardened Runtime Signature on `.app`:**
  ```zsh
  codesign -dvvv --strict build/MacPulse.app
  ```
  Confirms `Authority=Developer ID Application: ...` and `flags=0x10000(runtime)`.
- [ ] **Notarized & Stapled DMG (`dist/MacPulse.dmg`):**
  ```zsh
  xcrun stapler validate dist/MacPulse.dmg
  spctl --assess --type open --context context:primary-signature -vv dist/MacPulse.dmg
  hdiutil verify dist/MacPulse.dmg
  ```
  All three commands exit `0` (`accepted` / `validated` / `verified`).
- [ ] **Clean Zip Archive (If Distributed Alongside DMG):**
  Created via `ditto -c -k --sequesterRsrc --keepParent build/MacPulse.app dist/MacPulse.app.zip` (zero `__MACOSX` clutter).
- [ ] **Quarantine Simulation Test:**
  Copy `dist/MacPulse.dmg` to `/tmp/test_download.dmg`, apply quarantine (`xattr -w com.apple.quarantine "0081;00000000;Safari;" /tmp/test_download.dmg`), mount it, drag `MacPulse.app` to `/Applications`, and launch it in Finder. Confirm macOS opens `MacPulse` cleanly without a Gatekeeper block dialog.
- [ ] **SHA-256 Checksums Generated:**
  ```zsh
  shasum -a 256 dist/MacPulse.dmg dist/MacPulse.app.zip > dist/SHA256SUMS.txt
  ```
