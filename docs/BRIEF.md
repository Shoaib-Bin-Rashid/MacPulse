# MacPulse

Your Mac. Always Ready.

Lightweight native macOS menu bar utility that prevents system idle sleep while connected to AC power, while independently allowing the display to sleep.

## Replaces
Amphetamine, Caffeine, KeepingYouAwake, manual `caffeinate` terminal commands.

## Main jobs
1. Automatically detect when AC power adapter is connected or disconnected without polling.
2. Prevent system idle sleep while charging using native IOKit assertions (`kIOPMAssertionTypePreventUserIdleSystemSleep`).
3. Allow the display to sleep independently to conserve display life and maintain privacy.
4. Provide immediate menu bar toggles for "Keep Awake While Charging", "Always Awake", "Allow Display Sleep", and "Launch at Login".

## Data
- Settings: `keepAwakeWhileCharging: Bool`, `alwaysAwake: Bool`, `allowDisplaySleep: Bool`, `launchAtLogin: Bool`.
- PowerState: `isACConnected: Bool`, `batteryPercent: Int?`, `isAssertionActive: Bool`.

## Shape
Menu bar extra (`LSUIElement = true`), no Dock icon, macOS 13 or later. Local data only. Zero network requests. Zero tracking.

## System hooks
- Menu bar item (`NSStatusItem` / `MenuBarExtra`) with dynamic state icon.
- IOKit Power Management (`IOPMAssertionCreateWithName`, `IOPMAssertionRelease`).
- IOPowerSources notification loop (`IOPSNotificationCreateRunLoopSource`).
- ServiceManagement Login Item (`SMAppService.mainApp`).

## Reference
Amphetamine (simplified down to automatic power-state detection without complex triggers).

## Look
Native macOS menu bar item using SF Symbols (`bolt.fill`, `bolt.slash`, `powersleep`), clean system menu with native controls, zero unnecessary animations.

## Not in version one
- Complex application-based triggers (e.g. keep awake when Xcode is open).
- Network SSID-based triggers.
- Cloud sync or external accounts.
