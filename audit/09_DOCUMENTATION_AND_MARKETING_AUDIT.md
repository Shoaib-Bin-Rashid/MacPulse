# 09 — Documentation, Support, and Marketing Readiness Audit

- **Sector Score:** **2.0 / 5**
- **Confidence:** High
- **Evidence Coverage:** Static Inspection of `README.md`, `PROJECT.md`, `CLAUDE.md`, `AI_TESTING_GUIDE.md`, `TEST_INFRA.md`, `TEST_READY.md`, `docs/BRIEF.md`, `docs/SPEC.md`, `docs/STORIES.md`, `docs/ENGINEERING_REVIEW_01.md`, `MPAboutWindowController.m`, and `Icon/AppIcon.png`
- **Unresolved Findings:** 4 (`SCOPE-001` [P1], `REL-003` [P2], `DOC-001` [P2], `BRAND-001` [P2], `UX-003` [P2])
- **NOT VERIFIED Requirements:** 0

---

## 1. Documentation Accuracy & Contradiction Audit (`DOC-001` — P2)

A cross-check of all 10 Markdown files in the repository against the actual compiled code in `Sources/MacPulseNative/` revealed significant contradictions and inaccuracies:

| Document | Claim in Document | Actual Repository / Code Reality | Severity |
|---|---|---|---|
| `README.md` (lines 76, 82), `PROJECT.md` (line 97), `TEST_INFRA.md`, `TEST_READY.md` | Instructs users to run `./tests/run_e2e_tests.sh` and `./tests/tiers/tier5_adversarial/run_adversarial_tests.sh` (lowercase `tests/`) | Actual directory is named `Tests/` (uppercase `T`). Fails on case-sensitive APFS or Linux filesystems. | **P2 (`DOC-001`)** |
| `AI_TESTING_GUIDE.md` (line 63) | Claims `pmset -g assertions \| grep MacPulse` outputs: `PreventUserIdleSystemSleep "MacPulse Smart Awake (AC Connected)"` | Actual string in `MPPriorityArbiter.m` line 111 is: `"MacPulse: Keeping system awake while charging"`. | **P2 (`DOC-001`)** |
| `README.md` (line 15) vs. `MPAboutWindowController.m` (line 86) | `README.md` says battery safety threshold is configurable from `10% to 50%`. `MPAboutWindowController.m` says `(10%-80%, default 20%)`. | `MPStatusMenuController.m` line 167 offers `10%` through `80%`, while Canonical Scope §3.9 specifies `10%–50%`. | **P2 (`SCOPE-002` / `DOC-001`)** |
| `README.md` (line 14) vs. `MPAboutWindowController.m` (line 82) | `README.md` lists Timed Awake presets as `(30 minutes, 1 hour, 2 hours)` only. | `MPStatusMenuController.m` lines 249–277 offers 7 presets (`15m` to `8h`) plus `Custom Duration...`. | **P2 (`DOC-001`)** |
| `docs/SPEC.md` (line 46) vs. `README.md` (line 16) | `docs/SPEC.md` states: *"MacPulse avoids `kIOPMAssertionTypePreventUserIdleDisplaySleep` so the screen can turn off cleanly on timeout."* `README.md` advertises `"Display Sleep Control: Independent toggle..."`. | Code currently creates `PreventUserIdleDisplaySleep`, which violates Canonical Scope §3.5 (`SCOPE-001`). | **P1 (`SCOPE-001`)** |
| `CLAUDE.md` (lines 1–52) & `AGENTS.md` | Claims MacPulse is a SwiftUI app with a local SwiftData database, `SettingsView.swift`, `Snapshot.swift`, and `Theme.swift`. | Leftover boilerplate from the `new-mac-app` template; completely unrelated to `Sources/MacPulseNative/`. | **P2 (`DOC-001`)** |
| `README.md` (line 95) & `package.json` (line 12) | Declares `MIT License`. | **No `LICENSE` file exists anywhere in the repository (`REL-003`).** | **P2 (`REL-003`)** |

---

## 2. Missing User-Facing & Support Documentation (`DOC-001` — P2)

`README.md` is currently written as an internal engineering summary rather than a user-facing product guide. Before public launch, `README.md` (and the in-app `About & Help...` window) must include:

