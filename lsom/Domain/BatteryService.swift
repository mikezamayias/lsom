//
//  BatteryService.swift
//  lsom
//
//  Defines the high–level protocol used by the
//  presentation layer to obtain mouse battery state.
//

import Foundation

protocol BatteryService: Sendable {
    /// Returns the current mouse battery percentage (0–100).
    func batteryPercentage() throws -> Int
}

enum LogitechHIDError: Error {
    /// No Logitech receiver matching our filters was found.
    case receiverNotFound
    /// The system denied access to the receiver, usually because
    /// Input Monitoring permission has not been granted.
    case permissionDenied
    /// Opening the receiver failed for another I/O reason.
    /// Code is the raw IOReturn value from IOKit.
    case deviceOpenFailed(code: Int32)
    /// A required HID++ feature (e.g. Unified Battery) is missing.
    case featureNotFound(featureId: UInt16)
    /// The receiver responded with bytes that did not match the
    /// expected HID++ layout.
    case unexpectedResponse
    /// The device rejected a setting change with an error code.
    /// Common codes: 0x01=UNKNOWN, 0x02=INVALID_ARGUMENT, 0x05=NOT_ALLOWED
    case settingRejected(errorCode: UInt8)
}

// IOKit constant replicated here to avoid importing IOKit in Domain layer.
// kIOReturnNotPrivileged = 0xe00002c1 (iokit_common_err(0x2c1))
private let kIOReturnNotPrivilegedValue: Int32 = -536870719

extension LogitechHIDError {
    /// Returns true when this error is most likely caused by
    /// macOS privacy (TCC) restrictions such as Input Monitoring.
    var isPermissionsRelated: Bool {
        switch self {
        case .permissionDenied:
            return true
        case let .deviceOpenFailed(code):
            return code == kIOReturnNotPrivilegedValue
        case .receiverNotFound,
             .featureNotFound,
             .unexpectedResponse,
             .settingRejected:
            return false
        }
    }
}

extension LogitechHIDError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .receiverNotFound:
            return "No Logitech receiver found"
        case .permissionDenied:
            return "Permission denied - enable Input Monitoring"
        case .deviceOpenFailed(let code):
            return "Failed to open device (error \(code))"
        case .featureNotFound(let featureId):
            return "Feature 0x\(String(format: "%04X", featureId)) not supported"
        case .unexpectedResponse:
            return "Unexpected response from device"
        case .settingRejected(let errorCode):
            let reason: String
            switch errorCode {
            case 0x01: reason = "unknown function"
            case 0x02: reason = "invalid argument"
            case 0x03: reason = "out of range"
            case 0x04: reason = "hardware error"
            case 0x05: reason = "not allowed"
            case 0x06: reason = "invalid feature index"
            case 0x07: reason = "invalid function"
            case 0x08: reason = "busy"
            default: reason = "error 0x\(String(format: "%02X", errorCode))"
            }
            return "Device rejected setting: \(reason)"
        }
    }
}
