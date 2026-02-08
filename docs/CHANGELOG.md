# Changelog

All notable changes to **lsom** (Logitech Status on Mac) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_Nothing yet._

## [1.0.0] - 2025-XX-XX

### Added
- Native macOS menu bar app for Logitech mouse monitoring
- Real-time battery level display in the menu bar
- DPI and polling rate readout in popover
- Auto-refresh with configurable polling intervals (1, 5, or 15 minutes)
- Support for Logitech Unifying Receiver (USB product ID `0xC547`)
- HID++ 2.0 protocol implementation for device communication
- Input Monitoring permission handling with guided setup
- Launch at Login support
- Pure SwiftUI interface with minimal resource usage
- Tested with Logitech G Pro X Superlight

### Technical
- ~3,800 lines of Swift
- macOS 13.0+ (Ventura) minimum deployment target
- Swift 5.9
- No network access, no telemetry — privacy by design

---

_To create a new release, see [docs/release-process.md](release-process.md)._
