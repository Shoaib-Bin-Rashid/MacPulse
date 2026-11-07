# MacPulse — Technical Specification

## Overview
MacPulse is a zero-polling, native macOS menu bar application designed to prevent idle system sleep exclusively when connected to AC power, while allowing the screen to turn off independently.

## Architecture

```text
[Hardware AC Event]
       |
       v
[IOPSNotificationCreateRunLoopSource] -> [PowerSourceMonitor]
                                                |
                                                v
                                        [PowerManager]
                                                |
                        +-----------------------+-----------------------+
                        | (AC Connected & KeepAwake)                    | (Battery or Disabled)
                        v                                               v
            [IOPMAssertionCreateWithName]                     [IOPMAssertionRelease]
            Type: PreventUserIdleSystemSleep                  Status: Normal Sleep
                        |                                               |
                        +-----------------------+-----------------------+
                                                |
                                                v
                                     [MenuBarController]
                                     Icon: bolt.fill / bolt.slash
                                     Status: "Awake (Charging)" / "Normal Sleep"
```

## How It Works

### 1. Power Source Detection (Zero-Polling)
Continuous `while true` or `Timer` loops waste CPU cycles and battery. MacPulse utilizes `IOPSNotificationCreateRunLoopSource`:
```swift
let runLoopSource = IOPSNotificationCreateRunLoopSource({ context in
    let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(context!).takeUnretainedValue()
    monitor.powerSourceChanged()
}, Unmanaged.passUnretained(self).toOpaque()).takeRetainedValue()

CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
```
Whenever the charger is connected or disconnected, the kernel signals the run loop source, triggering an immediate state update.

### 2. Sleep Prevention Assertion
MacPulse avoids `kIOPMAssertionTypePreventUserIdleDisplaySleep` so the screen can turn off cleanly on timeout.
It exclusively asserts:
```swift
kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
```
Using `IOPMAssertionCreateWithName`:
- Name: `"com.shoaib.macpulse.charging-awake"`
- Details: `"MacPulse: Keeping system awake while AC adapter is connected"`
Assertions are deduplicated: if an assertion ID is currently held, another is never created.

### 3. Assertion Release Invariants
An assertion is released immediately when:
1. AC power is disconnected (unless `alwaysAwake` is explicitly enabled).
2. The user toggles "Keep Awake While Charging" to OFF.
3. The application terminates (`applicationWillTerminate`).

### 4. Launch at Login
Integrated via macOS `ServiceManagement`:
```swift
SMAppService.mainApp.register() // or .unregister()
```

## Gotchas & Edge Cases
1. **Lid Close (Clamshell Mode)**: Closing the MacBook lid when an external display is not connected puts the Mac into clamshell sleep by hardware design unless closed-display sleep assertion overrides exist. MacPulse targets system idle sleep when the lid is open or external displays are attached.
2. **Assertion Leaks**: If the app crashes or abruptly exits, the macOS kernel automatically reaps power assertions associated with the terminating process PID.
3. **Menu Bar Only (`LSUIElement`)**: The Info.plist must declare `LSUIElement = true` so no Dock icon or standard application window appears on launch.
