# Repository Guidelines

This repo contains the `lsom` macOS menu bar app for Logitech mice, written in Swift/SwiftUI with low-level HID++ access.

## Project Structure & Modules

```
lsom/
├── Application/           # App entry point, composition root
│   ├── lsomApp.swift      # Main app, AppDelegate, data caching
│   ├── AppEnvironment.swift
│   └── AutoRefreshInterval.swift
├── Presentation/          # SwiftUI views and ViewModels
│   ├── PopoverView.swift  # Main popover UI
│   └── SettingsView.swift # Settings window
├── Domain/                # Protocols and pure logic
│   ├── BatteryService.swift
│   ├── MouseSettingsService.swift
│   ├── HIDPPParsing.swift
│   └── MouseDeviceState.swift
├── Infrastructure/        # HID++ and system services
│   ├── LogitechHIDService.swift  # Core HID++ implementation (~1,800 LOC)
│   ├── HIDLogService.swift
│   └── SystemPermissionsService.swift
└── lsomTests/             # Unit tests
    ├── HIDPPParsingTests.swift
    └── Mocks/
```

**Total:** ~3,800 lines of Swift across 17 files.

## Target Architecture (Clean Architecture)

- **Presentation** – SwiftUI views + `@MainActor` ViewModels (no IOKit imports, no business logic)
- **Application** – Composition root, AppDelegate, `UserDefaultsKey` constants, data caching
- **Domain** – Service protocols (`BatteryService`, `MouseSettingsService`) and pure parsing helpers
- **Infrastructure** – Concrete implementations using IOKit/HID (`LogitechHIDService`) and system APIs

## Build, Run, and Development

- Open `lsom.xcodeproj` in Xcode and use the **lsom** scheme.
  - `Cmd+R` – run the menu bar app
  - `Cmd+U` – run tests
- From the CLI you can type-check Swift files:
  ```bash
  xcrun --sdk macosx swiftc -typecheck \
    lsom/Application/*.swift \
    lsom/Presentation/*.swift \
    lsom/Domain/*.swift \
    lsom/Infrastructure/*.swift
  ```

## Coding Style & Architecture

- **Language:** Swift 5+, SwiftUI for UI; AppKit only in small adapter types (status item, app lifecycle)
- **Indentation:** 4 spaces, no tabs
- **SOLID principles:**
  - One responsibility per type; ViewModels orchestrate data flow
  - Depend on protocols in Presentation/Application; concrete services in composition root
  - Dependency injection via `init()` (no singletons, no SwiftUI environment DI for services)
- **Concurrency:**
  - `@MainActor` on UI-facing ViewModels and AppDelegate
  - Regular `Task` for async operations (inherits actor context)
  - Proper cleanup in `deinit` and `applicationWillTerminate`
- **Naming:** Descriptive camelCase, `// MARK:` groupings within files
- **Constants:** UserDefaults keys centralized in `UserDefaultsKey` enum

## Testing Guidelines

- Use XCTest, prioritizing tests for pure logic (HID++ parsing, state mapping)
- Name tests by behavior, e.g., `testUnifiedBatteryParsingReturnsPercent()`
- Run tests via Xcode (`Cmd+U`) before large refactors or releases
- Current test coverage: `HIDPPParsingTests` for protocol parsing

## Commit & Pull Request Practices

- Keep commits small and focused; use imperative messages such as `Add UnifiedBattery service`
- For PRs, include:
  - A short summary of changes and which plan documents they implement
  - Screenshots for significant UI updates
  - Notes on any new permissions, entitlements, or behavioral changes
