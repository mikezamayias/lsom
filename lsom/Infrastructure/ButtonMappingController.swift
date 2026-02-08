//
//  ButtonMappingController.swift
//  lsom
//
//  Controller for Special Keys & Mouse Buttons feature (0x1B04).
//

import Foundation

/// Controller for reading and configuring button mappings via HID++ 2.0.
final class ButtonMappingController {
    private let transport: HIDTransport
    private let logService: HIDLogService

    /// Cached feature index for buttons (0x1B04)
    private var cachedFeatureIndex: UInt8?

    init(transport: HIDTransport, logService: HIDLogService) {
        self.transport = transport
        self.logService = logService
    }

    /// Clears cached feature index. Call on device disconnect.
    func clearCache() {
        cachedFeatureIndex = nil
    }

    /// Returns all button mappings from the device.
    func buttonMappings() throws -> [ButtonMapping] {
        guard let deviceIndex = transport.findActiveDeviceIndex() else {
            throw LogitechHIDError.receiverNotFound
        }

        guard let featureIndex = getFeatureIndex(deviceIndex: deviceIndex) else {
            throw LogitechHIDError.featureNotFound(featureId: HIDPPConstants.specialKeysButtonsFeatureId)
        }

        // Function 0x00: getCount
        guard let countResp = transport.sendFAPCommand(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionIndex: 0x00,
            params: []
        ) else {
            throw LogitechHIDError.unexpectedResponse
        }

        let countParams = Array(countResp.dropFirst(4))
        guard let count = HIDPPParsing.parseControlCount(countParams) else {
            throw LogitechHIDError.unexpectedResponse
        }

        var mappings: [ButtonMapping] = []

        for i in 0..<count {
            // Function 0x01: getCidInfo
            guard let infoResp = transport.sendFAPCommand(
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                functionIndex: 0x01,
                params: [UInt8(i)]
            ) else {
                continue
            }

            let infoParams = Array(infoResp.dropFirst(4))
            guard let (cid, tid, flags, _, gmask) = HIDPPParsing.parseControlInfo(infoParams) else {
                continue
            }

            // Function 0x02: getCidReporting
            var diverted = false
            var remappedTo: Int? = nil

            if let reportResp = transport.sendFAPCommand(
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                functionIndex: 0x02,
                params: [UInt8((cid >> 8) & 0xFF), UInt8(cid & 0xFF)]
            ) {
                let reportParams = Array(reportResp.dropFirst(4))
                if let (d, r) = HIDPPParsing.parseControlReporting(reportParams) {
                    diverted = d
                    remappedTo = r
                }
            }

            let buttonFlags = ButtonFlags(rawValue: flags)
            let control = ButtonControl(
                controlId: cid,
                taskId: tid,
                name: HIDPPParsing.controlName(for: cid),
                flags: buttonFlags,
                groupMask: gmask
            )

            mappings.append(ButtonMapping(
                control: control,
                remappedTo: remappedTo,
                isDiverted: diverted
            ))
        }

        return mappings
    }

    /// Remaps a button to a different control ID.
    func remapButton(controlId: Int, to targetCID: Int?) throws {
        guard let deviceIndex = transport.findActiveDeviceIndex() else {
            throw LogitechHIDError.receiverNotFound
        }

        guard let featureIndex = getFeatureIndex(deviceIndex: deviceIndex) else {
            throw LogitechHIDError.featureNotFound(featureId: HIDPPConstants.specialKeysButtonsFeatureId)
        }

        let cidHi = UInt8((controlId >> 8) & 0xFF)
        let cidLo = UInt8(controlId & 0xFF)
        let target = targetCID ?? 0
        let targetHi = UInt8((target >> 8) & 0xFF)
        let targetLo = UInt8(target & 0xFF)

        // Function 0x03: setCidReporting
        // params: [cidHi, cidLo, flags, remapHi, remapLo]
        // flags: bit 0 = persist
        let flags: UInt8 = 0x01  // persist

        guard transport.sendFAPCommand(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionIndex: 0x03,
            params: [cidHi, cidLo, flags, targetHi, targetLo]
        ) != nil else {
            throw LogitechHIDError.unexpectedResponse
        }

        log("Remapped button \(String(format: "0x%04X", controlId)) to \(targetCID.map { String(format: "0x%04X", $0) } ?? "default")")
    }

    /// Sets whether a button should be diverted to software.
    func setButtonDivert(controlId: Int, diverted: Bool) throws {
        guard let deviceIndex = transport.findActiveDeviceIndex() else {
            throw LogitechHIDError.receiverNotFound
        }

        guard let featureIndex = getFeatureIndex(deviceIndex: deviceIndex) else {
            throw LogitechHIDError.featureNotFound(featureId: HIDPPConstants.specialKeysButtonsFeatureId)
        }

        let cidHi = UInt8((controlId >> 8) & 0xFF)
        let cidLo = UInt8(controlId & 0xFF)

        // Function 0x03: setCidReporting
        // params: [cidHi, cidLo, flags, 0, 0]
        // flags: bit 0 = persist, bit 1 = divert
        var flags: UInt8 = 0x01  // persist
        if diverted {
            flags |= 0x02  // divert
        }

        guard transport.sendFAPCommand(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionIndex: 0x03,
            params: [cidHi, cidLo, flags, 0, 0]
        ) != nil else {
            throw LogitechHIDError.unexpectedResponse
        }

        log("Set button \(String(format: "0x%04X", controlId)) divert=\(diverted)")
    }

    // MARK: - Private Helpers

    private func getFeatureIndex(deviceIndex: UInt8) -> UInt8? {
        if let cached = cachedFeatureIndex {
            return cached
        }

        guard let (index, _) = transport.getFeatureIndex(
            deviceIndex: deviceIndex,
            featureId: HIDPPConstants.specialKeysButtonsFeatureId
        ) else {
            return nil
        }

        cachedFeatureIndex = index
        return index
    }

    private func log(_ message: String) {
        logService.log("Buttons: \(message)")
    }
}
