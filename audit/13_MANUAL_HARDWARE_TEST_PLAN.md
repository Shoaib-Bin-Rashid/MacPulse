# 13 — Manual Hardware Test Plan

Because automated local tests cannot physically plug/unplug a MagSafe/USB-C charger, discharge a lithium-ion battery across a safety threshold, close a MacBook lid, or reboot into a fresh login session, all tests in this document are currently classified as **NOT VERIFIED** and must be executed on physical Mac hardware before public release.

---

## 1. Test Environment & Preconditions

### Required Hardware Matrix
1. **Primary Portable Test Device:** Apple Silicon MacBook Air or MacBook Pro (macOS 13 Ventura or later) with working USB-C / MagSafe charger.
2. **Secondary Portable / Intel Test Device (or Rosetta 2 Slice Check):** Intel `x86_64` Mac (or `arch -x86_64 /Applications/MacPulse.app/Contents/MacOS/MacPulse` on Apple Silicon with Rosetta 2 installed).
3. **Desktop Mac Test Device (Optional / Recommended):** Mac mini, Mac Studio, or iMac (no internal battery).

### Pre-Test Setup Commands
Before starting the manual test session, open Terminal and run:
```zsh
# 1. Verify no competing keep-awake tools are running
killall caffeinate Amphetamine KeepingYouAwake 2>/dev/null || true

# 2. Reset MacPulse preferences to clean factory defaults
defaults delete com.shoaib.macpulse 2>/dev/null || true

# 3. Launch MacPulse from /Applications
open /Applications/MacPulse.app
```

---

## 2. Reproducible Hardware Test Cases

### Test H-01: Physical Charger Unplug & Reconnect (Smart Awake Transition)
- **Requirement Covered:** `REQ-01`, `REQ-02` (§3.1, §3.3, §3.4)
- **Preconditions:** MacBook connected to AC charger; `Smart Awake` (`Keep Awake While Charging`) is `ON`; `Timed Awake` and `Always Awake` are `OFF`.
- **Steps:**
  1. Run `pmset -g assertions | grep -i MacPulse` while plugged into AC power.
  2. Physically unplug the MagSafe / USB-C charging cable from the MacBook.
  3. Wait 1 second, observe the menu bar icon, open the MacPulse menu, and run `pmset -g assertions | grep -i MacPulse`.
  4. Physically plug the charging cable back into the MacBook.
  5. Wait 1 second, observe the menu bar icon, open the MacPulse menu, and run `pmset -g assertions | grep -i MacPulse`.
- **Expected Results:**
  - Step 1: Icon is `bolt.fill`; `pmset` shows `PreventUserIdleSystemSleep` held by `MacPulse`.
  - Step 3: Within ~250–500ms of unplugging, icon switches to `bolt.slash`; menu shows `Power Source: Battery (XX%)` and `System Status: Normal Sleep`; `pmset` shows **zero** assertions held by `MacPulse`.
  - Step 5: Within ~250–500ms of plugging back in, icon returns to `bolt.fill`; menu shows `Power Source: AC Power (XX%)`; `pmset` shows `PreventUserIdleSystemSleep` restored with a single assertion ID.
- **Evidence to Capture:** Terminal log of `pmset -g ps` and `pmset -g assertions` before unplug, during battery, and after reconnect.
- **Current Status:** **NOT VERIFIED**

---

### Test H-02: Rapid Physical Charger Bounce (Plug/Unplug 5x in 3 Seconds)
- **Requirement Covered:** `REQ-02`, `REQ-12` (§3.10, §8)
- **Preconditions:** MacBook on AC power with MacPulse running.
- **Steps:**
  1. Rapidly unplug and re-plug the USB-C charger 5 times within ~3–4 seconds, ending in the **unplugged** state.
  2. Wait 1 second and run `pmset -g assertions | grep -i MacPulse`.
  3. Plug the charger back in, wait 1 second, and run `pmset -g assertions | grep -i MacPulse`.
- **Expected Results:**
  - Step 2: Zero assertions held in `pmset`.
  - Step 3: Exactly **one** `PreventUserIdleSystemSleep` assertion held in `pmset` (zero duplicate/leaked assertion IDs).
- **Evidence to Capture:** Terminal output of `pmset -g assertions`.
- **Current Status:** **NOT VERIFIED**

---

### Test H-03: Real Battery Discharge Across Safety Cutoff Threshold
- **Requirement Covered:** `REQ-10`, `REQ-11` (§3.8, §3.9)
- **Preconditions:** Unplugged MacBook running on battery at e.g. `31%` charge (or any charge `N%` where `N` is 1% above a selectable threshold such as `30%`, `40%`, or `50%`).
- **Steps:**
  1. Set `Battery Safety Threshold` to `30%` (when battery is at `31%`).
  2. Enable `Always Awake` (`sun.max.fill` icon appears).
  3. Verify `pmset -g assertions | grep -i MacPulse` shows `PreventUserIdleSystemSleep`.
  4. Allow the MacBook battery to naturally discharge by 1% from `31%` to `30%`.
  5. As soon as macOS battery percentage hits `30%`, inspect the MacPulse menu bar icon, menu items, and `pmset -g assertions | grep -i MacPulse`.
- **Expected Results:**
  - At `30%` (`battery <= threshold`), `Always Awake` automatically disengages (`Always Awake` menu item is unchecked), icon transitions from `sun.max.fill` to `bolt.slash`, `System Status` indicates low-battery cutoff, and `pmset -g assertions` shows **zero** assertions for `MacPulse`.
