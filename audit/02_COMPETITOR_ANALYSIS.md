# 02 — Product, Market, and Competitor Analysis

- **Sector Score:** **3.5 / 5**
- **Confidence:** High
- **Evidence Coverage:** External Web Research (conducted 2026-11-07 across official GitHub repositories, developer websites, and Mac App Store listings) + Static Inspection of MacPulse
- **Unresolved Findings:** 1 (`BRAND-001` [P2])
- **NOT VERIFIED Requirements:** 0

---

## 1. Competitive Landscape Overview

The macOS "keep-awake" utility market is mature and bifurcated into two extremes:
1. **Ultra-minimal manual toggles** (*Caffeine*, *KeepingYouAwake*, *Lungo*, CLI `caffeinate`) where the user must remember to click an icon before starting a task and remember to click it again when finished (or set a manual timer).
2. **Heavyweight rule-automation suites** (*Amphetamine*) where users can configure dozens of conditional triggers (power adapter, Wi-Fi SSID, DNS, USB devices, running processes, CPU load) across multi-tab preferences windows.

**MacPulse's Strategic Wedge:**
MacPulse targets the underserved middle ground: **"Automatic by default, manual when needed."** Out of the box, with zero configuration or trigger setup, MacPulse keeps the Mac awake whenever connected to AC power (while letting the display sleep normally) and releases the assertion immediately when unplugged to protect battery life—supplemented by quick Timed Awake sessions and a battery-guarded Always Awake override.

---

## 2. Competitor Profiles & Evidence Citations

All competitor research below was verified on **2026-11-07**.

### 2.1 Amphetamine (by William Gustafson)
- **Source URLs:** `https://apps.apple.com/us/app/amphetamine/id937984704` (Research Date: 2026-11-07)
- **Status:** Actively maintained commercial-grade freeware on the Mac App Store.
- **Supported macOS:** macOS 10.13 High Sierra or later (Confirmed).
- **Distribution & Pricing:** Mac App Store ( plus external helper *Amphetamine Enhancer* on GitHub for closed-display fail-safes); 100% Free, no ads or IAP, closed-source proprietary license (Confirmed).
- **Primary UX & Features:**
  - Rich menu-bar interface with quick sessions (indefinite, minutes/hours, until specific clock time, while app runs, while file downloads) (Confirmed).
  - **Triggers Engine:** Supports automatic activation on AC power adapter connection, battery charging state, Wi-Fi SSID, VPN, external display, USB/Bluetooth, audio output, and CPU utilization—**but Triggers are disabled by default and require manual rule creation in a multi-tab Preferences window** (Confirmed).
  - **Battery Protection:** Configurable low-battery threshold to end sessions automatically (Confirmed).
  - **Display Sleep:** Configurable per session or trigger (allow or prevent display sleep, screen saver, closed-display sleep, mouse jiggler) (Confirmed).
- **Strengths:** Unmatched feature depth, AppleScript/Shortcuts support, rock-solid reputation, free.
- **Weaknesses / User Friction:** Steep configuration complexity for casual users; closed-source; Mac App Store sandbox restrictions require an external unsandboxed helper (*Amphetamine Enhancer*) for certain features; default behavior is manual rather than automatic AC-aware keep-awake.

### 2.2 KeepingYouAwake (by Marcel Dierkes / `newmarcel`)
- **Source URLs:** `https://github.com/newmarcel/KeepingYouAwake`, `https://keepingyouawake.app` (Research Date: 2026-11-07)
- **Status:** Actively maintained open-source project.
- **Supported macOS:** macOS 10.13+ through current macOS (Universal binary) (Confirmed).
- **Distribution & Pricing:** GitHub Releases (`.dmg` / `.zip`) and Homebrew Cask (`brew install --cask keepingyouawake`); Free, **MIT License** (Confirmed).
- **Primary UX & Features:**
  - Lightweight wrapper around `/usr/bin/caffeinate` (Confirmed).
  - One-click coffee cup icon in the menu bar toggles indefinite or default-duration keep-awake; right-click/secondary menu selects preset durations (5m, 15m, 30m, 1h, 2h, 5h, custom) (Confirmed).
  - **Battery Protection:** Can automatically deactivate when battery level drops below a user-configured threshold (10%–90%) or when macOS Low Power Mode is enabled (Confirmed).
  - **Automatic AC Power Behavior:** **Does NOT automatically activate when plugged into AC power and deactivate when unplugged** (Confirmed gap— offers "Activate on Launch" or manual click, not automatic charger-state sync).
  - **Display Sleep:** By default spawns `caffeinate -di` (preventing **both** display and system sleep) unless the user opens Settings -> Advanced and checks *"Allow the display to sleep"* (Confirmed).
