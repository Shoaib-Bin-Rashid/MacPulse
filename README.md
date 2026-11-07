# MacPulse

> Automatic Awake Utility with Optional Advanced Controls for macOS

MacPulse is a native macOS menu bar utility designed for everyday production use. It keeps your Mac awake automatically while connected to power, with optional timed sessions and advanced battery-protected keep-awake modes.

Built with native AppKit, Objective-C, and IOKit frameworks, MacPulse uses event-driven hardware notifications (`IOPSNotificationCreateRunLoopSource`) rather than polling loops, delivering near-zero idle CPU and memory consumption.

---

## Key Features

- **Smart Awake (Automatic)**: Automatically asserts `PreventUserIdleSystemSleep` when AC power / charger is connected, and releases it immediately upon disconnection.
- **Timed Awake**: Quick preset sessions (30 minutes, 1 hour, 2 hours) with a live countdown display in the menu. Automatically reverts to Smart Awake behavior on timer expiration or user cancellation.
- **Always Awake (with Battery Protection)**: Keeps your Mac awake on both AC and battery power. Automatically releases and disables if battery drops below a configurable safety cutoff (default 20%, configurable from 10% to 50%).
- **Display Sleep Control**: Independent toggle to allow or prevent display sleep while system sleep is prevented.
- **Launch at Login**: Native background login registration via `SMAppService.mainApp`.
- **Event-Driven Telemetry**: Dynamic menu bar status item displaying live power source (AC/Battery, percentage) and active state (active, inactive, Always Awake) without timer polling.
- **Universal Binary**: Fully native fat binary supporting both Apple Silicon (`arm64`) and Intel (`x86_64`) architectures on macOS 13+.

---

## Priority Arbitration & Lifecycle

MacPulse employs a deterministic priority arbiter to guarantee clean assertion transitions without duplicate leaks:

$$\text{Always Awake (Battery Safe)} \succ \text{Timed Awake (Countdown)} \succ \text{Smart Awake (AC)} \succ \text{Disabled}$$

All IOKit power assertions (`PreventUserIdleSystemSleep`, `PreventUserIdleDisplaySleep`) are tracked via thread-safe `os_unfair_lock` and released cleanly upon application quit or signal interruption.

---

## Building and Packaging

### Prerequisites
- macOS 13.0 or later
- Xcode Command Line Tools (`xcrun clang`, `lipo`, `codesign`, `hdiutil`)
- Optional: Bun or Node.js

### Universal Build
Compile the native universal binary (`arm64` + `x86_64`) and assemble the application bundle at `build/MacPulse.app` and `~/Applications/MacPulse.app`:
```bash
./build.sh
```

To build and immediately launch the updated app:
```bash
./build.sh --open
```

### Packaging DMG
Generate a distributable compressed disk image (`dist/MacPulse.dmg`) with `/Applications` symlink and UDZO compression format:
```bash
./scripts/package.sh
```
Or with Bun:
```bash
bun run package
```

---

## Testing & Quality Assurance

MacPulse includes a multi-tiered verification suite:

### 1. Headless Self-Tests (10/10 checks)
Verifies core subsystems against an isolated temporary store:
```bash
./tools/selftest.sh
```

### 2. Comprehensive E2E Automated Suite (17 suites, 98 test cases)
Runs automated end-to-end regression tests across all features, boundaries, combinations, and user scenarios:
```bash
./tests/run_e2e_tests.sh
```

### 3. Adversarial & Empirical Stress Suite (Tier 5)
Executes concurrent lock contention tests (5,000 operations across 10 threads), 3,840-state exhaustive matrix validation, hardware notification debounce coalescing, and kernel `pmset` lifecycle verification:
```bash
./tests/tiers/tier5_adversarial/run_adversarial_tests.sh
```

### 4. Kernel Assertion Leak Inspection
Confirm that zero power assertions remain after terminating MacPulse:
```bash
pmset -g assertions
```

---

## License

MIT License. Copyright (c) 2026 Shoaib.
