# Code Review Report (2025-12-30)

Scope: Full review of Swift/SwiftUI codebase in `lsom/` and `lsomTests/`.

## Findings (ordered by severity)

### High
- HID I/O and shared caches are not serialized; `sendFAPBytes` registers a per-call input callback and mutates shared `receiver`/`cached*` state while multiple tasks call into the service (refresh + settings), and `settingsChangeSubject.send` is invoked off the main thread even though Combine subjects are not thread-safe. This can interleave responses or race with `clearFeatureCache`. Consider isolating all HID I/O behind an `actor` or serial executor and emit state via `AsyncStream` or MainActor. See `lsom/Infrastructure/LogitechHIDService.swift:351`, `lsom/Infrastructure/LogitechHIDService.swift:881`, `lsom/Infrastructure/LogitechHIDService.swift:1166`, `lsom/Infrastructure/LogitechHIDService.swift:1341`, `lsom/Application/lsomApp.swift:218`, `lsom/Presentation/SettingsView.swift:76`.
- `refreshAllData` mixes `Thread.detachNewThread`, `Task.detached`, and a semaphore with shared mutable vars; the detached task can run on a different thread than intended, time out, or read stale data, and cancellation is lost. Prefer structured concurrency (`async let` or `TaskGroup`) and a dedicated HID actor with async APIs. See `lsom/Application/lsomApp.swift:218`.

### Medium
- Preview detection only checks `XCODE_RUNNING_FOR_PLAYGROUNDS`; SwiftUI Previews set `XCODE_RUNNING_FOR_PREVIEWS`, so HID initialization can still run in previews and crash. See `lsom/Infrastructure/LogitechHIDService.swift:105-108`.
- Permission hint logic equates "battery nil" with "permission denied," which also occurs for unsupported features or transient errors; users can get misleading prompts. Use `LogitechHIDError.isPermissionsRelated` plus connection state instead. See `lsom/Presentation/PopoverView.swift:51-67`, `lsom/Domain/BatteryService.swift:32-46`.
- Release logging is noisy (`NSLog` and `print` in UI + HID) and can leak device info or hurt performance. Prefer `Logger` (OSLog) with privacy redaction and `#if DEBUG` gating. See `lsom/Infrastructure/LogitechHIDService.swift:1171`, `lsom/Infrastructure/LogitechHIDService.swift:2024`, `lsom/Presentation/SettingsView.swift:146-167`.

### Low
- Maintainability nits: `AppDelegate` subscribes to `deviceConnectionSubject` directly instead of the publisher, `hidService` is unused in `PopoverViewModel`, a stray debug comment remains in `deviceState`, and `showPercentage` defaults are duplicated. Consider cleanup and modern SwiftUI state (`@AppStorage`, `@Observable`). See `lsom/Application/lsomApp.swift:104-106`, `lsom/Infrastructure/LogitechHIDService.swift:81`, `lsom/Presentation/PopoverView.swift:15-17`, `lsom/Infrastructure/LogitechHIDService.swift:812-817`, `lsom/Application/lsomApp.swift:256`, `lsom/Presentation/SettingsView.swift:57`.

## Open questions
- Do you want all HID access serialized on a single actor/run-loop thread (simplest) or allow parallelism?
- Are you targeting only Unifying receivers or planning Bolt/Bluetooth support (PID matching changes)?

## Suggested next steps
1. Introduce a dedicated HID `actor` or serial executor and convert public HID APIs to `async`, replacing semaphore bridging with `async let` or `TaskGroup`.
2. Replace Combine subjects with `AsyncStream` (or keep Combine but serialize sends on MainActor) and consider migrating view models to `@Observable` and `@Bindable`.
3. Swap `NSLog` and `print` for `Logger` with levels and privacy, gated by build configuration.
4. Add targeted tests for view model behavior using mocks and for extended report-rate parsing/device-state mapping.

## Notes
- No code changes made.
- Tests not run.
