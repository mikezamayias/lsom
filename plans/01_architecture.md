# Architecture Plan – Core HID Services and Structure

## Goals

- Apply macOS best practices (AppKit + SwiftUI) using SOLID and Clean Architecture.
- Structure the project into clear layers and folders suitable for a long‑lived SwiftUI app.
- Centralize all low-level HID logic in a focused service layer.
- Maintain a single `IOHIDManager` and receiver `IOHIDDevice` instance while the app runs.
- Provide a clean, high-level API for battery readings (and later DPI / button config).
- Gate heavy logging and legacy RAP code behind debug flags.
- Improve error handling and error surfacing to the UI.

---

## Plan

### 1. Define clear layers, folders, and service protocols

- [ ] Adopt a Clean Architecture layout, reflected in source folders under `lsom/`:
  - [ ] `Presentation/` – SwiftUI views and `ObservableObject` view models (no IOHID imports).
  - [ ] `Application/` – coordinators, use‑case types (e.g. `ReadBatteryUseCase`), and high‑level interfaces.
  - [ ] `Domain/` – simple models/value types (`BatteryStatus`, `MouseDevice`).
  - [ ] `Infrastructure/` – concrete HID++ and system services (`LogitechHIDService`, login item, permissions).
- [ ] Keep all boundaries protocol‑first (OOP + SOLID):
  - [ ] View models depend only on `Application` protocols.
  - [ ] Application layer depends only on `Domain` and service protocols.
  - [ ] Infrastructure implements those protocols and is wired up in a small composition root.
- [ ] Add `lsom/Infrastructure/LogitechHIDService.swift` (or similar) in the app target.
- [ ] Define a `protocol BatteryService { func batteryPercentage() throws -> Int }` in the domain layer.
- [ ] Implement `@MainActor final class LogitechHIDService: BatteryService` with:
  - [ ] A singleton or shared instance created in the composition root (DI‑friendly, but not globally accessed).
  - [ ] Internal properties:
    - [ ] `private let manager: IOHIDManager`
    - [ ] `private var receiver: IOHIDDevice?`
    - [ ] State for last-discovered `unifiedBatteryFeatureIndex`, last-used `deviceIndex`, etc.
- [ ] Move the FAP helpers (`HIDFAPWaiter`, `sendFAPBytes`, `rootGetFeatureIndexFAP`, `unifiedBatteryGetStatusFAP`) out of `HIDDebugService` into this class.
- [ ] Keep public surface narrow, e.g.:
  - [ ] `func batteryPercentage() throws -> Int`
  - [ ] `func refreshReceiverIfNeeded()`

### 2. Maintain a single IOHIDManager / device

- [ ] Initialize `IOHIDManagerCreate` once in `LogitechHIDService.init`.
- [ ] Apply the receiver matching dictionary (`vendorID`, `productID`, `usagePage`, `usage`) and open the manager once.
- [ ] Implement `private func ensureReceiverOpen() -> IOHIDDevice?` that:
  - [ ] Returns cached `receiver` if still valid.
  - [ ] Otherwise:
    - [ ] Re-scans `IOHIDManagerCopyDevices`,
    - [ ] Finds the HID++ interface for the Logitech receiver,
    - [ ] Opens it, caches it, and returns it.
- [ ] Ensure device closure only happens on app shutdown / deinit, not per read.

### 3. Inject services into presentation layer

- [ ] Introduce a small “composition root” (`AppContainer` or similar) created in `lsomApp.swift`:
  - [ ] Owns a single instance of `LogitechHIDService` (and future services).
  - [ ] Exposes protocol‑typed properties (`var batteryService: BatteryService`).
- [ ] In `AppDelegate`, depend on `BatteryService` rather than a concrete type:
  - [ ] Store `private let batteryService: BatteryService` injected from the container.
- [ ] In `HIDDebugViewModel`, accept a `BatteryService` (and any other services) in the initializer instead of instantiating a service internally.
- [ ] Keep `HIDDebugService` only as a *debug UI* façade that delegates to `BatteryService` / `LogitechHIDService`.

### 4. Gate debug logging & RAP code

- [ ] Introduce a compile-time flag (e.g. `LOGITECH_HID_DEBUG`) or use `#if DEBUG` blocks inside `LogitechHIDService`.
- [ ] Wrap verbose `print("lsom/hid: ...")` statements so:
  - [ ] In Debug builds: full logging shown.
  - [ ] In Release builds: only high-level errors are logged (or none).
- [ ] Move HID++ 1.0 RAP helpers into a dedicated extension:
  - [ ] `extension LogitechHIDService { /* RAP helpers */ }`
  - [ ] Guard them with `#if DEBUG` so they don’t ship in release builds unless you explicitly want them.

### 5. Improve error handling and surfacing

- [ ] Define a small `enum LogitechHIDError: Error` with cases like:
  - [ ] `.receiverNotFound`
  - [ ] `.deviceOpenFailed`
  - [ ] `.featureNotFound(featureId: UInt16)`
  - [ ] `.timeout`
  - [ ] `.ioError(code: IOReturn)`
- [ ] Change the battery API to a failable result:
  - [ ] `func batteryPercentage() throws -> Int`
  - [ ] Or Swift-conventional: `func batteryPercentage() -> Result<Int, LogitechHIDError>`
- [ ] Update `AppDelegate.refreshBatteryInStatusItem()` and `HIDDebugViewModel.refreshBattery()` to:
  - [ ] Distinguish “no receiver” vs. “timeout” vs. “other I/O error” and map to:
    - [ ] User-visible strings in the debug UI (e.g. “Receiver not found”, “Timed out talking to receiver”).

### 6. Prepare hooks for future settings (DPI, buttons)

- [ ] In `LogitechHIDService`, define **placeholder** APIs for future features:
  - [ ] `func dpiSettings() throws -> DPIMode` / `func setDPI(_:)`
  - [ ] `func pollingRate() -> Int` / `func setPollingRate(_:)`
  - [ ] `func buttonMapping() -> [ButtonMapping]` / `func updateButtonMapping(_:)`
- [ ] Internally, keep “feature index discovery” generic so it can be reused:
  - [ ] `func featureIndex(for featureId: UInt16, deviceIndex: UInt8) -> UInt8?`

---

## End State

When this plan is completed:

- All HID traffic (FAP, and RAP when enabled) flows through a single `LogitechHIDService` behind SOLID, protocol‑driven boundaries.
- The menu bar app uses a small, stable `BatteryService` API rather than scattered IOHID calls.
- Debug builds retain deep logging and RAP tools; release builds are quiet and lightweight.
- The architecture follows macOS best practices and is ready for DPI / button configuration features without structural changes.
