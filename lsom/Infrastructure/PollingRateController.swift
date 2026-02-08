//
//  PollingRateController.swift
//  lsom
//
//  Controller for Report Rate features (0x8060 and 0x8061).
//

import Foundation

/// Controller for reading and setting polling rate via HID++ 2.0.
final class PollingRateController {
    private let transport: HIDTransport
    private let logService: HIDLogService

    /// Cached feature indices
    private var cachedStandardFeatureIndex: UInt8?
    private var cachedExtendedFeatureIndex: UInt8?

    init(transport: HIDTransport, logService: HIDLogService) {
        self.transport = transport
        self.logService = logService
    }

    /// Clears cached feature indices. Call on device disconnect.
    func clearCache() {
        cachedStandardFeatureIndex = nil
        cachedExtendedFeatureIndex = nil
    }

    /// Returns current polling rate information.
    func pollingRateInfo() throws -> PollingRateInfo {
        log("pollingRateInfo ENTRY")

        guard let deviceIndex = transport.findActiveDeviceIndex() else {
            log("pollingRateInfo ERROR: No device found")
            throw LogitechHIDError.receiverNotFound
        }

        // Try standard feature first (0x8060)
        if let featureIndex = getStandardFeatureIndex(deviceIndex: deviceIndex) {
            log("using STANDARD feature (0x8060), index=0x\(String(format: "%02X", featureIndex))")

            if let info = tryStandardPollingRate(deviceIndex: deviceIndex, featureIndex: featureIndex) {
                return info
            }
        }

        // Fall back to extended feature (0x8061)
        if let featureIndex = getExtendedFeatureIndex(deviceIndex: deviceIndex) {
            log("using EXTENDED feature (0x8061), index=0x\(String(format: "%02X", featureIndex))")

            if let info = tryExtendedPollingRate(deviceIndex: deviceIndex, featureIndex: featureIndex) {
                return info
            }
        }

        throw LogitechHIDError.featureNotFound(featureId: HIDPPConstants.reportRateFeatureId)
    }

    /// Sets the polling rate.
    func setPollingRate(_ rateHz: Int) throws {
        log("setPollingRate ENTRY - requested=\(rateHz) Hz")

        guard let deviceIndex = transport.findActiveDeviceIndex() else {
            log("ERROR: No active device found")
            throw LogitechHIDError.receiverNotFound
        }

        let hasStandard = getStandardFeatureIndex(deviceIndex: deviceIndex) != nil
        let hasExtended = getExtendedFeatureIndex(deviceIndex: deviceIndex) != nil
        log("Feature support - standard(0x8060)=\(hasStandard ? "YES" : "NO"), extended(0x8061)=\(hasExtended ? "YES" : "NO")")

        let info = try pollingRateInfo()
        log("Current info - currentHz=\(info.currentHz), featureId=0x\(String(format: "%04X", info.featureId))")

        // Try standard feature first if that's what we queried
        if info.featureId == HIDPPConstants.reportRateFeatureId, hasStandard {
            if try trySetStandard(deviceIndex: deviceIndex, rateHz: rateHz, info: info) {
                return
            }
        }

        // Fall back to extended feature
        if hasExtended {
            if try trySetExtended(deviceIndex: deviceIndex, rateHz: rateHz) {
                return
            }
        }

        log("setPollingRate EXIT - FAILED to verify change")
        throw LogitechHIDError.unexpectedResponse
    }

    // MARK: - Standard Feature (0x8060)

    private func tryStandardPollingRate(deviceIndex: UInt8, featureIndex: UInt8) -> PollingRateInfo? {
        // Function 0x00: getReportRateList
        guard let listResp = transport.sendFAPCommand(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionIndex: 0x00,
            params: []
        ) else {
            log("getReportRateList returned nil")
            return nil
        }

        let listParams = Array(listResp.dropFirst(4))
        let supportedMask = HIDPPParsing.parseReportRateMask(listParams)
        let supportedRates = HIDPPParsing.parseReportRateList(listParams)
        log("Parsed supportedMask=0x\(String(format: "%04X", supportedMask)), supportedRates=\(supportedRates)")

        // Function 0x01: getReportRate
        guard let rateResp = transport.sendFAPCommand(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionIndex: 0x01,
            params: []
        ) else {
            log("getReportRate returned nil")
            return nil
        }

        let rateParams = Array(rateResp.dropFirst(4))
        guard let currentHz = HIDPPParsing.parseCurrentReportRate(
            rateParams,
            supportedMask: supportedMask
        ) else {
            log("parseCurrentReportRate returned nil")
            return nil
        }

        log("pollingRateInfo EXIT - currentHz=\(currentHz) (standard)")
        return PollingRateInfo(
            currentHz: currentHz,
            supportedHz: supportedRates,
            supportedMask: supportedMask,
            featureId: HIDPPConstants.reportRateFeatureId
        )
    }

