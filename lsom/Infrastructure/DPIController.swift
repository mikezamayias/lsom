//
//  DPIController.swift
//  lsom
//
//  Controller for Adjustable DPI feature (0x2201).
//

import Foundation

/// Controller for reading and setting mouse DPI via HID++ 2.0.
final class DPIController {
    private let transport: HIDTransport
    private let logService: HIDLogService

    /// Cached feature index for DPI (0x2201)
    private var cachedFeatureIndex: UInt8?

    init(transport: HIDTransport, logService: HIDLogService) {
        self.transport = transport
        self.logService = logService
    }

    /// Clears cached feature index. Call on device disconnect.
    func clearCache() {
        cachedFeatureIndex = nil
    }

    /// Returns the number of DPI sensors on the device.
    func sensorCount() throws -> Int {
        guard let deviceIndex = transport.findActiveDeviceIndex() else {
            throw LogitechHIDError.receiverNotFound
        }

        guard let featureIndex = getFeatureIndex(deviceIndex: deviceIndex) else {
            throw LogitechHIDError.featureNotFound(featureId: HIDPPConstants.adjustableDPIFeatureId)
        }

        // Function 0x00: getSensorCount
        guard let resp = transport.sendFAPCommand(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionIndex: 0x00,
            params: []
        ) else {
            throw LogitechHIDError.unexpectedResponse
        }

        let params = Array(resp.dropFirst(4))
        guard let count = HIDPPParsing.parseDPISensorCount(params) else {
            throw LogitechHIDError.unexpectedResponse
        }

        return count
    }

    /// Returns DPI settings for a specific sensor.
    func settings(forSensor sensorIndex: Int) throws -> DPISensorInfo {
        guard let deviceIndex = transport.findActiveDeviceIndex() else {
            throw LogitechHIDError.receiverNotFound
        }

        guard let featureIndex = getFeatureIndex(deviceIndex: deviceIndex) else {
            throw LogitechHIDError.featureNotFound(featureId: HIDPPConstants.adjustableDPIFeatureId)
        }

        // Function 0x01: getSensorDpiList
        guard let listResp = transport.sendFAPCommand(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionIndex: 0x01,
            params: [UInt8(sensorIndex)]
        ) else {
            throw LogitechHIDError.unexpectedResponse
        }

        let listParams = Array(listResp.dropFirst(4))
        let supportedValues = HIDPPParsing.parseDPIList(listParams)

        // Function 0x02: getSensorDpi (current + default)
        guard let dpiResp = transport.sendFAPCommand(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionIndex: 0x02,
            params: [UInt8(sensorIndex)]
        ) else {
            throw LogitechHIDError.unexpectedResponse
        }

        let dpiParams = Array(dpiResp.dropFirst(4))
        guard let (currentDPI, defaultDPI) = HIDPPParsing.parseDPICurrent(dpiParams) else {
            throw LogitechHIDError.unexpectedResponse
        }

        return DPISensorInfo(
            sensorIndex: sensorIndex,
            currentDPI: currentDPI,
            defaultDPI: defaultDPI,
            supportedValues: supportedValues
        )
    }

    /// Sets the DPI for a specific sensor.
    func setDPI(_ dpi: Int, forSensor sensorIndex: Int) throws {
        guard let deviceIndex = transport.findActiveDeviceIndex() else {
            throw LogitechHIDError.receiverNotFound
        }

        guard let featureIndex = getFeatureIndex(deviceIndex: deviceIndex) else {
            throw LogitechHIDError.featureNotFound(featureId: HIDPPConstants.adjustableDPIFeatureId)
        }

        // Function 0x03: setSensorDpi
        // params: [sensorIndex, dpiHi, dpiLo]
        let dpiHi = UInt8((dpi >> 8) & 0xFF)
        let dpiLo = UInt8(dpi & 0xFF)

        guard let response = transport.sendFAPCommand(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionIndex: 0x03,
            params: [UInt8(sensorIndex), dpiHi, dpiLo]
        ) else {
            throw LogitechHIDError.unexpectedResponse
        }

        if let errorCode = fapErrorCode(from: response) {
            log("Set DPI rejected (error 0x\(String(format: "%02X", errorCode)))")
            throw LogitechHIDError.settingRejected(errorCode: errorCode)
        }

        log("Set DPI to \(dpi) for sensor \(sensorIndex)")
    }

    // MARK: - Private Helpers

    private func getFeatureIndex(deviceIndex: UInt8) -> UInt8? {
        if let cached = cachedFeatureIndex {
            return cached
        }

        guard let (index, _) = transport.getFeatureIndex(
            deviceIndex: deviceIndex,
            featureId: HIDPPConstants.adjustableDPIFeatureId
        ) else {
            return nil
        }

        cachedFeatureIndex = index
        return index
    }

    private func fapErrorCode(from response: [UInt8]) -> UInt8? {
        guard response.count >= 6 else { return nil }
        guard response[0] == UInt8(HIDPPConstants.longReportId) else { return nil }
        guard response[2] == 0xFF else { return nil }
        return response[5]
    }

    private func log(_ message: String) {
        logService.log("DPI: \(message)")
    }
}
