# Permissions & Behavior Plan – TCC, LSUIElement, and Login Item

## Goals

- Ensure the app has the rights it needs to talk to the Logitech receiver reliably, following current macOS privacy best practices.
- Keep the app behaving as a proper menu-bar–only agent (no Dock icon).
- Model permissions and login‑item handling as services so they fit into the overall Clean Architecture layout.
- Provide a clean way for users to let `lsom` start automatically at login.

---

## Plan

### 1. App identity and LSUIElement

- [x] Confirm `Info.plist` / target settings for the main target have:
  - [x] `LSUIElement` set to `1` (true) so the app:
    - [x] Does not appear in the Dock.
    - [x] Does not appear in the Cmd+Tab switcher.
- [x] Ensure the bundle identifier is stable and matches what you want to ship:
  - [x] `"com.mikezamagias.lsom"`.

### 2. TCC permissions (Input Monitoring / Accessibility)

- [x] Ensure `Info.plist` includes a friendly description string for any used privacy keys:
  - [x] `NSInputMonitoringUsageDescription` (shipping today).
  - [ ] `NSAccessibilityUsageDescription` (only if we later use accessibility APIs).
  - [x] Make the description clear:
    - [x] “lsom needs access to input devices to read battery and configure your Logitech mouse.”
- [x] Implement a small `PermissionsService` in the Infrastructure layer and expose it via an `Application`‑level protocol:
  - [x] `func openInputMonitoringSettings()` that:
    - [x] Uses `NSWorkspace.shared.open` with the appropriate URL to System Settings → Privacy & Security → Input Monitoring.
  - [x] Expose a “Fix permissions…” button in:
    - [x] Settings.
    - [x] The error state in the popover when HID I/O is denied.
- [x] Add a tiny one-time onboarding flow:
  - [x] When the first HID call fails with a TCC‑style deny (`kIOReturnNotPrivileged` from `IOHIDDeviceOpen`):
    - [x] Present an explanation in the popover:
      - [x] “lsom needs Input Monitoring permission to read your mouse battery.”
      - [x] “Click ‘Open System Settings’ and enable lsom.”
    - [x] Include the “Open System Settings” button calling the helper above and a “Don’t show again” option persisted in `UserDefaults`.

### 3. Login item / launch at login

- [x] Prefer the modern API: use `SMAppService.mainApp` to register/unregister the main app as a login item on macOS 13+.
- [ ] Only fall back to `SMLoginItemSetEnabled` for older macOS targets if required.
- [ ] Add a login item helper target (`lsomLoginHelper`) if we ever need a separate helper app bundle.
  - [ ] Minimal app that just launches `lsom` and exits.
  - [ ] Add proper `LSBackgroundOnly` or `LSUIElement` settings for the helper as well.
- [x] Implement a small login‑item service and protocol in the Domain/Application layer:
  - [x] `var isEnabled: Bool` – reads login item status.
  - [x] `func setEnabled(_ enabled: Bool)` – toggles via `SMAppService` or no‑op where unavailable.
- [x] Wire this to the Settings “Launch at login” toggle from the UI plan.

### 4. App lifecycle behavior

- [x] Ensure quitting behavior is clear:
  - [x] `Quit` in the popover fully terminates the app (`NSApplication.shared.terminate(nil)`).
- [x] Decide whether the app should:
  - [ ] Retry in the background if the receiver isn’t present (e.g. periodically re-scan).
  - [x] Or only re-scan when:
    - [x] The status item or popover is interacted with.
    - [x] The auto-refresh timer fires on the main app delegate.
- [x] Make sure battery reads and HID interactions happen off the main thread to avoid UI hitching (using `Task.detached` and async hops back to the main actor).

---

## End State

When this plan is completed:

- `lsom` behaves like a proper Mac menu-bar agent: no Dock icon, tidy lifecycle.
- Users are guided through granting Input Monitoring (and future) privileges only when necessary.
- A single “Launch at login” toggle makes starting the app automatic in a standard, OS‑supported way.