    private func trySetStandard(deviceIndex: UInt8, rateHz: Int, info: PollingRateInfo) throws -> Bool {
        guard let featureIndex = getStandardFeatureIndex(deviceIndex: deviceIndex) else {
            return false
        }

        guard let msValue = HIDPPParsing.reportRateSettingValue(
            forHz: rateHz,
            supportedMask: info.supportedMask
        ) else {
            log("ERROR: No valid ms value for \(rateHz) Hz")
            return false
        }

        let bitIndex = UInt8(msValue - 1)
        let mask16 = UInt16(1 << bitIndex)
        let mask8 = UInt8(mask16 & 0xFF)
        let maskLE: [UInt8] = [mask8, UInt8((mask16 >> 8) & 0xFF)]

        let candidates: [(label: String, params: [UInt8])] = [
            ("ms", [msValue]),
            ("bit", [bitIndex]),
            ("mask8", [mask8]),
            ("mask16", maskLE)
        ]

        for candidate in candidates {
            log("Trying candidate '\(candidate.label)'")

            guard let response = transport.sendFAPCommand(
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                functionIndex: 0x02,
                params: candidate.params
            ) else {
                continue
            }

            if fapErrorCode(from: response) != nil {
                continue
            }

            // Small delay then verify
            Thread.sleep(forTimeInterval: 0.1)
            if verifyRate(rateHz) {
                log("setPollingRate EXIT - SUCCESS with standard feature")
                return true
            }
        }

        return false
    }

    // MARK: - Extended Feature (0x8061)

    private func tryExtendedPollingRate(deviceIndex: UInt8, featureIndex: UInt8) -> PollingRateInfo? {
        // Function 0x01: getReportRateList (extended)
        guard let listResp = transport.sendFAPCommand(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionIndex: 0x01,
            params: []
        ) else {
            log("Extended getReportRateList returned nil")
            return nil
        }

        let listParams = Array(listResp.dropFirst(4))
        let supportedMask = HIDPPParsing.parseExtendedReportRateMask(listParams)
        let supportedRates = HIDPPParsing.parseExtendedReportRateList(fromMask: supportedMask)
        log("Extended supportedMask=0x\(String(format: "%04X", supportedMask)), supportedRates=\(supportedRates)")

        // Function 0x02: getReportRate (extended)
        guard let rateResp = transport.sendFAPCommand(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionIndex: 0x02,
            params: []
        ) else {
            log("Extended getReportRate returned nil")
            return nil
        }

        let rateParams = Array(rateResp.dropFirst(4))
        guard let currentHz = HIDPPParsing.parseExtendedCurrentReportRate(
            rateParams,
            supportedMask: supportedMask
        ) else {
            log("parseExtendedCurrentReportRate returned nil")
            return nil
        }

        log("pollingRateInfo EXIT - currentHz=\(currentHz) (extended)")
        return PollingRateInfo(
            currentHz: currentHz,
            supportedHz: supportedRates,
            supportedMask: supportedMask,
            featureId: HIDPPConstants.extendedAdjustableReportRateFeatureId
        )
    }

    private func trySetExtended(deviceIndex: UInt8, rateHz: Int) throws -> Bool {
        guard let featureIndex = getExtendedFeatureIndex(deviceIndex: deviceIndex) else {
            return false
        }

        // Get extended mask directly
        guard let listResp = transport.sendFAPCommand(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionIndex: 0x01,
            params: []
        ) else {
            return false
        }

        let listParams = Array(listResp.dropFirst(4))
        let supportedMask = HIDPPParsing.parseExtendedReportRateMask(listParams)

        guard let indexValue = HIDPPParsing.extendedReportRateSettingValue(
            forHz: rateHz,
            supportedMask: supportedMask
        ) else {
            log("ERROR: No valid index for \(rateHz) Hz with extended mask")
            return false
        }

        guard let response = transport.sendFAPCommand(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionIndex: 0x03,
            params: [indexValue]
        ) else {
            return false
        }

        if let errorCode = fapErrorCode(from: response) {
            log("Extended set rejected with error 0x\(String(format: "%02X", errorCode))")
            throw LogitechHIDError.settingRejected(errorCode: errorCode)
        }

        // Small delay then verify
        Thread.sleep(forTimeInterval: 0.1)
        if verifyRate(rateHz) {
            log("setPollingRate EXIT - SUCCESS with extended feature")
            return true
        }

        return false
    }

    // MARK: - Helpers

    private func getStandardFeatureIndex(deviceIndex: UInt8) -> UInt8? {
        if let cached = cachedStandardFeatureIndex {
            return cached
        }

        guard let (index, _) = transport.getFeatureIndex(
            deviceIndex: deviceIndex,
            featureId: HIDPPConstants.reportRateFeatureId
        ) else {
            return nil
        }

        cachedStandardFeatureIndex = index
        return index
    }

    private func getExtendedFeatureIndex(deviceIndex: UInt8) -> UInt8? {
        if let cached = cachedExtendedFeatureIndex {
            return cached
        }

        guard let (index, _) = transport.getFeatureIndex(
            deviceIndex: deviceIndex,
            featureId: HIDPPConstants.extendedAdjustableReportRateFeatureId
        ) else {
            return nil
        }

        cachedExtendedFeatureIndex = index
        return index
    }

    private func verifyRate(_ expectedHz: Int) -> Bool {
        guard let info = try? pollingRateInfo() else {
            log("ERROR: Could not read polling rate after set")
            return false
        }

        if info.currentHz == expectedHz {
            log("SUCCESS: Rate verified as \(expectedHz) Hz")
            return true
        }

        log("MISMATCH: Device reports \(info.currentHz) Hz, we requested \(expectedHz) Hz")
        return false
    }

    private func fapErrorCode(from response: [UInt8]) -> UInt8? {
        guard response.count >= 6 else { return nil }
        guard response[0] == UInt8(HIDPPConstants.longReportId) else { return nil }
        guard response[2] == 0xFF else { return nil }
        return response[5]
    }

    private func log(_ message: String) {
        logService.log("Polling: \(message)")
    }
}
