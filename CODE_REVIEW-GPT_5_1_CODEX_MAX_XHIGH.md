# Code Review Report (2025-12-30)

Scope: Full review of the Swift/SwiftUI `lsom` codebase, focusing on code smells, bad practices, and opportunities to use modern Swift.

## Findings (ordered by severity)

### High
- **Thread safety:** HID access runs on ad‑hoc threads (`Thread.detachNewThread`, `Task.detached`, semaphore) and mutates shared caches/subjects concurrently; Combine `PassthroughSubject` sends occur off the main actor, which is undefined. Isolate all HID I/O inside a dedicated `actor` or serial executor and emit state via `AsyncStream` or the main actor.  
  Files: `lsom/Application/lsomApp.swift:218`, `lsom/Infrastructure/LogitechHIDService.swift:351,881,1166,1341`.
- **Refresh pipeline:** `refreshAllData` mixes raw threads with detached tasks and a semaphore; cancellation and ordering are uncontrolled, risking stale or missed updates. Refactor to structured concurrency (`async let` / `TaskGroup`) and drive work from a HID actor.  
  File: `lsom/Application/lsomApp.swift:218`.

### Medium
- **Preview safety:** HID init only checks `XCODE_RUNNING_FOR_PLAYGROUNDS`; SwiftUI Previews set `XCODE_RUNNING_FOR_PREVIEWS`, so previews can still hit IOKit and crash.  
  File: `lsom/Infrastructure/LogitechHIDService.swift:105-108`.
- **Permission hint heuristic:** Treats “battery == nil” as “permission denied,” conflating unsupported features or transient errors; use `LogitechHIDError.isPermissionsRelated` plus connection state instead.  
  Files: `lsom/Presentation/PopoverView.swift:51-67`, `lsom/Domain/BatteryService.swift:32-46`.
- **Logging noise & privacy:** `NSLog`/`print` in release paths (polling, FAP TX/RX) leak device info and add overhead. Use `Logger`/OSLog with privacy annotations and `#if DEBUG` gating.  
  Files: `lsom/Infrastructure/LogitechHIDService.swift:1171,2024`, `lsom/Presentation/SettingsView.swift:146-167`.

### Low
- **State duplication:** Default for `showPercentage` is set in multiple places; prefer `@AppStorage(UserDefaultsKey.showPercentageInMenuBar)` to keep a single source of truth.  
  Files: `lsom/Application/lsomApp.swift:256`, `lsom/Presentation/SettingsView.swift:57`.
- **Unused / stray code:** `hidService` stored in `PopoverViewModel` but unused; stray debug ASCII comment in `deviceState`; repeated “Logitech Mouse” fallback.  
  Files: `lsom/Presentation/PopoverView.swift:15-17`, `lsom/Infrastructure/LogitechHIDService.swift:812-817`, `lsom/Application/lsomApp.swift:247`.
- **Force cast:** Potential crash reading HID properties (`value as! CFNumber`); guard the CF type before casting.  
  File: `lsom/Infrastructure/LogitechHIDService.swift:2470` (approx).

## Modern Swift recommendations
- Wrap HID service in an `actor` (or dedicated serial queue) and expose async APIs; feed callbacks through `AsyncStream` instead of manual callbacks/semaphores.
- Replace manual timers with `Clock`/`sleep(for:)` in structured tasks or `Timer.publish` on main runloop.
- Consider migrating view models to `@Observable` / `@Bindable` (Swift 5.9+) to trim `@Published` boilerplate; use `@AppStorage` for user defaults.
- Keep Combine or swap to `AsyncStream`, but ensure all emissions are serialized (e.g., `@MainActor`).
- Switch logging to `Logger` with privacy redaction and build‑config gating.

## Suggested next steps
1. Introduce a HID actor and refactor `refreshAllData` + settings flows to async/await; remove semaphores and detached threads.  
2. Harden permission handling: surface `LogitechHIDError` to the UI and revise the hint condition.  
3. Modernize logging and clean stray debug artifacts.  
4. Add tests for permission-hint logic and concurrency-safe HID parsing/state mapping.

Notes: Report only; no code changes were made. Tests not run.
