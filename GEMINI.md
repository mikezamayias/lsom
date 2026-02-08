# GEMINI.md - Context & Instructions for `lsom`

## Project Overview

**lsom** (Logitech Status on Mac) is a native macOS menu bar application designed to manage and monitor Logitech mice (specifically targeting the G Pro X Superlight and similar devices) using the low-level HID++ protocol.

**Codebase:** ~3,800 lines of Swift across 17 files.

### Key Features
- **Battery Monitoring:** Reads battery percentage directly from the device via HID++ 2.0
- **DPI & Polling Rate Display:** Shows current mouse sensitivity and report rate
- **Menu Bar Integration:** Unobtrusive status item showing battery levels
- **Native UI:** Built with **SwiftUI** and **AppKit** (for menu bar management)
- **Data Caching:** Instant popover display with background refresh
- **Architecture:** Follows **Clean Architecture** principles

## Architecture & Structure

The codebase is organized to separate concerns and facilitate testing:

```
lsom/
├── Application/           # Composition root, AppDelegate, data caching
│   ├── lsomApp.swift      # Entry point, AppDelegate with cached data
│   ├── AppEnvironment.swift
│   └── AutoRefreshInterval.swift
├── Presentation/          # SwiftUI Views and ViewModels (MVVM)
│   ├── PopoverView.swift  # Main popover with battery/DPI/polling display
│   └── SettingsView.swift # Settings window with tabs
├── Domain/                # Protocol definitions and pure logic
│   ├── BatteryService.swift
│   ├── MouseSettingsService.swift
│   ├── HIDPPParsing.swift
│   └── MouseDeviceState.swift
├── Infrastructure/        # IOKit/HID implementations
│   ├── LogitechHIDService.swift  # Core HID++ (~1,800 LOC)
│   ├── HIDLogService.swift
│   └── SystemPermissionsService.swift
└── lsomTests/             # Unit tests
    ├── HIDPPParsingTests.swift
    └── Mocks/
```

**Note:** ViewModels should not import `IOKit` directly - all HID access goes through protocol abstractions.

## Building and Running

The project is a standard Xcode project (`lsom.xcodeproj`).

- **Build & Run:** Open `lsom.xcodeproj` and run the **lsom** scheme (`Cmd+R`)
- **Tests:** Run tests via `Cmd+U`
- **CLI Type-check:**
  ```bash
  xcrun --sdk macosx swiftc -typecheck \
    lsom/Application/*.swift \
    lsom/Presentation/*.swift \
    lsom/Domain/*.swift \
    lsom/Infrastructure/*.swift
  ```

## Development Conventions

- **Language:** Swift 5+
- **UI:** SwiftUI for all views; AppKit only where necessary (Status Bar, Window management)
- **Style:**
  - 4-space indentation
  - Protocol-oriented programming (Dependency Injection via protocols)
  - `@MainActor` for UI-facing components
  - Clean separation: No HID logic in Views/ViewModels
  - UserDefaults keys centralized in `UserDefaultsKey` enum
- **Concurrency:**
  - Regular `Task` for async operations (inherits actor context)
  - Proper cleanup in `deinit` and `applicationWillTerminate`
- **Logging:** Debug logging gated behind `#if DEBUG`

## App Behavior

- **Menu bar only** by default (no Dock icon)
- **Settings window** temporarily shows app in Dock/app switcher
- **Data caching** in AppDelegate for instant popover display
- **Permission hints** shown when Input Monitoring permission is missing

## Documentation

- **`AGENTS.md`**: High-level guidelines and project structure
- **`CLAUDE.md`**: Detailed context for Claude Code
- **`plans/`**: Detailed implementation plans for Architecture, UI/UX, Permissions, and Testing
- **`docs/`**: Manual test checklist and release process
