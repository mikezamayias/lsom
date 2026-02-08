# Remaining Work Plan – Architecture, UX Polish, and Testing

## Goals

- Finish the pieces that are still open across Plans 01, 02, and 04.
- Keep everything aligned with macOS best practices, SOLID, and the existing clean architecture layout.
- Focus on changes that directly improve day‑to‑day use and long‑term maintainability.

---

## 1. Application Layer & Composition

- [ ] Introduce a small application layer / container type (e.g. `AppEnvironment`):
  - [ ] Owns shared services (`BatteryService`, `MouseSettingsService`, `PermissionsService`, `LoginItemService`).
  - [ ] Is created once in `LsomApp` and injected into the `AppDelegate` and view models.
- [ ] Optionally add simple use‑case types (`ReadBatteryUseCase`, `ConfigureLoginItemUseCase`) that wrap service calls, so view models depend on use‑cases instead of services directly.

## 2. UI & UX Polish

- [ ] Replace the status‑item SF Symbol with a custom monochrome template icon derived from `icon.svg`:
  - [ ] Export proper template asset(s) into `Assets.xcassets`.
  - [ ] Use it in the status item and ensure it looks good in light/dark mode.
- [ ] Add one or two lightweight device details to the popover (e.g. “USB Receiver” + PID) once they are cheap to obtain from the HID layer.
- [ ] Add an optional “Show percentage in menu bar” toggle in Settings:
  - [ ] When off, status item shows only the icon while the popover remains unchanged.

## 3. Testing & Quality

- [ ] Add `lsomTests` target.
- [ ] Extract pure parsing helpers from `LogitechHIDService` into `Domain/HIDPPParsing.swift` (or similar) and cover them with unit tests:
  - [ ] Unified Battery parsing (the known `0x63` → 99% sample).
  - [ ] Root.GetFeature header/parameter decoding.
- [ ] Add a simple fake `BatteryService` and at least one view‑model test (e.g. `HIDDebugViewModel` mapping `LogitechHIDError` to user‑visible strings).

## 4. Distribution Checklist

- [ ] Write `docs/release-process.md` that documents:
  - [ ] How to archive/sign for “Run locally”.
  - [ ] How to copy `lsom.app` to `~/Applications` and verify HID permissions.
  - [ ] A short checklist from `docs/manual-test-checklist.md` to run before sharing a build.