- **Evidence to Capture:** Screenshot of menu before (`31%`) and after (`30%`) + `pmset -g assertions` output.
- **Current Status:** **NOT VERIFIED**

---

### Test H-04: Normal Display Sleep While System Remains Awake on AC
- **Requirement Covered:** `REQ-01`, `REQ-07` (§3.5)
- **Preconditions:** MacBook connected to AC power; in **System Settings > Lock Screen**, set *"Turn display off on power adapter when inactive"* to **1 minute** (temporarily for test). Start a continuous background job in Terminal (`ping -i 5 1.1.1.1` or a local loop recording `date >> /tmp/awake_heartbeat.log` every 5 seconds).
- **Steps:**
  1. Verify MacPulse shows `bolt.fill` and `pmset -g assertions` lists `PreventUserIdleSystemSleep` (and **not** `PreventUserIdleDisplaySleep`).
  2. Do not touch keyboard or trackpad for 3 minutes.
  3. Observe when the built-in display turns off.
  4. After the display has been off for 2 minutes, wake the screen and inspect `/tmp/awake_heartbeat.log`.
- **Expected Results:**
  - Display turns off normally after ~1 minute of inactivity.
  - System does **not** enter idle sleep while the display is off; `/tmp/awake_heartbeat.log` shows uninterrupted 5-second timestamps across the entire 3-minute window.
- **Evidence to Capture:** Contents of `/tmp/awake_heartbeat.log` and `pmset -g log | tail -n 30`.
- **Current Status:** **NOT VERIFIED**

---

### Test H-05: Clamshell (Lid Close) & Explicit User Sleep Behavior
- **Requirement Covered:** §2, §8 (Safety & OS Sleep Override Boundaries)
- **Preconditions:** MacBook unplugged (with `Always Awake` ON) or plugged into AC (with no external monitor connected).
- **Steps:**
  1. Close the MacBook lid for 30 seconds, then open the lid.
  2. With the lid open and `Always Awake` ON, select **Apple Menu () > Sleep**.
  3. Wake the Mac after 15 seconds and check `pmset -g assertions | grep -i MacPulse` and MacPulse menu responsiveness.
- **Expected Results:**
  - MacPulse does **not** block hardware clamshell sleep or explicit user-initiated sleep.
  - Upon wake (`NSWorkspaceDidWakeNotification`), MacPulse remains responsive and reconciles its current power source and assertion state cleanly.
- **Evidence to Capture:** `pmset -g log | grep -E "Sleep|Wake|Assertions" | tail -n 25`.
- **Current Status:** **NOT VERIFIED**

---

### Test H-06: Launch at Login Across macOS User Logout / Reboot
- **Requirement Covered:** `REQ-08` (§3.6)
- **Preconditions:** Single copy of `MacPulse.app` installed in `/Applications/MacPulse.app`.
- **Steps:**
  1. Open MacPulse menu and click `Launch at Login` so the checkmark (`✓`) is enabled.
  2. Verify in **System Settings > General > Login Items & Extensions** that `MacPulse` is listed under *Open at Login*.
  3. Log out of macOS (or reboot the Mac) and log back in.
  4. Observe the menu bar and run `pgrep -fl MacPulse`.
  5. In **System Settings > General > Login Items & Extensions**, toggle `MacPulse` **OFF**, then click `Launch at Login` in the MacPulse menu.
- **Expected Results:**
  - Step 4: `MacPulse` launches automatically into the menu bar upon login with no Dock icon or main window.
  - Step 5: MacPulse accurately reflects the disabled state and prompts the user to re-enable permission in System Settings when `SMAppServiceStatusRequiresApproval` is encountered (`UX-002`).
- **Evidence to Capture:** Screenshot of Login Items settings and `pgrep -fl MacPulse` post-reboot.
- **Current Status:** **NOT VERIFIED**

---

### Test H-07: Desktop Mac (No Internal Battery) Behavior
- **Requirement Covered:** `REQ-03`, `REQ-06` (§3.1, §3.4)
- **Preconditions:** Run on a Mac mini, Mac Studio, iMac, or Mac Pro.
- **Steps:**
  1. Launch `/Applications/MacPulse.app`.
  2. Open the MacPulse menu and inspect the `Power Source:` line and active mode.
- **Expected Results:**
  - `Power Source: AC Power` is displayed without any `(-1%)` or battery percentage suffix.
  - `Smart Awake` engages automatically on launch.
- **Evidence to Capture:** Screenshot of menu on Desktop Mac.
- **Current Status:** **NOT VERIFIED**

---

### Test H-08: Intel (`x86_64`) Slice Execution Verification
- **Requirement Covered:** `REQ-13` (§2, §12)
- **Preconditions:** Intel Mac or Apple Silicon Mac with Rosetta 2 installed.
- **Steps:**
  1. Run `arch -x86_64 /Applications/MacPulse.app/Contents/MacOS/MacPulse --selftest`.
  2. Launch `arch -x86_64 /Applications/MacPulse.app/Contents/MacOS/MacPulse &` and verify `pmset -g assertions`.
- **Expected Results:**
  - `--selftest` passes 10/10 checks under `x86_64` execution with exit code `0`.
  - `x86_64` process creates and releases `PreventUserIdleSystemSleep` cleanly.
- **Evidence to Capture:** Terminal output of `arch -x86_64 ... --selftest`.
- **Current Status:** **NOT VERIFIED**
