# lsom

**Logitech Status on Mac** — A native macOS menu bar app that monitors your Logitech mouse battery level, DPI, and polling rate.

![macOS 13.0+](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

## CI/CD Status

[![Build & Test](https://github.com/mikezamayias/lsom/actions/workflows/build.yml/badge.svg)](https://github.com/mikezamayias/lsom/actions/workflows/build.yml)
[![Lint & Test](https://github.com/mikezamayias/lsom/actions/workflows/lint.yml/badge.svg)](https://github.com/mikezamayias/lsom/actions/workflows/lint.yml)
[![Release](https://github.com/mikezamayias/lsom/actions/workflows/release.yml/badge.svg)](https://github.com/mikezamayias/lsom/actions/workflows/release.yml)

## Features

- **Menu bar battery display** — See your mouse battery percentage at a glance
- **DPI & polling rate** — View current sensitivity and report rate in the popover
- **Auto-refresh** — Configurable polling intervals (1, 5, or 15 minutes)
- **Native macOS experience** — Pure SwiftUI, no Electron, minimal resource usage (~3,800 lines of Swift)
- **Privacy-focused** — No network access, no telemetry, just HID communication

## Supported Devices

Currently supports Logitech mice connected via **Unifying Receiver** (USB dongle with product ID `0xC547`).

Tested with:
- Logitech G Pro X Superlight

Other Logitech mice using the Unifying receiver with HID++ 2.0 should also work.

## Requirements

- macOS 13.0 (Ventura) or later
- Logitech Unifying Receiver
- **Input Monitoring** permission (required to read HID data)

## Installation

### From Source

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/lsom.git
   cd lsom
   ```

2. Open in Xcode:
   ```bash
   open lsom.xcodeproj
   ```

3. Build and run (`Cmd+R`)

4. Grant Input Monitoring permission when prompted:
   - System Settings → Privacy & Security → Input Monitoring → Enable **lsom**

## Usage

Once running, lsom appears as a mouse icon in your menu bar showing the current battery percentage.

**Click the icon** to open the popover with:
- Battery percentage with circular progress indicator
- Connection status
- Current DPI setting
- Current polling rate
- Last updated timestamp
- Settings access
- Quit option

**Settings** (via menu bar → Settings, or click Settings button):
- Launch at login
- Show/hide percentage in menu bar
- Mouse settings (DPI, polling rate)
- Device information
- About

Note: When the Settings window is open, lsom appears in the Dock and app switcher for easy access.

## Architecture

lsom follows **Clean Architecture** with clear separation:

```
lsom/
├── Application/     # App entry point, composition root, UserDefaults keys
├── Presentation/    # SwiftUI views and ViewModels
├── Domain/          # Protocols and pure parsing logic
└── Infrastructure/  # HID++ implementation, system services
```

The HID++ 2.0 protocol implementation communicates directly with the Logitech receiver using IOKit, with no third-party dependencies.

## Building

```bash
# Type-check from command line
xcrun --sdk macosx swiftc -typecheck \
  lsom/Application/*.swift \
  lsom/Presentation/*.swift \
  lsom/Domain/*.swift \
  lsom/Infrastructure/*.swift

# Build in Xcode
open lsom.xcodeproj
# Press Cmd+R
```

## Testing

```bash
# Run unit tests in Xcode
# Cmd+U
```

Tests cover:
- HID++ response parsing (`HIDPPParsingTests`)
- Known byte sequence validation

## Troubleshooting

### "Receiver not connected"
- Ensure the Logitech Unifying Receiver is plugged in
- Try a different USB port
- Check if the mouse is paired with the receiver

### "Input Monitoring permission needed"
- Open System Settings → Privacy & Security → Input Monitoring
- Enable lsom in the list
- If lsom doesn't appear, try removing and re-adding it

### Battery not updating
- Click the popover to trigger a refresh
- Check that auto-refresh is enabled in Settings
- Some mice only report battery when actively used

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Follow the existing code style (4-space indentation, Clean Architecture patterns)
4. Submit a pull request

## License

MIT License — see [LICENSE](LICENSE) for details.

## Acknowledgments

- [Logitech HID++ 2.0 specification](https://lekensteyn.nl/files/logitech/logitech_hidpp_2.0_specification_draft_2012-06-04.pdf) for protocol documentation
- The reverse engineering community for HID++ insights
# Test build trigger
