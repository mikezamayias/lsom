# UI / UX Plan – Status Item, Popover, and Settings

## Goals

- Make the menu-bar presentation clear and attractive on macOS using native conventions.
- Present battery information in a friendly, glanceable way using idiomatic SwiftUI MVVM.
- Keep debug tooling available without cluttering the user experience.
- Prepare room in the UI for future configuration features (DPI, buttons, polling rate).

---

## Plan

### 1. Status item visual polish

- [ ] Wrap the status-item logic in a tiny AppKit adapter (`StatusItemController`) so SwiftUI views stay pure.
- [ ] Replace SF Symbol `computermouse` with a custom app icon that:
  - [ ] Uses a mouse silhouette tailored to your Logitech device.
  - [ ] Includes a small battery glyph or “fill” that can be tinted by state (e.g. green / yellow / red).
  - [ ] Export at appropriate sizes for dark/light modes and @2x/@3x.
- [ ] Adjust status item content:
  - [ ] For normal mode:
    - [ ] Icon + numeric `NN%`.
  - [ ] For low battery:
    - [ ] Optionally tint the percentage red, or show a warning dot / exclamation inside the icon.
  - [ ] Show “—” or no text when the receiver is not present.

### 2. Popover layout and content (SwiftUI MVVM)

- [ ] Redesign `DebugMenuView` (or create `MainPopoverView`) as a thin SwiftUI view with a dedicated `@MainActor final` view model:
  - [ ] A “normal” section:
    - [ ] Large battery percentage (e.g. 99%) with label (“Battery”).
    - [ ] Text status (“Good”, “Low”, “Critical”) derived from the percentage.
    - [ ] Device name (“G Pro X Superlight on USB Receiver”).
    - [ ] Last updated timestamp (“Updated just now” / “Updated 2m ago”).
  - [ ] A “controls” row bound to view-model intents:
    - [ ] `Refresh now` button.
    - [ ] `Settings…` button.
    - [ ] `Quit` button.
  - [ ] Move HID debug content into a collapsible section or dedicated Debug view (separate scene or tab):
  - [ ] Only show “Log HID details” (current Log button text and explanation) when:
    - [ ] Running in Debug build, or
    - [ ] A hidden “Enable developer tools” toggle in Settings is on.

### 3. Settings window enhancements

- [ ] Use the native SwiftUI `Settings` scene for macOS, backed by a `SettingsViewModel` that reads/writes user defaults via an injected settings service.
- [ ] Replace the placeholder Settings scene with real sections:
  - [ ] **General**
    - [ ] Checkbox: “Launch at login”.
    - [ ] Checkbox: “Show battery percentage in menu bar”.
    - [ ] Picker: “Auto-refresh interval” with options:
      - [ ] Off, 1 min, 5 min, 15 min.
  - [ ] **Device**
    - [ ] Dropdown list of detected Logitech devices / device indices.
    - [ ] Read-only fields: receiver PID, firmware version (once implemented), last battery value.
  - [ ] **Developer / Debug**
    - [ ] Toggle: “Enable verbose HID logging”.
    - [ ] Button: “Open Console filtered to lsom/hid”.

### 4. Auto-refresh behavior

- [ ] Add a small timer in `AppDelegate` (or a dedicated `BatteryPollingController`) that:
  - [ ] Respects the “Auto-refresh interval” setting.
  - [ ] On each tick:
    - [ ] Calls `LogitechHIDService.batteryPercentage()`.
    - [ ] Updates both:
      - [ ] Status item title.
      - [ ] `lastBatteryPercent` (used by the popover view model).
- [ ] Ensure the timer pauses when:
  - [ ] The app cannot see the receiver (to avoid useless polling).
  - [ ] The system is on battery and a very short interval might be too aggressive (optional optimization).

### 5. Visual feedback for errors

- [ ] Define simple error states in the UI:
  - [ ] “Receiver not found” → show an outline icon and text “Receiver not connected”.
  - [ ] “Permission denied” (if TCC blocks HID) → show “Input Monitoring permission needed” and a button to open System Settings.
  - [ ] “Unknown error” → generic error label plus suggestion to check logs.
- [ ] Map `LogitechHIDError` cases from the architecture plan to these UI states.

---

## End State

When this plan is completed:

- The menu bar shows a clean icon + battery percentage that matches the popover.
- Users see clear status and basic device info at a glance.
- Debug actions and raw HID logging are available but not in the way of everyday use.
- The UI has obvious expansion points for DPI / button / polling‑rate controls once implemented.
