//
//  HIDTransport.swift
//  lsom
//
//  Low-level HID++ transport protocol for Logitech devices.
//

import Foundation

/// Response from a FAP (Feature Access Protocol) command.
struct FAPResponse {
    let deviceIndex: UInt8
    let featureIndex: UInt8
    let functionIndex: UInt8
    let clientId: UInt8
    let params: [UInt8]
}

/// Response from a RAP (Register Access Protocol) command.
struct RAPResponse {
    let deviceIndex: UInt8
    let subId: UInt8
    let register: UInt8
    let params: [UInt8]
    let isError: Bool
    let errorCode: UInt8?
}

/// Protocol for low-level HID++ transport operations.
/// Implementations handle the actual I/O with the HID device.
protocol HIDTransport: AnyObject {
    /// Send a FAP command and receive a response.
    /// - Parameters:
    ///   - deviceIndex: The device index (1-6 for paired devices)
    ///   - featureIndex: The feature index on the device
    ///   - functionIndex: The function to call
    ///   - params: Parameters for the function (up to 16 bytes)
    /// - Returns: Raw response bytes, or nil if failed/timed out
    func sendFAPCommand(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        functionIndex: UInt8,
        params: [UInt8]
    ) -> [UInt8]?

    /// Look up a feature index by feature ID.
    /// - Parameters:
    ///   - deviceIndex: The device index
    ///   - featureId: The 16-bit feature ID (e.g., 0x2201 for DPI)
    /// - Returns: Tuple of (featureIndex, featureType) or nil if not found
    func getFeatureIndex(
        deviceIndex: UInt8,
        featureId: UInt16
    ) -> (featureIndex: UInt8, featureType: UInt8)?

    /// Find the first active device index that responds to queries.
    /// - Returns: Device index (1-6) or nil if no device found
    func findActiveDeviceIndex() -> UInt8?

    /// Check if the receiver is connected and accessible.
    var isReceiverAvailable: Bool { get }

    /// Clear any cached feature indices.
    func clearFeatureCache()
}

/// HID++ protocol constants used across all controllers.
enum HIDPPConstants {
    // Long report for HID++ FAP (Feature Access Protocol)
    static let longReportId: CFIndex = 0x11
    // Short report for HID++ 1.0 RAP (Register Access Protocol)
    static let shortReportId: CFIndex = 0x10
    // Payload bytes after the report ID
    static let payloadLength: CFIndex = 19
    // Total report size including report ID byte
    static let totalReportLength: CFIndex = 1 + payloadLength
    static let maxParamCount = 16

    // Logitech identifiers
    static let logitechVendorId = 0x046D
    static let unifyingReceiverPid = 0xC547
    static let hidppUsagePage = 0xFF00
    static let hidppUsage = 0x0001

    // Feature IDs
    static let rootFeatureId: UInt16 = 0x0000
    static let featureSetFeatureId: UInt16 = 0x0001
    static let deviceNameFeatureId: UInt16 = 0x0005
    static let unifiedBatteryFeatureId: UInt16 = 0x1004
    static let adjustableDPIFeatureId: UInt16 = 0x2201
    static let reportRateFeatureId: UInt16 = 0x8060
    static let extendedAdjustableReportRateFeatureId: UInt16 = 0x8061
    static let specialKeysButtonsFeatureId: UInt16 = 0x1B04
    static let onboardProfilesFeatureId: UInt16 = 0x8100

    // HID++ 1.0 RAP (register) commands
    static let rapSetRegister: UInt8 = 0x80
    static let rapGetRegister: UInt8 = 0x81
    static let rapSetLongRegister: UInt8 = 0x82
    static let rapGetLongRegister: UInt8 = 0x83

    // HID++ 1.0 error sub-id
    static let rapErrorSubId: UInt8 = 0x8F

    // Registers
    static let rapRegEnableReports: UInt8 = 0x00
    static let rapRegBatteryStatus: UInt8 = 0x07
    static let rapRegBatteryMileage: UInt8 = 0x0D

    // Timing
    static let defaultTimeout: TimeInterval = 0.5
    static let deviceIndexRange: ClosedRange<UInt8> = 1...6
}
