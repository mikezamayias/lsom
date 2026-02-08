//
//  MouseDeviceState.swift
//  lsom
//
//  Domain model representing the complete state of a connected Logitech mouse.
//  This is a pure value type with no dependencies on infrastructure.
//

import Foundation

/// Complete snapshot of a Logitech mouse's state and capabilities.
struct MouseDeviceState: Equatable, Sendable {
    let deviceName: String
    let batteryPercentage: Int?
    let dpiState: DPIState?
    let pollingRateState: PollingRateState?
    let onboardProfilesState: OnboardProfilesState?
    let buttonMappingState: ButtonMappingState?
    let timestamp: Date

    /// DPI sensor state and capabilities.
    struct DPIState: Equatable, Sendable {
        let isSupported: Bool
        let sensorCount: Int
        let currentDPI: Int
        let defaultDPI: Int
        let supportedValues: [Int]

        var supportedRangeDescription: String {
            guard !supportedValues.isEmpty else { return "none" }
            if supportedValues.count > 10 {
                let min = supportedValues.min() ?? 0
                let max = supportedValues.max() ?? 0
                return "\(supportedValues.count) steps (\(min)–\(max))"
            }
            return supportedValues.map { "\($0)" }.joined(separator: ", ")
        }
    }

    /// Polling rate state and capabilities.
    struct PollingRateState: Equatable, Sendable {
        let isSupported: Bool
        let currentHz: Int
        let supportedHz: [Int]

        var supportedDescription: String {
            supportedHz.map { "\($0)Hz" }.joined(separator: ", ")
        }
    }

    /// Onboard profiles state and capabilities.
    struct OnboardProfilesState: Equatable, Sendable {
        let isSupported: Bool
        let isEnabled: Bool
    }

    /// Button mapping state and capabilities.
    struct ButtonMappingState: Equatable, Sendable {
        let isSupported: Bool
        let buttonCount: Int
        let mappings: [ButtonMapping]
    }
}

// MARK: - CustomStringConvertible

extension MouseDeviceState: CustomStringConvertible {
    var description: String {
        var parts: [String] = []

        parts.append("Device: \(deviceName)")

        if let battery = batteryPercentage {
            parts.append("Battery: \(battery)%")
        }

        if let dpi = dpiState, dpi.isSupported {
            parts.append("DPI: current \(dpi.currentDPI), default \(dpi.defaultDPI), supported \(dpi.supportedRangeDescription)")
        }

        if let polling = pollingRateState, polling.isSupported {
            parts.append("Polling: current \(polling.currentHz)Hz, supported [\(polling.supportedDescription)]")
        }

        if let profiles = onboardProfilesState, profiles.isSupported {
            parts.append("Onboard Profiles: \(profiles.isEnabled ? "enabled" : "disabled")")
        }

        if let buttons = buttonMappingState, buttons.isSupported {
            parts.append("Buttons: \(buttons.buttonCount) controls")
        }

        return parts.joined(separator: " | ")
    }
}

// MARK: - Diagnostic Description

extension MouseDeviceState {
    /// Returns a multi-line diagnostic description suitable for logging.
    var diagnosticDescription: String {
        var lines: [String] = []
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        lines.append("=== Mouse Device State ===")
        lines.append("Timestamp: \(formatter.string(from: timestamp))")
        lines.append("Device: \(deviceName)")

        if let battery = batteryPercentage {
            lines.append("Battery: \(battery)%")
        } else {
            lines.append("Battery: unavailable")
        }

        lines.append("")
        lines.append("--- DPI ---")
        if let dpi = dpiState {
            lines.append("Supported: \(dpi.isSupported)")
            if dpi.isSupported {
                lines.append("Sensors: \(dpi.sensorCount)")
                lines.append("Current: \(dpi.currentDPI)")
                lines.append("Default: \(dpi.defaultDPI)")
                lines.append("Supported values: \(dpi.supportedRangeDescription)")
            }
        } else {
            lines.append("Supported: false")
        }

        lines.append("")
        lines.append("--- Polling Rate ---")
        if let polling = pollingRateState {
            lines.append("Supported: \(polling.isSupported)")
            if polling.isSupported {
                lines.append("Current: \(polling.currentHz)Hz")
                lines.append("Supported: \(polling.supportedDescription)")
            }
        } else {
            lines.append("Supported: false")
        }

        lines.append("")
        lines.append("--- Onboard Profiles ---")
        if let profiles = onboardProfilesState {
            lines.append("Supported: \(profiles.isSupported)")
            if profiles.isSupported {
                lines.append("Enabled: \(profiles.isEnabled)")
            }
        } else {
            lines.append("Supported: false")
        }

        lines.append("")
        lines.append("--- Button Mapping ---")
        if let buttons = buttonMappingState {
            lines.append("Supported: \(buttons.isSupported)")
            if buttons.isSupported {
                lines.append("Button count: \(buttons.buttonCount)")
                for mapping in buttons.mappings {
                    let remap = mapping.remappedTo.map { "-> \($0)" } ?? ""
                    let divert = mapping.isDiverted ? " [diverted]" : ""
                    lines.append("  - \(mapping.control.name) (CID: 0x\(String(format: "%04X", mapping.control.controlId)))\(remap)\(divert)")
                }
            }
        } else {
            lines.append("Supported: false")
        }

        lines.append("==========================")

        return lines.joined(separator: "\n")
    }
}
