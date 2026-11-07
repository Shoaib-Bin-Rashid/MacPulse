# MacPulse — User Stories & Acceptance Criteria

## Milestone 1: Core Foundation & Power Monitoring
### Story 1.1: Zero-Polling AC Power Detection
- **As a** user,
- **I want** the app to detect when I plug in or unplug my charger instantly,
- **So that** it responds without wasting battery on continuous background polling.
- **Acceptance Criteria**:
  - [ ] Registers `IOPSNotificationCreateRunLoopSource` on application run loop.
  - [ ] Updates internal `PowerState.isACConnected` immediately on AC cable connect/disconnect.
  - [ ] Reads battery percentage accurately if present.

### Story 1.2: System Idle Sleep Assertion
- **As a** user,
- **I want** my Mac to stay awake while charging so long downloads and tasks finish,
- **So that** I don't have to keep moving my mouse.
- **Acceptance Criteria**:
  - [ ] Calls `IOPMAssertionCreateWithName` with `kIOPMAssertionTypePreventUserIdleSystemSleep`.
  - [ ] Verifies via `pmset -g assertions` that assertion is active and owned by `MacPulse`.
  - [ ] Allows display sleep independently (does not prevent display sleep).
  - [ ] Releases assertion immediately when AC power is disconnected.

## Milestone 2: User Interface & Menu Bar Extra
### Story 2.1: Native Menu Bar Item
- **As a** user,
- **I want** a clean icon in the top menu bar showing current status,
- **So that** I can see if MacPulse is active at a glance.
- **Acceptance Criteria**:
  - [ ] Displays `bolt.fill` when AC power is connected and awake assertion is active.
  - [ ] Displays `bolt.slash` or dim symbol when on battery / idle sleep enabled.
  - [ ] Clicking the icon reveals a native macOS menu with live status and toggles.

### Story 2.2: User Preferences & Toggles
- **As a** user,
- **I want** controls to toggle "Keep Awake While Charging" and "Always Awake",
- **So that** I can customize sleep behavior on demand.
- **Acceptance Criteria**:
  - [ ] "Keep Awake While Charging" toggle (persisted in UserDefaults, default ON).
  - [ ] "Always Awake" toggle (persisted, default OFF).
  - [ ] "Allow Display Sleep" toggle (default ON).
  - [ ] State display line: "Power Source: AC Power / Battery".
  - [ ] State display line: "System Status: Awake / Normal Sleep Behaviour".

## Milestone 3: System Integration & Lifecycle Safety
### Story 3.1: Launch at Login
- **As a** user,
- **I want** MacPulse to start automatically when my Mac starts up,
- **So that** I never forget to enable it.
- **Acceptance Criteria**:
  - [ ] Toggle "Launch at Login" calls `SMAppService.mainApp.register()` / `.unregister()`.
  - [ ] Reflects current login item registration status accurately.

### Story 3.2: Clean Shutdown Assertion Release
- **As a** user,
- **I want** all assertions cleanly released when I quit the app,
- **So that** my Mac returns to default sleep behavior immediately.
- **Acceptance Criteria**:
  - [ ] `applicationWillTerminate` calls `releaseAllAssertions()`.
  - [ ] `pmset -g assertions` confirms zero dangling assertions after quitting.