1. **Clear End-User Installation Steps (After Opening `MacPulse.dmg`):**
   - Drag `MacPulse.app` into the `Applications` folder.
   - Eject the `MacPulse` disk image.
   - Launch `MacPulse` from `/Applications` (or Spotlight / Raycast).
   - Explain that MacPulse is a menu-bar-only app (`LSUIElement`)—look for the lightning bolt icon (`⚡`) in the top-right macOS menu bar rather than the Dock.
   - If distributed before Apple Developer ID notarization is completed (e.g., for internal/beta testers), document the Gatekeeper right-click -> **Open** (or `xattr -d com.apple.quarantine /Applications/MacPulse.app`) workaround honestly.
2. **Honest Statement of macOS Hardware & OS Sleep Limitations (§2, §8, §14):**
   - Explicitly state that MacPulse prevents **automatic idle system sleep** (`PreventUserIdleSystemSleep`), while allowing your display to dim and sleep normally.
   - Explicitly warn users that MacPulse **does not override**:
     - Closing the MacBook lid (clamshell sleep without an external display + power).
     - Choosing **Apple Menu () > Sleep** or **Shut Down** manually.
     - Critical low-battery hardware hibernate (~1–2%) or thermal emergency shutdowns.
3. **Uninstall Instructions:**
   - Open MacPulse in the menu bar -> uncheck **Launch at Login** -> click **Quit MacPulse**.
   - Drag `/Applications/MacPulse.app` to the Trash.
   - Optional clean preference removal: `defaults delete com.shoaib.macpulse`.
4. **Support & Issue Reporting:**
   - Add `.github/ISSUE_TEMPLATE/bug_report.md` prompting users to attach their macOS version, Mac model (MacBook Air/Pro vs. Desktop), and output of `pmset -g assertions | grep -i MacPulse` and `pmset -g ps`.

---

## 3. Branding and Marketing Readiness (§15)

### 3.1 Six-Point User Comprehension Evaluation

| # | Question | Assessment | Findings & Recommendations |
|---:|---|---|---|
| 1 | **What MacPulse does** | **Clear** | Tagline *"Your Mac. Always Ready. Plug in. Stay awake. Unplug. Sleep normally."* communicates the core loop immediately. |
| 2 | **Why they need it** | **Clear** | Prevents interrupted builds, downloads, renders, and SSH sessions while on charger without draining battery when unplugged. |
| 3 | **How it differs from alternatives** | **Needs Sharper Framing in `README.md`** | `README.md` does not currently contrast MacPulse's zero-config automatic AC behavior against manual click toggles (*KeepingYouAwake*, *Caffeine*) or complex trigger setups (*Amphetamine*). |
| 4 | **Whether it is trustworthy** | **Blocked by `REL-001` & `REL-003`** | Lack of Developer ID notarization (triggers macOS malware warning) and missing `LICENSE` file undermine user trust at the moment of installation. |
| 5 | **How much it costs** | **Clear** | Free and open-source (MIT). |
| 6 | **Where to download it** | **Missing Links** | `README.md` has no link to GitHub Releases (` MacPulse.dmg`) or Homebrew installation command. |

### 3.2 Naming & Trademark Risk (`BRAND-001` — P2)
- **Issue:** Apple's *Guidelines for Using Apple Trademarks and Copyrights* state that third-party developers should not incorporate `"Mac"` as part of a product or application name (recommend using `"for Mac"` as a suffix instead, e.g., *"PulseAwake for Mac"* or *"VoltAwake"*).
- **Impact:** While many open-source GitHub utilities use `"Mac..."` names informally, Apple routinely rejects apps prefixed with `"Mac"` during Mac App Store review, and commercial branding carries trademark risk. Flagged for product owner decision before public launch.

### 3.3 Minimum Launch Assets Checklist
Before publishing v1.0.0 on GitHub Releases, the project needs:
- [ ] Clean 1024x1024 `AppIcon.png` / `AppIcon.icns` without embedded `"MacPulse"` text and without bottom-edge white halo artifacts (`UX-003`).
- [ ] Light-mode and Dark-mode high-DPI screenshots of the open MacPulse menu bar dropdown embedded at the top of `README.md`.
- [ ] Root `LICENSE` file (MIT).
- [ ] Signed and notarized `MacPulse-1.0.0.dmg` with `SHA256` checksum on the GitHub Releases page.
