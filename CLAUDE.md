# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**lsom** (Logitech Status on Mac) is a native macOS menu bar application that monitors Logitech mouse battery levels, DPI, and polling rate using the HID++ 2.0 protocol. It's a menu bar-only app (no Dock icon by default) targeting macOS 13.0+.

**Codebase size:** ~3,800 lines of Swift across 17 files.

## Build & Run

```bash
# Type-check from CLI (useful for quick validation)
xcrun --sdk macosx swiftc -typecheck \
  lsom/Application/*.swift \
  lsom/Presentation/*.swift \
  lsom/Domain/*.swift \
  lsom/Infrastructure/*.swift

# Build from CLI
xcodebuild build -project lsom.xcodeproj -scheme lsom -configuration Debug -destination 'platform=macOS'

# Build & run: Open lsom.xcodeproj in Xcode, use Cmd+R
# Tests: Cmd+U
```

## CI/CD — Xcode Cloud

All CI/CD runs on **Xcode Cloud** (not GitHub Actions). GitHub Actions workflows have been
archived to `.github/workflows.archived/`.

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| **Build** | Push to any branch | Build (Debug) + SwiftLint |
| **Test** | Push to any branch | Run unit tests |
| **Release** | Tag `v*.*.*` | Archive → Sign → Notarize → Distribute |

**Custom CI scripts** live in `ci_scripts/` (the only repo-level Xcode Cloud config):
- `ci_post_clone.sh` — installs SwiftLint
- `ci_pre_xcodebuild.sh` — runs linting
- `ci_post_xcodebuild.sh` — logs archive info

**Code signing & notarization** are automatic via Xcode Cloud (Apple Developer team `DW97QZ7F3B`).

### Creating a Release

```bash
# 1. Update version in Xcode target settings
# 2. Update docs/CHANGELOG.md
# 3. Tag and push:
git tag v1.0.0
git push origin v1.0.0
```

See [`docs/XCODE_CLOUD_SETUP.md`](docs/XCODE_CLOUD_SETUP.md) for full setup instructions.

## Architecture

The project follows Clean Architecture with 4 layers:

```
Presentation → Application → Domain ← Infrastructure
```

| Layer | Location | Purpose |
|-------|----------|---------|
| **Presentation** | `lsom/Presentation/` | SwiftUI views + `@MainActor` ViewModels. No IOKit imports. |
| **Application** | `lsom/Application/` | Composition root (`lsomApp.swift`), AppDelegate, `UserDefaultsKey` constants, data caching |
| **Domain** | `lsom/Domain/` | Protocols (`BatteryService`, `MouseSettingsService`) and pure parsing helpers |
| **Infrastructure** | `lsom/Infrastructure/` | Concrete HID++ implementation (`LogitechHIDService`), system services |

**Key architectural rules:**
- Presentation layer must NOT import IOKit - all HID access goes through protocol abstractions
- ViewModels receive dependencies via `init()` (no singletons, no SwiftUI environment DI for services)
- AppDelegate caches data (battery, DPI, polling rate) for instant popover display
- Regular `Task` for async operations (inherits `@MainActor` context from AppDelegate)
- Proper cleanup in `deinit` (timers) and `applicationWillTerminate` (observers)

## Key Files

| File | LOC | Purpose |
|------|-----|---------|
| `Infrastructure/LogitechHIDService.swift` | ~1,800 | Core HID++ 2.0 FAP implementation |
| `Presentation/SettingsView.swift` | ~450 | Settings window with tabs |
| `Presentation/PopoverView.swift` | ~350 | Main popover UI |
| `Application/lsomApp.swift` | ~260 | Entry point, AppDelegate, data caching |
| `Domain/HIDPPParsing.swift` | ~220 | Pure parsing functions (unit-testable) |

## HID++ Protocol Details

The app communicates with Logitech Unifying Receiver (VID `0x046D`, PID `0xC547`) using:
- **Long reports** (0x11 header, 20-byte payloads)
- **FAP (Feature Access Protocol)** for feature discovery and commands
- **Unified Battery feature** (0x1004) probed on device indices 1-6
- Synchronous wait-loop with 2-second timeout per request
- Callback unregistration to prevent dangling pointers

## Code Style

- **Indentation:** 4 spaces
- **Concurrency:** `@MainActor` on UI-facing ViewModels and AppDelegate; regular `Task` for async work
- **Constants:** UserDefaults keys in `UserDefaultsKey` enum (centralized)
- **Naming:** Descriptive camelCase, `// MARK:` groupings within files
- **Debug logging:** Gated with `#if DEBUG`, ISO-8601 timestamps for HID traces

## Testing

Tests are in `lsomTests/`:
- `HIDPPParsingTests.swift` - Pure parsing functions with known byte sequences
- `Mocks/` - Mock services for unit testing

Run with `Cmd+U` in Xcode.

## Known Limitations

- Only supports Unifying Receiver (PID `0xC547`), single device at a time
- DPI/polling configuration: read-only display (writing implemented but UI is view-only)
- Button remapping: protocol defined but not exposed in UI
- Custom menu bar icon not yet created (uses SF Symbol `computermouse`)

## Permissions

The app requires **Input Monitoring** permission (TCC) for `IOHIDDeviceOpen`. Errors surface via `LogitechHIDError.isPermissionsRelated` and trigger user-facing hints in the popover UI when battery data is unavailable.

## App Behavior

- **Menu bar only** by default (no Dock icon)
- **Settings window** causes app to appear in Dock/app switcher temporarily
- **Data caching** in AppDelegate for instant popover display
- **Auto-refresh** configurable (off, 1min, 5min, 15min)

## Product & GTM

These analyses inform feature prioritization, pricing, and launch sequencing for lsom:

| Document | Path | Purpose |
|----------|------|---------|
| **Product Requirements** | [`docs/lsom_PRD.md`](docs/lsom_PRD.md) | Feature specs, user stories, acceptance criteria |
| **Distribution Roadmap** | [`docs/lsom_DISTRIBUTION_ROADMAP.md`](docs/lsom_DISTRIBUTION_ROADMAP.md) | Go-to-market channels and launch strategy |
| **Monetization** | [`docs/lsom_MONETIZATION.md`](docs/lsom_MONETIZATION.md) | Pricing model, unit economics, revenue targets |
| **Tech Lead Review** | [`TECH_LEAD_REVIEW.md`](TECH_LEAD_REVIEW.md) | Implementation standards and code quality gates |
| **Best Practices** | [`BEST_PRACTICES.md`](BEST_PRACTICES.md) | Swift/macOS platform standards and conventions |

## Documentation

- `plans/` - Design documents covering architecture, UI/UX, permissions, testing
- `docs/` - Manual test checklist and release process
- `docs/XCODE_CLOUD_SETUP.md` - Xcode Cloud CI/CD configuration and setup guide
- `ci_scripts/` - Custom CI scripts for Xcode Cloud
