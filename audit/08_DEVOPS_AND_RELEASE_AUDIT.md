# 08 — Build, DevOps, and Release Engineering Audit

- **Sector Score:** **1.5 / 5**
- **Confidence:** High
- **Evidence Coverage:** Static Inspection (`build.sh`, `scripts/package.sh`, `scripts/build.ts`, `scripts/package.ts`, `Info.plist.in`, `package.json`, `git status`) + Automated Verification (`lipo`, `codesign`, `spctl`, `stapler`, `hdiutil`, `unzip -l`)
- **Unresolved Findings:** 4 (`REL-001` [P0], `REL-002` [P1], `ARCH-001` [P1], `REL-003` [P2])
- **NOT VERIFIED Requirements:** 1 (End-to-end Apple `notarytool` submission and Gatekeeper verification on a clean external Mac)

---

## 1. Build Pipeline Review (`build.sh`)

### 1.1 Compiler & Linker Invocation (`build.sh` lines 13–20)
```zsh
xcrun clang -fobjc-arc -O2 \
    -arch arm64 -arch x86_64 \
    -mmacosx-version-min=13.0 \
    -framework Cocoa \
    -framework IOKit \
    -framework ServiceManagement \
    "$here"/Sources/MacPulseNative/*.m \
    -o "$bin_dir/$name"
```
- **What Works Well:** Fast single-step universal compilation (~0.5s), `-fobjc-arc` enabled, `-O2` optimization, explicit `-arch arm64 -arch x86_64`, and `-mmacosx-version-min=13.0`.
- **Missing Compiler Hardening / Warning Flags:** Does not pass `-Wall -Wextra -Wpedantic` or `-fstack-protector-strong`.

### 1.2 Critical Defect in `build.sh`: Unconditional Multi-Location Installation (`REL-002` — P1)
In `build.sh` lines 30–60:
```zsh
app_bundle="$build_dir/$name.app"
system_app="/Applications/$name.app"
user_app="$HOME/Applications/$name.app"
...
target_apps=("$app_bundle" "$user_app")
if touch /Applications/.macpulse_check 2>/dev/null; then
    rm -f /Applications/.macpulse_check
    target_apps+=("$system_app")
fi
```
- **Why It Matters:**
  1. Running `./build.sh` (or `./scripts/package.sh`, which calls `./build.sh` at line 12!) **unconditionally deletes and overwrites both `~/Applications/MacPulse.app` and `/Applications/MacPulse.app`** on the host system! A build script should compile into `./build/MacPulse.app` by default and only install to `/Applications/MacPulse.app` when an explicit `--install` flag is passed.
  2. Installing into **three** paths simultaneously (`build/MacPulse.app`, `~/Applications/MacPulse.app`, and `/Applications/MacPulse.app`) and calling `lsregister -f` and `mdimport` on all three (lines 56–59) registers three identical copies of `com.shoaib.macpulse` in macOS LaunchServices. This causes duplicate entries in Spotlight/Raycast and confuses `SMAppService.mainApp` Login Item registration.

### 1.3 Broken Build Version Substitution in `Info.plist.in` (`REL-003` — P2)
- `build.sh` line 50 executes:
  ```zsh
  sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" "$here/Info.plist.in" > "$target_app/Contents/Info.plist"
  ```
- However, `Info.plist.in` lines 21–22 contain:
  ```xml
  <key>CFBundleVersion</key>
  <string>1</string>
  ```
  Because `__BUILD__` does not exist in `Info.plist.in`, the `sed` command is a silent no-op and `CFBundleVersion` is permanently stuck at `1`.

---

## 2. Packaging & Distribution Artifacts Review

### 2.1 DMG Installer (`dist/MacPulse.dmg` & `scripts/package.sh`)
- **Verified Structure:** `hdiutil verify dist/MacPulse.dmg` passed CRC32 verification (`$FAB5DA46`). Mounting read-only confirmed `MacPulse.app`, the `/Applications` symlink, and `.VolumeIcon.icns`.
- **Script Divergence (`REL-003`):** `scripts/package.sh` copies `Icon/AppIcon.icns` to `.VolumeIcon.icns` and runs `SetFile -a C` (lines 25–32), whereas `scripts/package.ts` (lines 30–56) omits the volume icon logic completely. Furthermore, `package.json` invokes `bun run scripts/package.ts`, which fails because `bun` is not installed on the system (`bun not found`).

