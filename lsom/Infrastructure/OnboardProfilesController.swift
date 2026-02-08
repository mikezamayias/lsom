//
//  OnboardProfilesController.swift
//  lsom
//
//  Controller for Onboard Profiles feature (0x8100).
//

import Foundation

/// Controller for managing onboard profiles via HID++ 2.0.
final class OnboardProfilesController {
    private let transport: HIDTransport
    private let logService: HIDLogService

    /// Cached feature index for onboard profiles (0x8100)
    private var cachedFeatureIndex: UInt8?

    /// Cached profile selection for restore after re-enable
    private var cachedProfileSelection: [UInt8]?

    init(transport: HIDTransport, logService: HIDLogService) {
        self.transport = transport
        self.logService = logService
    }

    /// Clears cached data. Call on device disconnect.
    func clearCache() {
        cachedFeatureIndex = nil
        cachedProfileSelection = nil
    }

    /// Returns whether the device supports onboard profiles.
    func supportsOnboardProfiles() -> Bool {
        guard let deviceIndex = transport.findActiveDeviceIndex() else {
            return false
        }

        let supported = getFeatureIndex(deviceIndex: deviceIndex) != nil
        log("Onboard profiles supported: \(supported)")
        return supported
    }

    /// Returns whether onboard profiles are currently enabled.
    func isEnabled() throws -> Bool {
        guard let deviceIndex = transport.findActiveDeviceIndex() else {
            throw LogitechHIDError.receiverNotFound
        }

        guard let featureIndex = getFeatureIndex(deviceIndex: deviceIndex) else {
            throw LogitechHIDError.featureNotFound(featureId: HIDPPConstants.onboardProfilesFeatureId)
        }

        // Function 0x02: getOnboardProfilesMode
        guard let resp = transport.sendFAPCommand(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionIndex: 0x02,
            params: []
        ) else {
            throw LogitechHIDError.unexpectedResponse
        }

        let params = Array(resp.dropFirst(4))
        guard let enabledByte = params.first else {
            throw LogitechHIDError.unexpectedResponse
        }

        let enabled = enabledByte == 0x01

        // Cache active profile selection for later restore
        if enabled {
            cacheActiveProfile(deviceIndex: deviceIndex, featureIndex: featureIndex)
        }

        log("Onboard profiles enabled: \(enabled)")
        return enabled
    }

    /// Enables or disables onboard profiles.
    func setEnabled(_ enabled: Bool) throws {
        guard let deviceIndex = transport.findActiveDeviceIndex() else {
            throw LogitechHIDError.receiverNotFound
        }

        guard let featureIndex = getFeatureIndex(deviceIndex: deviceIndex) else {
            throw LogitechHIDError.featureNotFound(featureId: HIDPPConstants.onboardProfilesFeatureId)
        }

        // Mode: 0x01 = onboard, 0x02 = host
        let modeByte: UInt8 = enabled ? 0x01 : 0x02

        // Function 0x01: setOnboardProfilesMode
        guard transport.sendFAPCommand(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionIndex: 0x01,
            params: [modeByte]
        ) != nil else {
            throw LogitechHIDError.unexpectedResponse
        }

        // Restore active profile when re-enabling
        if enabled, let selection = cachedProfileSelection, selection.count >= 2 {
            _ = transport.sendFAPCommand(
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                functionIndex: 0x03,
                params: Array(selection.prefix(2))
            )
        }

        log("Set onboard profiles enabled=\(enabled)")
    }

    // MARK: - Private Helpers

    private func getFeatureIndex(deviceIndex: UInt8) -> UInt8? {
        if let cached = cachedFeatureIndex {
            return cached
        }

        guard let (index, _) = transport.getFeatureIndex(
            deviceIndex: deviceIndex,
            featureId: HIDPPConstants.onboardProfilesFeatureId
        ) else {
            return nil
        }

        cachedFeatureIndex = index
        return index
    }

    private func cacheActiveProfile(deviceIndex: UInt8, featureIndex: UInt8) {
        // Function 0x04: getActiveProfile
        if let activeResp = transport.sendFAPCommand(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionIndex: 0x04,
            params: []
        ) {
            let activeParams = Array(activeResp.dropFirst(4))
            if activeParams.count >= 2 {
                cachedProfileSelection = Array(activeParams.prefix(2))
            }
        }
    }

    private func log(_ message: String) {
        logService.log("Profiles: \(message)")
    }
}
