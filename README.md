# MacPulse

> Automatic Awake Utility with Optional Advanced Controls for macOS

MacPulse is a native macOS menu bar keep-awake utility designed for everyday production use. It keeps your Mac awake automatically while connected to power, with optional timed sessions, display sleep controls, and battery safety protection.

Built with native AppKit, Objective-C, and Apple IOKit frameworks, MacPulse uses event-driven hardware power notifications (`IOPSNotificationCreateRunLoopSource`) rather than polling loops, delivering near-zero idle CPU and memory consumption.

---

## Key Features

- **Smart Awake (Automatic)**: Automatically creates a `PreventUserIdleSystemSleep` assertion when AC power / charger is connected, and releases it immediately upon disconnection.
- **Timed Awake**: Quick countdown sessions (15m, 30m, 45m, 1h, 2h, 4h, 8h, or custom duration) backed by a sleep-aware continuous timer (`mach_continuous_time`). Automatically reverts to Smart Awake behavior on timer expiration or user cancellation.
- **Always Awake (with Battery Shield)**: Keeps your Mac awake continuously on both AC and battery power. Automatically disengages if battery level drops to or below a configurable safety cutoff (default 40%, configurable from 10% to 80%).
- **Keep Display On**: Dedicated control to prevent the monitor from sleeping while keep-awake is active (default: OFF so the screen sleeps normally). Automatically pauses if battery drops below the configured safety threshold.
- **Launch at Login**: Native background login registration via `SMAppService.mainApp` with approval detection for macOS System Settings.
- **Universal Binary**: Fully native universal Mach-O binary supporting both Apple Silicon (`arm64`) and Intel (`x86_64`) on macOS 13+.

---

## Power Management Architecture

### System Sleep vs. Display Sleep
- **System Sleep:** When idle, macOS halts the CPU, network interfaces, and background tasks. MacPulse prevents system sleep via IOKit's `PreventUserIdleSystemSleep` assertion so downloads, builds, and scripts complete uninterrupted.
- **Display Sleep:** To prevent OLED/LCD burn-in and conserve energy, macOS dims and sleeps the display independently of system sleep. By default, MacPulse allows displays to sleep normally. Enabling **Keep Display On** asserts `PreventUserIdleDisplaySleep` to keep the screen active (e.g. for presentations or active dashboards).

### Lid-Close Limitation (Clamshell Mode)
Under macOS power and thermal security architecture, closing the lid of a MacBook triggers hardware sleep immediately unless the system is in **Clamshell Mode**. Apple requires:
1. Connection to AC power.
2. Connection to an external display.
3. Connection to an external keyboard and mouse/trackpad.

No third-party user-space application can or should override closed-lid sleep on battery power due to fire safety, ventilation, and hardware protections enforced by Apple silicon SMC.

---

## Priority Arbitration & Lifecycle

MacPulse employs a deterministic priority arbiter to guarantee clean assertion transitions without duplicate leaks:

$$\text{Always Awake (Battery Safe)} \succ \text{Timed Awake (Countdown)} \succ \text{Smart Awake (AC)} \succ \text{Disabled}$$

All IOKit power assertions (`PreventUserIdleSystemSleep`, `PreventUserIdleDisplaySleep`) are tracked via thread-safe `os_unfair_lock` and released cleanly upon application quit or signal interruption.

---

## Building and Installation

### Prerequisites
- macOS 13.0 or later (Ventura, Sonoma, Sequoia)
- Xcode Command Line Tools (`xcrun clang`, `lipo`, `codesign`, `iconutil`)

### Build Targets
Compile the universal binary (`arm64` + `x86_64`) and assemble `build/MacPulse.app`:
```bash
./build.sh
```

To install cleanly to `/Applications/MacPulse.app`:
```bash
./build.sh --install
```

To install and immediately open the application:
```bash
./build.sh --open
```

### Packaging DMG
Generate a distributable disk image (`dist/MacPulse.dmg`) with `/Applications` symlink and UDZO compression format:
```bash
./scripts/package.sh
```

---

## Testing & Quality Assurance

MacPulse includes a multi-tiered verification suite:

### 1. In-App Deterministic Self-Tests (10/10 PASS)
Executes internal subsystem tests using an isolated test store (`com.shoaib.macpulse.tests`), completely protecting user preferences:
```bash
./build/bin/MacPulse --selftest
```

### 2. Automated Regression Suites (Tier 1: 10 suites, 52 test cases)
Runs automated regression tests across all features, boundaries, and teardown lifecycles:
```bash
./Tests/run_e2e_tests.sh --tier 1
```

*Note on Test Classification (QA-002):*
- **14 True E2E Tests:** Execute live compiled binaries and assert kernel power assertions via `pmset -g assertions`.
- **14 Integration Tests:** Exercise defaults persistence, AppKit/Cocoa APIs, and CLI argument parsing.
- **17 Simulated/Mock-Only Tests:** Fast algorithmic simulations validating mathematical edge cases.
- **9 Static/Build Checks:** Verify architectures (`lipo`), packaging, and `Info.plist` metadata.
- **1 Hardware Telemetry Check:** Real-time battery status detection.

### 3. Adversarial & Empirical Stress Suite (Tier 5)
Executes concurrent lock contention tests (5,000 operations across 10 threads), 3,840-state exhaustive matrix validation, hardware notification debounce coalescing, and kernel `pmset` lifecycle verification:
```bash
./Tests/tiers/tier5_adversarial/run_adversarial_tests.sh
```

### 4. Kernel Assertion Leak Inspection
Confirm that zero power assertions remain after quitting MacPulse:
```bash
pmset -g assertions
```

---

## Legal & Trademarks

MacPulse is licensed under the MIT License. Copyright (c) 2026 Shoaib Bin Rashid.  
See [docs/LEGAL.md](docs/LEGAL.md) for complete trademark acknowledgments and compliance policies.