### 2.2 Zip Archives (`dist/MacPulse.app.zip` & `dist/MacPulse-AI-Test-Package.zip`)
- Inspecting `unzip -l dist/MacPulse.app.zip` revealed `__MACOSX/._*` AppleDouble resource fork entries (`__MACOSX/MacPulse.app/Contents/MacOS/._MacPulse`, etc.) because it was created with `zip -r` instead of `ditto -c -k --sequesterRsrc --keepParent build/MacPulse.app dist/MacPulse.app.zip`. On macOS, `ditto -c -k --keepParent` is the standard way to package `.app` bundles cleanly.

---

## 3. Code Signing, Hardened Runtime, and Notarization (`REL-001` — P0)

### 3.1 Current State (Read-Only Verification)
- **App Bundle Signature:** `Signature=adhoc`, `flags=0x2(adhoc)`, `TeamIdentifier=not set`.
- **Hardened Runtime:** **Disabled** (missing `--options runtime`).
- **Gatekeeper Assessment (`spctl --assess --type execute -vv build/MacPulse.app`):** `build/MacPulse.app: rejected (source=no usable signature)`.
- **DMG Gatekeeper Assessment (`spctl --assess --type open --context context:primary-signature -vv dist/MacPulse.dmg`):** `dist/MacPulse.dmg: rejected (source=no usable signature)`.
- **Notarization Ticket (`xcrun stapler validate`):** `does not have a ticket stapled to it`.

### 3.2 Exact Steps Required Before Public Release
To distribute `MacPulse.dmg` on GitHub Releases or Homebrew Cask without macOS Gatekeeper blocking users with *"MacPulse.app is damaged and can't be opened"* or *"Apple could not verify MacPulse.app is free of malware"*, the developer must perform the following steps (requiring a paid Apple Developer Program membership):

1. **Sign the Application Bundle with Hardened Runtime:**
   ```zsh
   codesign --force --options runtime --timestamp \
     --sign "Developer ID Application: <Developer Name> (<TEAM_ID>)" \
     build/MacPulse.app
   ```
2. **Build and Sign the DMG:**
   ```zsh
   ./scripts/package.sh
   codesign --force --timestamp \
     --sign "Developer ID Application: <Developer Name> (<TEAM_ID>)" \
     dist/MacPulse.dmg
   ```
3. **Submit the DMG to Apple Notarization Service (`notarytool`):**
   ```zsh
   xcrun notarytool submit dist/MacPulse.dmg \
     --keychain-profile "AC_NOTARY_PROFILE" \
     --wait
   ```
4. **Staple the Notarization Ticket and Verify:**
   ```zsh
   xcrun stapler staple dist/MacPulse.dmg
   spctl --assess --type open --context context:primary-signature -vv dist/MacPulse.dmg
   ```

---

## 4. Git State, Licensing, and CI/CD Pipeline (`REL-003` — P2)

### 4.1 Uncommitted Working Tree
Running `git status -s` and `git log -n 5 --oneline` revealed that the repository has only a single initial template commit (`6461428 Create MacPulse from the macOS app template`), while **100% of the actual MacPulse implementation (`Sources/MacPulseNative/`, `Tests/tiers/`, `README.md`, `PROJECT.md`, `scripts/`) is untracked (`??`)** and 12 deleted Swift template files (`D Sources/MacPulse/ContentView.swift`, etc.) are unstaged. If the working directory were accidentally cleaned (`git clean -fd`), the entire application would be lost.

### 4.2 Missing `LICENSE` File
Canonical requirement §2 and `README.md` line 95 specify the **MIT License**, but no `LICENSE` file exists in `/Users/shoaib/Workspace/Projects/MacPulse/`.

### 4.3 Recommended Lightweight GitHub Actions CI/CD Pipeline
Currently, no `.github/workflows/` directory exists. A minimal, high-value single-file workflow (`.github/workflows/ci.yml` on `macos-14` or `macos-15`) should run on every push and pull request:
1. Compile universal binary (`./build.sh --build-only`).
2. Verify both `arm64` and `x86_64` slices via `lipo -info`.
3. Run headless self-tests (`./build/bin/MacPulse --selftest`) against an isolated preference suite.
4. Run the E2E & Stress test suites.
5. On tagged releases (`v*`), build `dist/MacPulse.dmg`, generate `SHA256SUMS.txt`, and (when Apple Developer secrets are configured) sign, notarize, staple, and upload to GitHub Releases.