- **Strengths:** Clean MIT open-source codebase, native look, Sparkle auto-updates, localized in many languages, Homebrew Cask availability.
- **Weaknesses / User Friction:** Spawns a child `/usr/bin/caffeinate` process rather than using in-process `IOPMAssertion` APIs directly; prevents display sleep by default; lacks automatic AC-charger-triggered Smart Awake.

### 2.3 Caffeine (Original by Tomas Franzén / Lighthead; Modernized forks by IntelliScape / `caffeinate-app`)
- **Source URLs:** `https://www.caffeine-app.net`, `https://github.com/IntelliScape/caffeine` (Research Date: 2026-11-07)
- **Status:** Original Lighthead app (2006) was discontinued; modernized open-source forks (such as IntelliScape's Universal build) maintain compatibility for Apple Silicon (Confirmed).
- **Distribution & Pricing:** Direct web download (`.dmg`) and Homebrew Cask (`brew install --cask caffeine`); Free, open-source (Confirmed).
- **Primary UX & Features:**
  - Single-click coffee cup toggle with basic duration presets (Confirmed).
  - Prevents display sleep and screensaver alongside system sleep (Confirmed).
  - Lacks automatic AC charger detection, lacks live battery telemetry, and lacks low-battery safety cutoff (Confirmed).
- **Strengths:** Iconic simplicity and zero learning curve.
- **Weaknesses:** Outdated feature set; prevents display sleep; no battery protection or charger awareness.

### 2.4 Add Caffeine & Mac App Store Equivalents (*Lungo*, *Caffeinated*, *Jolt of Caffeine*)
- **Source URLs:**
  - *Add Caffeine*: Mac App Store listing (`apps.apple.com`) (Research Date: 2026-11-07)
  - *Lungo* (by Sindre Sorhus): `https://sindresorhus.com/lungo`, `https://apps.apple.com/app/id1263070803` (Research Date: 2026-11-07)
  - *Caffeinated*: `https://caffeinated.app` (Research Date: 2026-11-07)
- **Status & Pricing:** Commercial/freemium Mac App Store utilities (*Lungo* and *Caffeinated* are paid/paid-upgrade; *Add Caffeine* and *Jolt of Caffeine* offer free/freemium tiers) (Confirmed).
- **Primary UX & Features:**
  - *Add Caffeine* focuses on app-based triggers (staying awake while specific apps like Terminal or Docker run) plus manual countdown timers and separate display/system sleep options (Confirmed).
  - *Lungo* provides a polished modern menu-bar toggle with durations, low-battery pause, and Shortcuts integration, but is proprietary/paid and oriented around manual/timed sessions rather than zero-config charger automation (Confirmed).

### 2.5 macOS Built-In `/usr/bin/caffeinate`
- **Source:** macOS standard base system (`/usr/bin/caffeinate`, `man caffeinate`) (Verified locally on macOS 26.2).
- **Primary UX & Features:**
  - CLI flags: `-i` (prevent idle system sleep), `-d` (prevent display sleep), `-s` (prevent system sleep on AC power only), `-t <timeout>` (timed session in seconds), `-w <pid>` (wait for process PID).
  - Note: While `caffeinate -s` or `caffeinate -i` exists in Terminal, it requires keeping a Terminal tab or background daemon open, provides no menu-bar status indicator, no GUI countdown, and no configurable battery percentage cutoff (e.g., 20%) for battery overrides.

---

## 3. Feature Comparison Matrix

Legend:
- **Confirmed:** Verified in official documentation, App Store listing, or source code.
- **No (Confirmed):** Verified absent in official documentation/source.
- **Not Found:** Not mentioned in public documentation.

| Capability | **MacPulse (Canonical Target)** | **MacPulse (Current Repo)** | **Amphetamine** | **KeepingYouAwake** | **Caffeine (Forks)** | **Add Caffeine / Lungo** | **macOS `caffeinate`** |
|---|---|---|---|---|---|---|---|
| **License** | MIT (Open Source) | MIT (`LICENSE` file missing: `REL-003`) | Proprietary | MIT (Open Source) | Open Source | Proprietary | Apple System |
| **Price** | Free | Free | Free | Free | Free | Free / Paid | Free (Built-in) |
| **Distribution** | GitHub + DMG + Homebrew | Local DMG (Unsigned/Ad-hoc: `REL-001`) | Mac App Store | GitHub + DMG + Homebrew | Web DMG + Homebrew | Mac App Store | Built-in CLI |
| **Zero-Config Auto Awake on AC** | **Yes (Default ON)** | **Yes (Default ON)** | Manual Trigger setup required | No (Confirmed) | No (Confirmed) | No / App-trigger focus | `caffeinate -s` (CLI only, no GUI) |
| **Auto Release on Unplug** | **Yes (Default)** | **Yes (250ms debounce)** | Only if Trigger configured | No (Confirmed) | No (Confirmed) | Not by default | With `-s` flag only |
| **Normal Display Sleep by Default** | **Always Allowed (No toggle)** | Allowed by default (Has out-of-scope toggle: `SCOPE-001`) | Configurable (Default prevents display sleep) | Prevents display sleep by default (Advanced setting to allow) | No (Prevents display sleep) | Configurable | `caffeinate -i` allows display sleep |
| **Timed Awake Sessions** | **Yes (30m, 1h, 2h)** | **Yes (15m–8h + Custom)** | Yes (Presets + Custom + Clock time) | Yes (Presets + Custom) | Yes (Basic presets) | Yes (Presets) | `caffeinate -t <sec>` (No countdown UI) |
| **Always Awake Override** | **Yes** | **Yes** | Yes | Yes (Default click) | Yes (Default click) | Yes | `caffeinate -i` |
| **Low-Battery Auto-Cutoff** | **Yes (Default 20%, 10%–50%)** | **Yes (Default 20%, 10%–80%; UI feedback missing: `POWER-001`)** | Yes (Confirmed) | Yes (10%–90% + Low Power Mode) | No (Confirmed) | Yes (*Lungo* / *Jolt*) | No (Runs until critical OS sleep) |
| **Per-App / Network Triggers** | **Intentionally Excluded** | **Excluded** | Yes (Extensive) | No | No | Yes (*Add Caffeine*) | `-w <pid>` (CLI only) |
| **In-Process `IOPMAssertion` (No child process)** | **Yes** | **Yes** | Yes | No (Spawns `/usr/bin/caffeinate`) | Yes | Yes | Native process |
| **Launch at Login (`SMAppService`)** | **Yes** | **Yes** | Yes | Yes | Yes | Yes | Requires `launchd` plist |

---

## 4. Product Positioning Analysis

### 4.1 Most Likely MacPulse User
Developers, data scientists, video editors, and remote workers using MacBooks who frequently move between a desk charger (where builds, renders, SSH sessions, and downloads must not be interrupted by idle sleep while the screen dims/locks normally) and battery power (where the MacBook must sleep normally to preserve battery).

### 4.2 Strongest Differentiator
**"Plug in. Stay awake. Unplug. Sleep normally."**
Unlike *KeepingYouAwake*, *Caffeine*, and *Lungo* (which require manual clicking every time and prevent display sleep by default), and unlike *Amphetamine* (which requires configuring multi-condition Triggers in a complex preferences window), MacPulse delivers **automatic charger-aware system keep-awake + normal display sleep out of the box with zero configuration**.

### 4.3 Weakest Competitive Area
1. **Distribution Trust (`REL-001`):** *Amphetamine* and *Lungo* are signed and notarized via the Mac App Store; *KeepingYouAwake* is Developer ID signed, notarized, and available via `brew install --cask keepingyouawake`. MacPulse is currently ad-hoc signed and blocked by Gatekeeper.
2. **Naming Trademark Exposure (`BRAND-001` — P2):** Apple's trademark guidelines discourage third-party product names starting with `"Mac"`. Competitors use distinct names (*Amphetamine*, *KeepingYouAwake*, *Lungo*, *Caffeinated*).

### 4.4 Features That Should Intentionally NOT Be Added
To preserve MacPulse's speed, tiny footprint (`<300 KB` binary), and zero-configuration clarity, **do not add**:
- Per-application triggers, Wi-Fi SSID triggers, or DNS/VPN watchers (requires background process/network monitoring and permissions).
- Independent display-sleep prevention or mouse-jiggler features (`SCOPE-001`—undermines display longevity and screen-lock security).
- Custom multi-tab SwiftUI Preferences windows (everything fits cleanly in the menu bar and one expandable submenu).
- Cloud sync, telemetry, or auto-update daemons that phone home without user action.
