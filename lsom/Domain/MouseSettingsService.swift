//
//  MouseSettingsService.swift
//  lsom
//
//  Domain‑level protocol and simple models for
//  mouse configuration features (DPI, polling rate,
//  button mappings).
//

import Combine
import Foundation

// MARK: - DPI Types

/// Represents DPI settings for a single sensor.
struct DPISensorInfo: Equatable, Sendable {
    let sensorIndex: Int
    let currentDPI: Int
    let defaultDPI: Int
    /// Supported DPI values. Either a discrete list or values derived from a range.
    let supportedValues: [Int]
}

/// Simplified DPI mode for setting DPI on a sensor.
struct DPIMode: Equatable, Sendable {
    let sensorIndex: Int
    let dpi: Int
}

// MARK: - Polling Rate Types

/// Information about device polling/report rate.
struct PollingRateInfo: Equatable, Sendable {
    let currentHz: Int
    let supportedHz: [Int]
    let supportedMask: UInt16
    let featureId: UInt16
}

// MARK: - Button Mapping Types

/// Flags describing button capabilities.
struct ButtonFlags: OptionSet, Equatable, Sendable {
    let rawValue: UInt16

    /// Button can be reprogrammed to another function.
    static let reprogrammable = ButtonFlags(rawValue: 1 << 0)
    /// Button can be diverted to software (raw events sent to host).
    static let divertable = ButtonFlags(rawValue: 1 << 1)
    /// Button settings persist on device.
    static let persistent = ButtonFlags(rawValue: 1 << 2)
    /// Virtual button (gesture, not physical).
    static let virtual = ButtonFlags(rawValue: 1 << 3)
}

/// Describes a single button/control on the device.
struct ButtonControl: Equatable, Sendable {
    /// Control ID (CID) - unique identifier for this control.
    let controlId: Int
    /// Task ID (TID) - recommended/default handler for this control.
    let taskId: Int
    /// Human-readable name for this control.
    let name: String
    /// Capability flags.
    let flags: ButtonFlags
    /// Group mask indicating which other controls this can be remapped to.
    let groupMask: Int
}

/// Represents current mapping state for a button.
struct ButtonMapping: Equatable, Sendable {
    let control: ButtonControl
    /// The CID this button is currently remapped to, or nil if using default.
    let remappedTo: Int?
    /// Whether raw events are diverted to software.
    let isDiverted: Bool
}

// MARK: - Settings Change Event

/// Event emitted when mouse settings change.
enum MouseSettingsChange: Equatable, Sendable {
    case dpiChanged(Int)
    case pollingRateChanged(Int)
}

// MARK: - Protocol

protocol MouseSettingsService: Sendable {
    /// Publisher that emits true when receiver is connected, false on disconnect.
    var deviceConnectionPublisher: AnyPublisher<Bool, Never> { get }

    /// Publisher that emits when DPI or polling rate settings change.
    var settingsChangePublisher: AnyPublisher<MouseSettingsChange, Never> { get }
    // MARK: DPI (Feature 0x2201)

    /// Returns the number of DPI sensors on the device.
    func dpiSensorCount() async throws -> Int

    /// Returns DPI settings for a specific sensor.
    func dpiSettings(forSensor sensorIndex: Int) async throws -> DPISensorInfo

    /// Sets DPI for a specific sensor.
    func setDPI(_ dpi: Int, forSensor sensorIndex: Int) async throws

    // MARK: Polling Rate (Feature 0x8060 / 0x8061)

    /// Returns current polling rate and supported values.
    func pollingRateInfo() async throws -> PollingRateInfo

    /// Sets the polling rate.
    func setPollingRate(_ rateHz: Int) async throws

    // MARK: Button Mapping (Feature 0x1B04)

    /// Returns all button controls and their current mappings.
    func buttonMappings() async throws -> [ButtonMapping]

    /// Remaps a button to a different function.
    /// Pass `nil` for `targetCID` to reset to default.
    func remapButton(controlId: Int, to targetCID: Int?) async throws

    /// Sets whether a button's events are diverted to software.
    func setButtonDivert(controlId: Int, diverted: Bool) async throws

    // MARK: Device Persistence (Feature 0x8100)

    /// Returns true if the device supports onboard profiles (settings persist on device).
    func supportsOnboardProfiles() async throws -> Bool

    /// Returns whether onboard profiles are enabled (device controls report rate/DPI).
    func onboardProfilesEnabled() async throws -> Bool

    /// Enables or disables onboard profiles.
    func setOnboardProfilesEnabled(_ enabled: Bool) async throws

    // MARK: Device State

    /// Returns a complete snapshot of the mouse device state.
    func deviceState() async -> MouseDeviceState
}
