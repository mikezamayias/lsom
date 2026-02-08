//
//  LogitechHIDService.swift
//  lsom
//
//  Core HID++ 2.0 FAP/RAP implementation for Logitech devices.
//  Created by Mike Zamagias on 27/12/2025.
//

import Combine
import Foundation
import IOKit
import IOKit.hid

// Simple holder used by the HID++ FAP input-report callback.
// It lets us synchronously wait for the next report with a given ID.
// Thread-safe: accessed from both C callback and run-loop polling.
final class HIDFAPWaiter: @unchecked Sendable {
    let reportID: UInt32
    private let lock = NSLock()
    private var _response: [UInt8]?
    private var _done: Bool = false

    var response: [UInt8]? {
        get { lock.withLock { _response } }
        set { lock.withLock { _response = newValue } }
    }

    var done: Bool {
        get { lock.withLock { _done } }
        set { lock.withLock { _done = newValue } }
    }

    init(reportID: UInt32) {
        self.reportID = reportID
    }
}

// Global C callback bridge for IOHIDDeviceRegisterInputReportCallback.
private let hidFAPInputCallback: IOHIDReportCallback = { (context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, type: IOHIDReportType, reportID: UInt32, report: UnsafeMutablePointer<UInt8>, reportLength: CFIndex) in
    guard result == kIOReturnSuccess, let context = context else {
        return
    }

    let waiter = Unmanaged<HIDFAPWaiter>.fromOpaque(context)
        .takeUnretainedValue()

    // Only capture reports for the ID we're interested in.
    guard reportID == waiter.reportID else { return }

    let bytes: [UInt8]
    if reportLength > 0 {
        let buf = UnsafeBufferPointer(start: report, count: Int(reportLength))
        bytes = Array(buf)
    } else {
        bytes = []
    }

    waiter.response = bytes
    waiter.done = true
}

// Timestamp formatter for DEBUG logging.
#if DEBUG
private let hidLogTimestampFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()
#endif

/// Concrete HID implementation used by the application for
/// reading Logitech mouse battery state and managing
/// DPI / polling / button settings. Also provides debug logging.
///
/// This class acts as both the HID transport layer and a facade that
/// delegates to specialized controllers for different features.
final class LogitechHIDService: BatteryService, MouseSettingsService, HIDTransport {
    // Single manager and cached receiver for the app lifetime.
    private let manager: IOHIDManager
    private var receiver: IOHIDDevice?

    /// Injected logging service for HID protocol traffic.
    private let logService: HIDLogService

    // MARK: - Feature Controllers

    private lazy var dpiController = DPIController(transport: self, logService: logService)
    private lazy var pollingRateController = PollingRateController(transport: self, logService: logService)
    private lazy var buttonMappingController = ButtonMappingController(transport: self, logService: logService)
    private lazy var onboardProfilesController = OnboardProfilesController(transport: self, logService: logService)

    /// Publisher that emits when a Logitech receiver is connected or disconnected.
    /// `true` = connected, `false` = disconnected.
    let deviceConnectionSubject = PassthroughSubject<Bool, Never>()

    var deviceConnectionPublisher: AnyPublisher<Bool, Never> {
        deviceConnectionSubject.eraseToAnyPublisher()
    }

    /// Publisher that emits when mouse settings (DPI, polling rate) change.
    private let settingsChangeSubject = PassthroughSubject<MouseSettingsChange, Never>()

    var settingsChangePublisher: AnyPublisher<MouseSettingsChange, Never> {
        settingsChangeSubject.eraseToAnyPublisher()
    }

    // Cached feature indices (cleared on disconnect)
    private var cachedDeviceIndex: UInt8?
    private var cachedDeviceNameFeatureIndex: UInt8?
    private var cachedDeviceName: String?
    private var cachedDPIFeatureIndex: UInt8?
    private var cachedReportRateFeatureIndex: UInt8?
    private var cachedExtendedReportRateFeatureIndex: UInt8?
    private var cachedButtonsFeatureIndex: UInt8?
    private var cachedOnboardProfilesFeatureIndex: UInt8?
    private var cachedOnboardProfileSelection: [UInt8]?

    /// Returns true if running in Xcode Previews or Playgrounds.
    private static var isPreviewMode: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" ||
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
    }

    /// Track whether HID is actually initialized (false during previews).
    private let isHIDInitialized: Bool

    /// Internal logging helper that writes to console in DEBUG and persistent file always.
    private func log(_ message: @autoclosure () -> String) {
        let msg = message()
        #if DEBUG
        let timestamp = hidLogTimestampFormatter.string(from: Date())
        print("[\(timestamp)] HID: \(msg)")
        #endif
        logService.log(msg)
    }

    init(logService: HIDLogService) {
        self.logService = logService
        manager = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )

        // Skip HID initialization during Xcode Previews to prevent crashes
        guard !Self.isPreviewMode else {
            isHIDInitialized = false
            log("lsom/hid: Skipping HID initialization (preview mode)")
            return
        }
        isHIDInitialized = true

        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: HIDPPConstants.logitechVendorId,
            kIOHIDProductIDKey as String: HIDPPConstants.unifyingReceiverPid,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        // Register device connection/disconnection callbacks
        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(
            manager,
            { context, _, _, device in
                guard let context = context else { return }

                // Only react to the HID++ interface (usagePage 0xFF00)
                let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
                guard usagePage == 0xFF00 else { return }

                let service = Unmanaged<LogitechHIDService>.fromOpaque(context).takeUnretainedValue()
                service.log("lsom/hid: HID++ device connected (usagePage=0xFF00)")
                // Clear cached receiver so ensureReceiverOpen() will re-scan and open properly
                service.receiver = nil
                service.deviceConnectionSubject.send(true)
            },
            context
        )

        IOHIDManagerRegisterDeviceRemovalCallback(
            manager,
            { context, _, _, device in
                guard let context = context else { return }

                // Only react to the HID++ interface (usagePage 0xFF00)
                let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
                guard usagePage == 0xFF00 else { return }

                let service = Unmanaged<LogitechHIDService>.fromOpaque(context).takeUnretainedValue()
                service.log("lsom/hid: HID++ device disconnected (usagePage=0xFF00)")
                service.receiver = nil
                service.clearFeatureCache()
                service.deviceConnectionSubject.send(false)
            },
            context
        )

        // Schedule on main run loop to receive callbacks
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )

        let openResult = IOHIDManagerOpen(
            manager,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        if openResult != kIOReturnSuccess {
            log(
                "lsom/hid: IOHIDManagerOpen (init) failed: \(openResult)"
            )
        }
    }

    // MARK: - Public entry point

    /// Logs basic HID enumeration and then dumps the HID++ feature table
    /// for the Logitech Unifying receiver / mouse, if available.
    func logReceiverStateAndFeatures() {
        logReceiverEnumeration()
        logHIDPPFeatureTable()
    }

    // MARK: - Plain HID enumeration (what you already had)

    private func logReceiverEnumeration() {
        log("lsom/hid: === debug session start ===")

        let openResult = IOHIDManagerOpen(
            manager,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        log("lsom/hid: IOHIDManagerOpen -> \(openResult)")
        guard openResult == kIOReturnSuccess else { return }

        guard
            let deviceSet = IOHIDManagerCopyDevices(manager)
                as? Set<IOHIDDevice>
        else {
            log("lsom/hid: IOHIDManagerCopyDevices returned nil")
            return
        }

        log("lsom/hid: found \(deviceSet.count) HID device(s)")

        for device in deviceSet {
            let vid = intProperty(device, key: kIOHIDVendorIDKey as CFString)
            let pid = intProperty(device, key: kIOHIDProductIDKey as CFString)
            let usagePage = intProperty(
                device,
                key: kIOHIDPrimaryUsagePageKey as CFString
            )
            let usage = intProperty(
                device,
                key: kIOHIDPrimaryUsageKey as CFString
            )
            let product =
                stringProperty(device, key: kIOHIDProductKey as CFString) ?? "?"
            let transport =
                stringProperty(device, key: kIOHIDTransportKey as CFString)
                ?? "?"

            log(
                String(
                    format:
                        "lsom/hid: device vid=0x%04X pid=0x%04X usagePage=0x%04X usage=0x%04X product=\"%@\" transport=%@",
                    vid,
                    pid,
                    usagePage,
                    usage,
                    product,
                    transport
                )
            )
        }

        log("lsom/hid: === debug session end ===")
    }

    // MARK: - HID++ 2.0 feature dump

    // Note: Protocol constants are defined in HIDPPConstants (HIDTransport.swift)
    // Response structs FAPResponse and RAPResponse are also defined there.

    /// Returns a HID++ error code when the response is an error report (featureIndex 0xFF).
    private func fapErrorCode(from response: [UInt8]) -> UInt8? {
        guard response.count >= 6 else { return nil }
        guard response[0] == UInt8(HIDPPConstants.longReportId) else { return nil }
        guard response[2] == 0xFF else { return nil }
        return response[5]
    }

    /// Builds a HID++ 2.0 function byte with software ID 0x01 and sends it via FAP.
    private func sendFAPCommandInternal(
        device: IOHIDDevice,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        functionIndex: UInt8,
        params: [UInt8]
    ) -> [UInt8]? {
        let softwareId: UInt8 = 0x01
        let funcIndexClientId =
            ((functionIndex & 0x0F) << 4) | (softwareId & 0x0F)
        return sendFAPBytes(
            device: device,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionByte: funcIndexClientId,
            params: params
        )
    }

    // Low-level helper that mirrors the Python script's send_fap:
    // build a 20-byte report (0x11, devIdx, featIdx, funcByte, 16 params),
    // send it, then synchronously wait for the next input report with
    // ID 0x11 using an IOHIDDeviceRegisterInputReportCallback-backed
    // run loop. This matches how hidapi reads on macOS.
    private func sendFAPBytes(
        device: IOHIDDevice,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        functionByte: UInt8,
        params: [UInt8]
    ) -> [UInt8]? {
        if params.count > HIDPPConstants.maxParamCount {
            log(
                "lsom/hid: sendFAPBytes called with too many params (\(params.count))"
            )
            return nil
        }

        // Build the 20-byte HID++ long report.
        var tx = [UInt8](
            repeating: 0,
            count: Int(HIDPPConstants.totalReportLength)
        )
        tx[0] = UInt8(HIDPPConstants.longReportId)
        tx[1] = deviceIndex
        tx[2] = featureIndex
        tx[3] = functionByte & 0xFF
        for (i, b) in params.enumerated() {
            tx[4 + i] = b
        }

        log(
            String(
                format:
                    "lsom/hid: FAP tx (raw) devIdx=0x%02X featIdx=0x%02X funcByte=0x%02X params=%@",
                deviceIndex,
                featureIndex,
                functionByte,
                params
                    .map { String(format: "0x%02X", $0) }
                    .joined(separator: " ")
            )
        )

        // Prepare waiter and callback buffer.
        let waiter = HIDFAPWaiter(reportID: UInt32(HIDPPConstants.longReportId))
        let context = UnsafeMutableRawPointer(
            Unmanaged.passUnretained(waiter).toOpaque()
        )
        var cbBuffer = [UInt8](repeating: 0, count: 32)

        let runLoop: CFRunLoop = CFRunLoopGetCurrent()
        let mode: CFRunLoopMode = .defaultMode
        IOHIDDeviceScheduleWithRunLoop(
            device,
            runLoop,
            mode.rawValue
        )
        IOHIDDeviceRegisterInputReportCallback(
            device,
            &cbBuffer,
            cbBuffer.count,
            hidFAPInputCallback,
            context
        )

        let setResult: IOReturn = tx.withUnsafeBytes { rawBuffer in
            let ptr = rawBuffer.bindMemory(to: UInt8.self).baseAddress!
            return IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                HIDPPConstants.longReportId,
                ptr,
                tx.count
            )
        }

        if setResult != kIOReturnSuccess {
            log(
                String(
                    format:
                        "lsom/hid: IOHIDDeviceSetReport FAP(raw) failed: 0x%08X",
                    setResult
                )
            )
            // Unregister callback before waiter goes out of scope
            IOHIDDeviceRegisterInputReportCallback(
                device,
                &cbBuffer,
                cbBuffer.count,
                nil,
                nil
            )
            IOHIDDeviceUnscheduleFromRunLoop(
                device,
                runLoop,
                mode.rawValue
            )
            return nil
        }

        // Pump the run loop until we either get a response or time out.
        // Use shorter timeout to avoid long waits when device indices don't respond
        let deadline = Date().timeIntervalSinceReferenceDate + HIDPPConstants.defaultTimeout
        while !waiter.done
            && Date().timeIntervalSinceReferenceDate < deadline
        {
            CFRunLoopRunInMode(mode, 0.05, false)
        }

        // Unregister callback before waiter goes out of scope to prevent dangling pointer
        IOHIDDeviceRegisterInputReportCallback(
            device,
            &cbBuffer,
            cbBuffer.count,
            nil,
            nil
        )

        IOHIDDeviceUnscheduleFromRunLoop(
            device,
            runLoop,
            mode.rawValue
        )

        guard let resp = waiter.response else {
            log("lsom/hid: FAP(raw) timed out waiting for response")
            return nil
        }

        log(
            "lsom/hid: FAP rx (raw) bytes: "
                + resp.map { String(format: "0x%02X", $0) }.joined(separator: " ")
        )
        return resp
    }

    /// Root.GetFeature for a specific featureID, using the raw FAP helper.
    /// Mirrors `root_get_feature_index` from the Python script.
    private func rootGetFeatureIndexFAP(
        device: IOHIDDevice,
        deviceIndex: UInt8,
        featureId: UInt16
    ) -> (featureIndex: UInt8, featureType: UInt8, raw: [UInt8])? {
        let featureHi = UInt8((featureId >> 8) & 0xFF)
        let featureLo = UInt8(featureId & 0xFF)
        let params: [UInt8] = [featureHi, featureLo]

        guard
            let resp = sendFAPBytes(
                device: device,
                deviceIndex: deviceIndex,
                featureIndex: 0x00,
                functionByte: 0x01,
                params: params
            )
        else {
            return nil
        }

        guard resp.count >= 6 else {
            log("lsom/hid: Root.GetFeature FAP response too short")
            return nil
        }

        if resp[0] != 0x11 || resp[1] != deviceIndex {
            log(
                "lsom/hid: Root.GetFeature unexpected header: "
                    + resp.prefix(4).map { String(format: "0x%02X", $0) }
                    .joined(separator: " ")
            )
            return nil
        }

        let featIndex = resp[4]
        let featType = resp[5]
        if featIndex == 0 {
            // Index 0 is Root; 0 for any other feature means "not supported".
            return nil
        }
        return (featIndex, featType, resp)
    }

    /// Unified Battery GET_STATUS using the raw FAP helper.
    private func unifiedBatteryGetStatusFAP(
        device: IOHIDDevice,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) -> (stateOfCharge: UInt8, raw: [UInt8], params: [UInt8])? {
        guard
            let resp = sendFAPBytes(
                device: device,
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                functionByte: 0x10,
                params: []
            )
        else {
            return nil
        }

        guard resp.count >= 5 else {
            log("lsom/hid: UnifiedBattery GET_STATUS response too short")
            return nil
        }

        if resp[0] != 0x11 || resp[1] != deviceIndex {
            log(
                "lsom/hid: UnifiedBattery GET_STATUS unexpected header: "
                    + resp.prefix(4).map { String(format: "0x%02X", $0) }
                    .joined(separator: " ")
            )
            return nil
        }

        let params = Array(resp[4..<min(resp.count, 20)])
        guard let soc = params.first else { return nil }
        return (soc, resp, params)
    }

    /// Enumerate HID++ features via Root (+ FeatureSet when available) and log them.
    private func logHIDPPFeatureTable() {
        log("lsom/hid: === HID++ feature table debug start ===")

        guard let receiver = try? ensureReceiverOpen() else {
            log("lsom/hid: no Logitech Unifying receiver HID++ interface found")
            return
        }

        // First: try to talk HID++ 2.0 UnifiedBattery exactly like the
        // Python script does, using Root.GetFeature to discover the
        // feature index and then UnifiedBattery.GET_STATUS.
        var foundUnifiedBattery = false
        for deviceIndex in 1...6 {
            let dIdx = UInt8(deviceIndex)
            log(
                String(
                    format:
                        "lsom/hid: UnifiedBattery FAP probe devIdx=0x%02X",
                    dIdx
                )
            )

            guard
                let (ubattIndex, ubattType, rootResp) = rootGetFeatureIndexFAP(
                    device: receiver,
                    deviceIndex: dIdx,
                    featureId: 0x1004
                )
            else {
                continue
            }

            foundUnifiedBattery = true
            log(
                String(
                    format:
                        "lsom/hid:   UnifiedBattery feature index=0x%02X type=0x%02X",
                    ubattIndex,
                    ubattType
                )
            )
            log(
                "lsom/hid:   Root.GetFeature raw bytes: "
                    + rootResp.map { String(format: "0x%02X", $0) }
                    .joined(separator: " ")
            )

            if let (soc, ubattResp, ubattParams) = unifiedBatteryGetStatusFAP(
                device: receiver,
                deviceIndex: dIdx,
                featureIndex: ubattIndex
            ) {
                log(
                    "lsom/hid:   UnifiedBattery GET_STATUS raw bytes: "
                        + ubattResp.map { String(format: "0x%02X", $0) }
                        .joined(separator: " ")
                )
                log(
                    "lsom/hid:   UnifiedBattery params[0..15]: "
                        + ubattParams.map { String(format: "0x%02X", $0) }
                        .joined(separator: " ")
                )
                log(
                    "lsom/hid:   UnifiedBattery state_of_charge: \(soc)%"
                )
            }

            // For now we only care about the first paired device that
            // exposes UnifiedBattery.
            break
        }

        if !foundUnifiedBattery {
            log(
                "lsom/hid: UnifiedBattery feature (0x1004) not found via HID++ 2.0 FAP"
            )
        }

        // Finally, try legacy HID++ 1.0 RAP battery registers. This is
        // what many older Unifying receivers/mice use instead of the
        // HID++ 2.0 battery features.
        logHIDPP10BatteryState(receiver: receiver)

        log("lsom/hid: === HID++ feature table debug end ===")
    }

    /// Public convenience: read the Unified Battery percentage for the
    /// first paired device, if available.
    func readUnifiedBatteryPercentage() -> Int? {
        return try? readUnifiedBatteryPercentageInternal()
    }

    /// Internal throwing implementation used by BatteryService.
    private func readUnifiedBatteryPercentageInternal() throws -> Int {
        let receiver = try ensureReceiverOpen()

        // Prefer device index 1, like the Python script. If that fails,
        // try a couple of other indexes.
        let candidateIndexes = Array(HIDPPConstants.deviceIndexRange)
        var lastError: LogitechHIDError = .featureNotFound(featureId: 0x1004)

        for dIdx in candidateIndexes {
            guard
                let (ubattIndex, _, _) = rootGetFeatureIndexFAP(
                    device: receiver,
                    deviceIndex: dIdx,
                    featureId: 0x1004
                )
            else {
                continue
            }

            if let (soc, _, _) = unifiedBatteryGetStatusFAP(
                device: receiver,
                deviceIndex: dIdx,
                featureIndex: ubattIndex
            ) {
                return Int(soc)
            } else {
                lastError = .unexpectedResponse
            }
        }

        throw lastError
    }

    // MARK: - BatteryService

    func batteryPercentage() throws -> Int {
        try readUnifiedBatteryPercentageInternal()
    }

    /// Returns the device name from HID++ 2.0 Device Name feature (0x0005).
    func deviceName() -> String? {
        if let cached = cachedDeviceName {
            return cached
        }

        guard let receiver = try? ensureReceiverOpen(),
              let deviceIndex = findActiveDeviceIndexInternal(device: receiver),
              let featureIndex = getDeviceNameFeatureIndex(device: receiver, deviceIndex: deviceIndex)
        else {
            return nil
        }

        // Function 0: getDeviceNameCount -> returns name length in params[0]
        guard let countResp = sendFAPCommandInternal(
            device: receiver,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionIndex: 0x00,
            params: []
        ) else {
            return nil
        }

        let countParams = Array(countResp.dropFirst(4))
        guard let nameLength = countParams.first, nameLength > 0 else {
            return nil
        }

        // Function 1: getDeviceName(charIndex) -> returns up to 16 chars starting at charIndex
        var nameBytes: [UInt8] = []
        var offset: UInt8 = 0

        while offset < nameLength {
            guard let nameResp = sendFAPCommandInternal(
                device: receiver,
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                functionIndex: 0x01,
                params: [offset]
            ) else {
                break
            }

            let chunk = Array(nameResp.dropFirst(4))
            let remaining = Int(nameLength) - Int(offset)
            let toTake = min(remaining, chunk.count)
            nameBytes.append(contentsOf: chunk.prefix(toTake))
            offset += UInt8(toTake)
        }

        // Convert to string, stopping at null terminator
        if let nullIndex = nameBytes.firstIndex(of: 0) {
            nameBytes = Array(nameBytes.prefix(nullIndex))
        }

        guard let name = String(bytes: nameBytes, encoding: .utf8), !name.isEmpty else {
            return nil
        }

        cachedDeviceName = name
        log("lsom/hid: Device name: \(name)")
        return name
    }

    /// Returns a complete snapshot of the mouse device state.
    func deviceState() async -> MouseDeviceState {
        let name = deviceName() ?? "Unknown Device"
        let battery = try? batteryPercentage()

        // DPI state
        var dpiState: MouseDeviceState.DPIState? = nil
        do {
            let sensorCount = try await dpiSensorCount()
            let dpiInfo = try await dpiSettings(forSensor: 0)
            dpiState = MouseDeviceState.DPIState(
                isSupported: true,
                sensorCount: sensorCount,
                currentDPI: dpiInfo.currentDPI,
                defaultDPI: dpiInfo.defaultDPI,
                supportedValues: dpiInfo.supportedValues
            )
        } catch {
            if case LogitechHIDError.featureNotFound = error {
                dpiState = MouseDeviceState.DPIState(
                    isSupported: false,
                    sensorCount: 0,
                    currentDPI: 0,
                    defaultDPI: 0,
                    supportedValues: []
                )
            }
        }

        // Polling rate state
        var pollingState: MouseDeviceState.PollingRateState? = nil
        do {
            let pollingInfo = try await pollingRateInfo()
            pollingState = MouseDeviceState.PollingRateState(
                isSupported: true,
                currentHz: pollingInfo.currentHz,
                supportedHz: pollingInfo.supportedHz
            )
        } catch {
            if case LogitechHIDError.featureNotFound = error {
                pollingState = MouseDeviceState.PollingRateState(
                    isSupported: false,
                    currentHz: 0,
                    supportedHz: []
                )
            }
        }
        log("lsom/hid: polling rate state: \(pollingState.debugDescription)")

        // Onboard profiles state
        var profilesState: MouseDeviceState.OnboardProfilesState? = nil
        do {
            let supported = try await supportsOnboardProfiles()
            if supported {
                let enabled = try await onboardProfilesEnabled()
                profilesState = MouseDeviceState.OnboardProfilesState(
                    isSupported: true,
                    isEnabled: enabled
                )
            } else {
                profilesState = MouseDeviceState.OnboardProfilesState(
                    isSupported: false,
                    isEnabled: false
                )
            }
        } catch {
            profilesState = MouseDeviceState.OnboardProfilesState(
                isSupported: false,
                isEnabled: false
            )
        }

        // Button mapping state
        var buttonState: MouseDeviceState.ButtonMappingState? = nil
        do {
            let mappings = try await buttonMappings()
            buttonState = MouseDeviceState.ButtonMappingState(
                isSupported: !mappings.isEmpty,
                buttonCount: mappings.count,
                mappings: mappings
            )
        } catch {
            if case LogitechHIDError.featureNotFound = error {
                buttonState = MouseDeviceState.ButtonMappingState(
                    isSupported: false,
                    buttonCount: 0,
                    mappings: []
                )
            }
        }

        let state = MouseDeviceState(
            deviceName: name,
            batteryPercentage: battery,
            dpiState: dpiState,
            pollingRateState: pollingState,
            onboardProfilesState: profilesState,
            buttonMappingState: buttonState,
            timestamp: Date()
        )

        // Log the full state
        logService.logDeviceState(state)

        return state
    }

    // MARK: - HIDTransport Implementation

    var isReceiverAvailable: Bool {
        (try? ensureReceiverOpen()) != nil
    }

    func clearFeatureCache() {
        cachedDeviceIndex = nil
        cachedDeviceNameFeatureIndex = nil
        cachedDeviceName = nil
        cachedDPIFeatureIndex = nil
        cachedReportRateFeatureIndex = nil
        cachedExtendedReportRateFeatureIndex = nil
        cachedButtonsFeatureIndex = nil
        cachedOnboardProfilesFeatureIndex = nil
        cachedOnboardProfileSelection = nil
        // Clear controller caches
        dpiController.clearCache()
        pollingRateController.clearCache()
        buttonMappingController.clearCache()
        onboardProfilesController.clearCache()
    }

    func sendFAPCommand(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        functionIndex: UInt8,
        params: [UInt8]
    ) -> [UInt8]? {
        guard let receiver = try? ensureReceiverOpen() else { return nil }
        return sendFAPCommandInternal(
            device: receiver,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionIndex: functionIndex,
            params: params
        )
    }

    func getFeatureIndex(
        deviceIndex: UInt8,
        featureId: UInt16
    ) -> (featureIndex: UInt8, featureType: UInt8)? {
        guard let receiver = try? ensureReceiverOpen() else { return nil }
        return rootGetFeatureIndexFAP(
            device: receiver,
            deviceIndex: deviceIndex,
            featureId: featureId
        ).map { ($0.featureIndex, $0.featureType) }
    }

    func findActiveDeviceIndex() -> UInt8? {
        guard let receiver = try? ensureReceiverOpen() else { return nil }
        return findActiveDeviceIndexInternal(device: receiver)
    }

    // MARK: - Internal Helpers

    /// Finds the first active device index (1-6) that responds to feature queries.
    private func findActiveDeviceIndexInternal(
        device: IOHIDDevice
    ) -> UInt8? {
        if let cached = cachedDeviceIndex {
            return cached
        }

        // Try device indices 1-6, looking for any that responds
        for idx: UInt8 in 1...6 {
            // Try to get IFeatureSet which all HID++ 2.0 devices should have
            if rootGetFeatureIndexFAP(
                device: device,
                deviceIndex: idx,
                featureId: HIDPPConstants.featureSetFeatureId
            ) != nil {
                cachedDeviceIndex = idx
                log("lsom/hid: Found active device at index \(idx)")
                return idx
            }
        }
        return nil
    }

    /// Gets the feature index for Device Name, caching the result.
    private func getDeviceNameFeatureIndex(
        device: IOHIDDevice,
        deviceIndex: UInt8
    ) -> UInt8? {
        if let cached = cachedDeviceNameFeatureIndex {
            return cached
        }

        guard let (index, _, _) = rootGetFeatureIndexFAP(
            device: device,
            deviceIndex: deviceIndex,
            featureId: HIDPPConstants.deviceNameFeatureId
        ) else {
            return nil
        }

        cachedDeviceNameFeatureIndex = index
        return index
    }

    /// Gets the feature index for Adjustable DPI, caching the result.
    private func getDPIFeatureIndex(
        device: IOHIDDevice,
        deviceIndex: UInt8
    ) -> UInt8? {
        if let cached = cachedDPIFeatureIndex {
            return cached
        }

        guard let (index, _, _) = rootGetFeatureIndexFAP(
            device: device,
            deviceIndex: deviceIndex,
            featureId: HIDPPConstants.adjustableDPIFeatureId
        ) else {
            return nil
        }

        cachedDPIFeatureIndex = index
        return index
    }

    /// Gets the feature index for Report Rate, caching the result.
    private func getReportRateFeatureIndex(
        device: IOHIDDevice,
        deviceIndex: UInt8
    ) -> UInt8? {
        if let cached = cachedReportRateFeatureIndex {
            return cached
        }

        guard let (index, _, _) = rootGetFeatureIndexFAP(
            device: device,
            deviceIndex: deviceIndex,
            featureId: HIDPPConstants.reportRateFeatureId
        ) else {
            return nil
        }

        cachedReportRateFeatureIndex = index
        return index
    }

    /// Gets the feature index for Extended Adjustable Report Rate, caching the result.
    private func getExtendedReportRateFeatureIndex(
        device: IOHIDDevice,
        deviceIndex: UInt8
    ) -> UInt8? {
        if let cached = cachedExtendedReportRateFeatureIndex {
            return cached
        }

        guard let (index, _, _) = rootGetFeatureIndexFAP(
            device: device,
            deviceIndex: deviceIndex,
            featureId: HIDPPConstants.extendedAdjustableReportRateFeatureId
        ) else {
            return nil
        }

        cachedExtendedReportRateFeatureIndex = index
        return index
    }

    /// Gets the feature index for Special Keys & Mouse Buttons, caching the result.
    private func getButtonsFeatureIndex(
        device: IOHIDDevice,
        deviceIndex: UInt8
    ) -> UInt8? {
        if let cached = cachedButtonsFeatureIndex {
            return cached
        }

        guard let (index, _, _) = rootGetFeatureIndexFAP(
            device: device,
            deviceIndex: deviceIndex,
            featureId: HIDPPConstants.specialKeysButtonsFeatureId
        ) else {
            return nil
        }

        cachedButtonsFeatureIndex = index
        return index
    }

    /// Gets the feature index for Onboard Profiles, caching the result.
    private func getOnboardProfilesFeatureIndex(
        device: IOHIDDevice,
        deviceIndex: UInt8
    ) -> UInt8? {
        if let cached = cachedOnboardProfilesFeatureIndex {
            return cached
        }

        guard let (index, _, _) = rootGetFeatureIndexFAP(
            device: device,
            deviceIndex: deviceIndex,
            featureId: HIDPPConstants.onboardProfilesFeatureId
        ) else {
            return nil
        }

        cachedOnboardProfilesFeatureIndex = index
        return index
    }

    // MARK: - DPI (delegates to DPIController)

    func dpiSensorCount() async throws -> Int {
        try dpiController.sensorCount()
    }

    /// Synchronous DPI read for use on threads with run loops.
    func dpiSettingsSync(forSensor sensorIndex: Int) throws -> DPISensorInfo {
        try dpiController.settings(forSensor: sensorIndex)
    }

    func dpiSettings(forSensor sensorIndex: Int) async throws -> DPISensorInfo {
        try dpiController.settings(forSensor: sensorIndex)
    }

    func setDPI(_ dpi: Int, forSensor sensorIndex: Int) async throws {
        try dpiController.setDPI(dpi, forSensor: sensorIndex)
        settingsChangeSubject.send(.dpiChanged(dpi))
    }

    // MARK: Polling Rate (Feature 0x8060)

    /// Internal synchronous implementation for use on threads with run loops.
    func pollingRateInfoSync() throws -> PollingRateInfo {
        log("lsom/polling: pollingRateInfo ENTRY")
        let receiver = try ensureReceiverOpen()

        guard let deviceIndex = findActiveDeviceIndexInternal(device: receiver) else {
            log("lsom/polling: pollingRateInfo ERROR: No device found")
            throw LogitechHIDError.receiverNotFound
        }

        if let featureIndex = getReportRateFeatureIndex(
            device: receiver,
            deviceIndex: deviceIndex
        ) {
            log("lsom/polling: using STANDARD feature (0x8060), index=0x\(String(format: "%02X", featureIndex))")
            // Function 0x00: getReportRateList
            if let listResp = sendFAPCommandInternal(
                device: receiver,
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                functionIndex: 0x00,
                params: []
            ) {
                let listParams = Array(listResp.dropFirst(4))
                let listParamsStr = listParams.map { String(format: "0x%02X", $0) }.joined(separator: " ")
                log("lsom/polling: getReportRateList response params: [\(listParamsStr)]")

                let supportedMask = HIDPPParsing.parseReportRateMask(listParams)
                let supportedRates = HIDPPParsing.parseReportRateList(listParams)
                log("lsom/polling: Parsed supportedMask=0x\(String(format: "%04X", supportedMask)), supportedRates=\(supportedRates)")

                // Function 0x01: getReportRate
                if let rateResp = sendFAPCommandInternal(
                    device: receiver,
                    deviceIndex: deviceIndex,
                    featureIndex: featureIndex,
                    functionIndex: 0x01,
                    params: []
                ) {
                    let rateParams = Array(rateResp.dropFirst(4))
                    let rateParamsStr = rateParams.map { String(format: "0x%02X", $0) }.joined(separator: " ")
                    log("lsom/polling: getReportRate response params: [\(rateParamsStr)]")

                    if let currentHz = HIDPPParsing.parseCurrentReportRate(
                        rateParams,
                        supportedMask: supportedMask
                    ) {
                        log("lsom/polling: pollingRateInfo EXIT - currentHz=\(currentHz) (standard)")
                        return PollingRateInfo(
                            currentHz: currentHz,
                            supportedHz: supportedRates,
                            supportedMask: supportedMask,
                            featureId: HIDPPConstants.reportRateFeatureId
                        )
                    } else {
                        log("lsom/polling: parseCurrentReportRate returned nil")
                    }
                } else {
                    log("lsom/polling: getReportRate returned nil")
                }
            } else {
                log("lsom/polling: getReportRateList returned nil")
            }
        }

        if let featureIndex = getExtendedReportRateFeatureIndex(
            device: receiver,
            deviceIndex: deviceIndex
        ) {
            log("lsom/polling: using EXTENDED feature (0x8061), index=0x\(String(format: "%02X", featureIndex))")
            // Function 0x01: getReportRateList (extended)
            guard let listResp = sendFAPCommandInternal(
                device: receiver,
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                functionIndex: 0x01,
                params: []
            ) else {
                log("lsom/polling: Extended getReportRateList returned nil")
                throw LogitechHIDError.unexpectedResponse
            }

            let listParams = Array(listResp.dropFirst(4))
            let listParamsStr = listParams.map { String(format: "0x%02X", $0) }.joined(separator: " ")
            log("lsom/polling: Extended getReportRateList params: [\(listParamsStr)]")

            let supportedMask = HIDPPParsing.parseExtendedReportRateMask(listParams)
            let supportedRates = HIDPPParsing.parseExtendedReportRateList(fromMask: supportedMask)
            log("lsom/polling: Extended supportedMask=0x\(String(format: "%04X", supportedMask)), supportedRates=\(supportedRates)")

            // Function 0x02: getReportRate (extended)
            guard let rateResp = sendFAPCommandInternal(
                device: receiver,
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                functionIndex: 0x02,
                params: []
            ) else {
                log("lsom/polling: Extended getReportRate returned nil")
                throw LogitechHIDError.unexpectedResponse
            }

            let rateParams = Array(rateResp.dropFirst(4))
            let rateParamsStr = rateParams.map { String(format: "0x%02X", $0) }.joined(separator: " ")
            log("lsom/polling: Extended getReportRate params: [\(rateParamsStr)]")

            guard let currentHz = HIDPPParsing.parseExtendedCurrentReportRate(
                rateParams,
                supportedMask: supportedMask
            ) else {
                log("lsom/polling: parseExtendedCurrentReportRate returned nil")
                throw LogitechHIDError.unexpectedResponse
            }

            log("lsom/polling: pollingRateInfo EXIT - currentHz=\(currentHz) (extended)")
            return PollingRateInfo(
                currentHz: currentHz,
                supportedHz: supportedRates,
                supportedMask: supportedMask,
                featureId: HIDPPConstants.extendedAdjustableReportRateFeatureId
            )
        }

        throw LogitechHIDError.featureNotFound(featureId: HIDPPConstants.reportRateFeatureId)
    }

    func pollingRateInfo() async throws -> PollingRateInfo {
        try pollingRateInfoSync()
    }

    func setPollingRate(_ rateHz: Int) async throws {
        log("lsom/polling: setPollingRate ENTRY - requested=\(rateHz) Hz")
        let receiver = try ensureReceiverOpen()
        log("lsom/polling: Receiver opened successfully")

        guard let deviceIndex = findActiveDeviceIndexInternal(device: receiver) else {
            log("lsom/polling: ERROR: No active device found")
            throw LogitechHIDError.receiverNotFound
        }
        log("lsom/polling: Found device at index \(deviceIndex)")

        // Prefer extended info if available, otherwise standard.
        // We still record whether both features exist so we can fall back.
        let hasStandard = getReportRateFeatureIndex(device: receiver, deviceIndex: deviceIndex) != nil
        let hasExtended = getExtendedReportRateFeatureIndex(device: receiver, deviceIndex: deviceIndex) != nil
        log("lsom/polling: Feature support - standard(0x8060)=\(hasStandard ? "YES" : "NO"), extended(0x8061)=\(hasExtended ? "YES" : "NO")")

        let info: PollingRateInfo
        do {
            log("lsom/polling: Reading current polling rate info...")
            info = try await pollingRateInfo()
            log("lsom/polling: Current info - currentHz=\(info.currentHz), featureId=0x\(String(format: "%04X", info.featureId)), supportedMask=0x\(String(format: "%04X", info.supportedMask))")
        } catch {
            log("lsom/polling: ERROR: pollingRateInfo failed - \(error)")
            throw error
        }

        // Some devices require onboard profiles to be disabled before the rate can change.
        if let supported = try? await supportsOnboardProfiles(),
           supported,
           let enabled = try? await onboardProfilesEnabled(),
           enabled {
            log("lsom/polling: Onboard profiles enabled, disabling them first...")
            try? await setOnboardProfilesEnabled(false)
        }

        // Helper to verify after any attempt.
        func verifyApplied() async -> Bool {
            log("lsom/polling: Verifying applied rate...")
            if let refreshed = try? await pollingRateInfo() {
                log("lsom/polling: Read back currentHz=\(refreshed.currentHz) (expected \(rateHz))")
                if refreshed.currentHz == rateHz {
                    log("lsom/polling: SUCCESS: Rate verified as \(rateHz) Hz")
                    settingsChangeSubject.send(.pollingRateChanged(rateHz))
                    return true
                }
                log("lsom/polling: MISMATCH: Device reports \(refreshed.currentHz) Hz, we requested \(rateHz) Hz")
            } else {
                log("lsom/polling: ERROR: Could not read polling rate after set")
            }
            return false
        }

        // Try standard feature first if it is the one we queried, but be ready to fall back.
        log("lsom/polling: Checking if standard feature should be used (featureId=0x\(String(format: "%04X", info.featureId)))")
        if info.featureId == HIDPPConstants.reportRateFeatureId, hasStandard {
            log("lsom/polling: Using STANDARD feature (0x8060)")
            guard let featureIndex = getReportRateFeatureIndex(
                device: receiver,
                deviceIndex: deviceIndex
            ) else {
                log("lsom/polling: ERROR: Could not get standard feature index")
                throw LogitechHIDError.featureNotFound(featureId: HIDPPConstants.reportRateFeatureId)
            }
            log("lsom/polling: Standard feature index = 0x\(String(format: "%02X", featureIndex))")

            guard let msValue = HIDPPParsing.reportRateSettingValue(
                forHz: rateHz,
                supportedMask: info.supportedMask
            ) else {
                log("lsom/polling: ERROR: No valid ms value for \(rateHz) Hz with mask 0x\(String(format: "%04X", info.supportedMask))")
                throw LogitechHIDError.unexpectedResponse
            }
            log("lsom/polling: Computed msValue=\(msValue) for \(rateHz) Hz")

            let bitIndex = UInt8(msValue - 1)           // bit index if needed
            let mask16 = UInt16(1 << bitIndex)
            let mask8 = UInt8(mask16 & 0xFF)
            let maskLE: [UInt8] = [mask8, UInt8((mask16 >> 8) & 0xFF)]

            let candidates: [(label: String, params: [UInt8])] = [
                ("ms", [msValue]),
                ("bit", [bitIndex]),
                ("mask8", [mask8]),          // single-byte mask
                ("mask16", maskLE)           // little-endian 16-bit mask
            ]

            for candidate in candidates {
                let paramsString = candidate.params
                    .map { String(format: "0x%02X", $0) }
                    .joined(separator: " ")
                log("lsom/polling: Trying candidate '\(candidate.label)' with params [\(paramsString)]")

                guard let response = sendFAPCommandInternal(
                    device: receiver,
                    deviceIndex: deviceIndex,
                    featureIndex: featureIndex,
                    functionIndex: 0x02,
                    params: candidate.params
                ) else {
                    log("lsom/polling: No response for candidate '\(candidate.label)'")
                    continue
                }

                let respStr = response.map { String(format: "0x%02X", $0) }.joined(separator: " ")
                log("lsom/polling: Got response for '\(candidate.label)': [\(respStr)]")

                if let errorCode = fapErrorCode(from: response) {
                    log("lsom/polling: Candidate '\(candidate.label)' rejected with error 0x\(String(format: "%02X", errorCode))")
                    continue
                }

                log("lsom/polling: Candidate '\(candidate.label)' accepted, waiting 100ms then verifying...")
                try? await Task.sleep(for: .milliseconds(100))
                if await verifyApplied() {
                    log("lsom/polling: setPollingRate EXIT - SUCCESS with standard feature")
                    return
                }
            }
            log("lsom/polling: All standard feature candidates failed")
        }

        // Fallback to extended feature if available.
        log("lsom/polling: Trying EXTENDED feature (0x8061)...")
        if hasExtended {
            log("lsom/polling: Using EXTENDED feature (0x8061)")
            guard let featureIndex = getExtendedReportRateFeatureIndex(
                device: receiver,
                deviceIndex: deviceIndex
            ) else {
                log("lsom/polling: ERROR: Could not get extended feature index")
                throw LogitechHIDError.featureNotFound(featureId: HIDPPConstants.extendedAdjustableReportRateFeatureId)
            }
            log("lsom/polling: Extended feature index = 0x\(String(format: "%02X", featureIndex))")

            // Fetch extended mask directly (don't rely on standard info mask).
            guard let listResp = sendFAPCommandInternal(
                device: receiver,
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                functionIndex: 0x01,
                params: []
            ) else {
                log("lsom/polling: ERROR: No response to extended list query")
                throw LogitechHIDError.unexpectedResponse
            }

            let listParams = Array(listResp.dropFirst(4))
            let supportedMask = HIDPPParsing.parseExtendedReportRateMask(listParams)
            log("lsom/polling: Extended supportedMask = 0x\(String(format: "%04X", supportedMask))")

            guard let indexValue = HIDPPParsing.extendedReportRateSettingValue(
                forHz: rateHz,
                supportedMask: supportedMask
            ) else {
                log("lsom/polling: ERROR: No valid index for \(rateHz) Hz with extended mask")
                throw LogitechHIDError.unexpectedResponse
            }
            log("lsom/polling: Extended indexValue=\(indexValue) for \(rateHz) Hz")

            log("lsom/polling: Sending setReportRate command with index \(indexValue)")
            guard let response = sendFAPCommandInternal(
                device: receiver,
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                functionIndex: 0x03,
                params: [indexValue]
            ) else {
                log("lsom/polling: ERROR: No response to set command")
                throw LogitechHIDError.unexpectedResponse
            }

            let respStr = response.map { String(format: "0x%02X", $0) }.joined(separator: " ")
            log("lsom/polling: Extended set response: [\(respStr)]")

            if let errorCode = fapErrorCode(from: response) {
                log("lsom/polling: Extended set rejected with error 0x\(String(format: "%02X", errorCode))")
                throw LogitechHIDError.settingRejected(errorCode: errorCode)
            }

            log("lsom/polling: Extended set accepted, waiting 100ms then verifying...")
            try? await Task.sleep(for: .milliseconds(100))
            if await verifyApplied() {
                log("lsom/polling: setPollingRate EXIT - SUCCESS with extended feature")
                return
            }
        } else {
            log("lsom/polling: Extended feature not available")
        }

        // If we reach here, we were unable to verify the change.
        log("lsom/polling: setPollingRate EXIT - FAILED to verify change")
        throw LogitechHIDError.unexpectedResponse
    }

    // MARK: Button Mapping (Feature 0x1B04)

    func buttonMappings() async throws -> [ButtonMapping] {
        let receiver = try ensureReceiverOpen()

        guard let deviceIndex = findActiveDeviceIndexInternal(device: receiver) else {
            throw LogitechHIDError.receiverNotFound
        }

        guard let featureIndex = getButtonsFeatureIndex(
            device: receiver,
            deviceIndex: deviceIndex
        ) else {
            throw LogitechHIDError.featureNotFound(featureId: HIDPPConstants.specialKeysButtonsFeatureId)
        }

        // Function 0x00: getCount
        guard let countResp = sendFAPCommandInternal(
            device: receiver,
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
            // Function 0x10: getCidInfo
            guard let infoResp = sendFAPCommandInternal(
                device: receiver,
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

            // Function 0x20: getCidReporting
            var diverted = false
            var remappedTo: Int? = nil

            if let reportResp = sendFAPCommandInternal(
                device: receiver,
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

    func remapButton(controlId: Int, to targetCID: Int?) async throws {
        let receiver = try ensureReceiverOpen()

        guard let deviceIndex = findActiveDeviceIndexInternal(device: receiver) else {
            throw LogitechHIDError.receiverNotFound
        }

        guard let featureIndex = getButtonsFeatureIndex(
            device: receiver,
            deviceIndex: deviceIndex
        ) else {
            throw LogitechHIDError.featureNotFound(featureId: HIDPPConstants.specialKeysButtonsFeatureId)
        }

        let cidHi = UInt8((controlId >> 8) & 0xFF)
        let cidLo = UInt8(controlId & 0xFF)
        let target = targetCID ?? 0
        let targetHi = UInt8((target >> 8) & 0xFF)
        let targetLo = UInt8(target & 0xFF)

        // Function 0x30: setCidReporting
        // params: [cidHi, cidLo, flags, remapHi, remapLo]
        // flags: bit 0 = persist
        let flags: UInt8 = 0x01  // persist

        guard sendFAPCommandInternal(
            device: receiver,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionIndex: 0x03,
            params: [cidHi, cidLo, flags, targetHi, targetLo]
        ) != nil else {
            throw LogitechHIDError.unexpectedResponse
        }

        log("lsom/hid: Remapped button \(String(format: "0x%04X", controlId)) to \(targetCID.map { String(format: "0x%04X", $0) } ?? "default")")
    }

    func setButtonDivert(controlId: Int, diverted: Bool) async throws {
        let receiver = try ensureReceiverOpen()

        guard let deviceIndex = findActiveDeviceIndexInternal(device: receiver) else {
            throw LogitechHIDError.receiverNotFound
        }

        guard let featureIndex = getButtonsFeatureIndex(
            device: receiver,
            deviceIndex: deviceIndex
        ) else {
            throw LogitechHIDError.featureNotFound(featureId: HIDPPConstants.specialKeysButtonsFeatureId)
        }

        let cidHi = UInt8((controlId >> 8) & 0xFF)
        let cidLo = UInt8(controlId & 0xFF)

        // Function 0x30: setCidReporting
        // params: [cidHi, cidLo, flags, 0, 0]
        // flags: bit 0 = persist, bit 1 = divert
        var flags: UInt8 = 0x01  // persist
        if diverted {
            flags |= 0x02  // divert
        }

        guard sendFAPCommandInternal(
            device: receiver,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionIndex: 0x03,
            params: [cidHi, cidLo, flags, 0, 0]
        ) != nil else {
            throw LogitechHIDError.unexpectedResponse
        }

        log("lsom/hid: Set button \(String(format: "0x%04X", controlId)) divert=\(diverted)")
    }

    // MARK: Device Persistence (Feature 0x8100)

    func supportsOnboardProfiles() async throws -> Bool {
        let receiver = try ensureReceiverOpen()

        guard let deviceIndex = findActiveDeviceIndexInternal(device: receiver) else {
            throw LogitechHIDError.receiverNotFound
        }

        let supported = getOnboardProfilesFeatureIndex(
            device: receiver,
            deviceIndex: deviceIndex
        ) != nil
        log("lsom/hid: Onboard profiles supported: \(supported)")
        return supported
    }

    func onboardProfilesEnabled() async throws -> Bool {
        let receiver = try ensureReceiverOpen()

        guard let deviceIndex = findActiveDeviceIndexInternal(device: receiver) else {
            throw LogitechHIDError.receiverNotFound
        }

        guard let featureIndex = getOnboardProfilesFeatureIndex(
            device: receiver,
            deviceIndex: deviceIndex
        ) else {
            throw LogitechHIDError.featureNotFound(featureId: HIDPPConstants.onboardProfilesFeatureId)
        }

        // Function 0x20: getOnboardProfilesMode
        guard let resp = sendFAPCommandInternal(
            device: receiver,
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
        if enabled {
            // Function 0x40: getActiveProfile
            if let activeResp = sendFAPCommandInternal(
                device: receiver,
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                functionIndex: 0x04,
                params: []
            ) {
                let activeParams = Array(activeResp.dropFirst(4))
                if activeParams.count >= 2 {
                    cachedOnboardProfileSelection = Array(activeParams.prefix(2))
                }
            }
        }

        log("lsom/hid: Onboard profiles enabled: \(enabled)")
        return enabled
    }

    func setOnboardProfilesEnabled(_ enabled: Bool) async throws {
        let receiver = try ensureReceiverOpen()

        guard let deviceIndex = findActiveDeviceIndexInternal(device: receiver) else {
            throw LogitechHIDError.receiverNotFound
        }

        guard let featureIndex = getOnboardProfilesFeatureIndex(
            device: receiver,
            deviceIndex: deviceIndex
        ) else {
            throw LogitechHIDError.featureNotFound(featureId: HIDPPConstants.onboardProfilesFeatureId)
        }

        let modeByte: UInt8 = enabled ? 0x01 : 0x02

        // Function 0x10: setOnboardProfilesMode
        guard sendFAPCommandInternal(
            device: receiver,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionIndex: 0x01,
            params: [modeByte]
        ) != nil else {
            throw LogitechHIDError.unexpectedResponse
        }

        if enabled, let selection = cachedOnboardProfileSelection, selection.count >= 2 {
            _ = sendFAPCommandInternal(
                device: receiver,
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                functionIndex: 0x03,
                params: Array(selection.prefix(2))
            )
        }

        log("lsom/hid: Set onboard profiles enabled=\(enabled)")
    }

    // MARK: - Receiver management

    /// Ensures we have an open IOHIDDevice for the Logitech receiver.
    private func ensureReceiverOpen() throws -> IOHIDDevice {
        // In preview mode, HID is not initialized - report as not found
        guard isHIDInitialized else {
            throw LogitechHIDError.receiverNotFound
        }

        if let receiver {
            return receiver
        }

        guard
            let deviceSet = IOHIDManagerCopyDevices(manager)
                as? Set<IOHIDDevice>,
            !deviceSet.isEmpty
        else {
            throw LogitechHIDError.receiverNotFound
        }

        guard
            let found = deviceSet.first(where: { device in
                let vid = intProperty(device, key: kIOHIDVendorIDKey as CFString)
                let pid = intProperty(
                    device,
                    key: kIOHIDProductIDKey as CFString
                )
                let usagePage = intProperty(
                    device,
                    key: kIOHIDPrimaryUsagePageKey as CFString
                )
                let usage = intProperty(
                    device,
                    key: kIOHIDPrimaryUsageKey as CFString
                )
                return vid == HIDPPConstants.logitechVendorId
                    && pid == HIDPPConstants.unifyingReceiverPid
                    && usagePage == HIDPPConstants.hidppUsagePage
                    && usage == HIDPPConstants.hidppUsage
            })
        else {
            throw LogitechHIDError.receiverNotFound
        }

        let openDeviceResult = IOHIDDeviceOpen(
            found,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        guard openDeviceResult == kIOReturnSuccess else {
            if openDeviceResult == kIOReturnNotPrivileged {
                throw LogitechHIDError.permissionDenied
            } else {
                throw LogitechHIDError.deviceOpenFailed(code: Int32(openDeviceResult))
            }
        }

        receiver = found
        return found
    }

    /// Root.GetFeature(featureID) -> (featureIndex, featureType)
    private func rootGetFeature(
        device: IOHIDDevice,
        deviceIndex: UInt8,
        featureId: UInt16
    ) -> (UInt8, UInt8)? {
        let params: [UInt8] = [
            UInt8((featureId >> 8) & 0xFF),
            UInt8(featureId & 0xFF),
        ]

        guard
            let response = sendFAP(
                device: device,
                deviceIndex: deviceIndex,
                featureIndex: 0x00,  // Root is always at index 0
                // HID++ Root.GetFeature uses function index 0x00.
                functionIndex: 0x00,
                params: params
            )
        else {
            return nil
        }

        guard response.params.count >= 2 else { return nil }
        let featureIndex = response.params[0]
        let featureType = response.params[1]
        // Per spec, featureIndex 0 means "not found".
        if featureIndex == 0 {
            return nil
        }
        return (featureIndex, featureType)
    }

    /// IFeatureSet.GetCount() for a given featureSetIndex.
    private func featureSetGetCount(
        device: IOHIDDevice,
        deviceIndex: UInt8,
        featureSetIndex: UInt8
    ) -> UInt8? {
        guard
            let response = sendFAP(
                device: device,
                deviceIndex: deviceIndex,
                featureIndex: featureSetIndex,
                functionIndex: 0x00, // GetCount
                params: []
            )
        else {
            return nil
        }
        guard let count = response.params.first else { return nil }
        return count
    }

    /// IFeatureSet.GetFeatureID(featureIndex) -> (featureId, featureType)
    private func featureSetGetFeatureID(
        device: IOHIDDevice,
        deviceIndex: UInt8,
        featureSetIndex: UInt8,
        tableIndex: UInt8
    ) -> (UInt16, UInt8)? {
        guard
            let response = sendFAP(
                device: device,
                deviceIndex: deviceIndex,
                featureIndex: featureSetIndex,
                functionIndex: 0x01, // GetFeatureID
                params: [tableIndex]
            )
        else {
            return nil
        }

        guard response.params.count >= 3 else { return nil }
        let msb = UInt16(response.params[0])
        let lsb = UInt16(response.params[1])
        let featureId = (msb << 8) | lsb
        let featureType = response.params[2]
        return (featureId, featureType)
    }

    /// Dump all features advertised by IFeatureSet.
    private func dumpFeatureSet(
        device: IOHIDDevice,
        deviceIndex: UInt8,
        featureSetIndex: UInt8
    ) {
        guard
            let count = featureSetGetCount(
                device: device,
                deviceIndex: deviceIndex,
                featureSetIndex: featureSetIndex
            )
        else {
            log("lsom/hid: FeatureSet.GetCount failed")
            return
        }

        log(
            String(
                format:
                    "lsom/hid: FeatureSet reports %u features (excluding root)",
                count
            )
        )

        if count == 0 {
            return
        }

        for idx in 1...Int(count) {
            let tableIndex = UInt8(idx)
            guard
                let (featureId, featureType) = featureSetGetFeatureID(
                    device: device,
                    deviceIndex: deviceIndex,
                    featureSetIndex: featureSetIndex,
                    tableIndex: tableIndex
                )
            else {
                log(
                    String(
                        format:
                            "lsom/hid:   idx=%3d -> GetFeatureID failed",
                        idx
                    )
                )
                continue
            }

            let name = featureName(for: featureId) ?? "unknown"

            log(
                String(
                    format:
                        "lsom/hid:   idx=%3d featureId=0x%04X type=0x%02X (%@)",
                    idx,
                    featureId,
                    featureType,
                    name
                )
            )
        }
    }

    /// Minimal mapping of common HID++ feature IDs to human‑readable names.
    private func featureName(for featureId: UInt16) -> String? {
        switch featureId {
        case 0x0000: return "ROOT"
        case 0x0001: return "FEATURE SET"
        case 0x0003: return "DEVICE FW VERSION"
        case 0x0005: return "DEVICE NAME"
        case 0x0020: return "RESET"
        case 0x1000: return "BATTERY STATUS"
        case 0x1004: return "UNIFIED BATTERY"
        case 0x1D4B: return "WIRELESS DEVICE STATUS"
        case 0x1B04: return "REPROG CONTROLS V4"
        case 0x2201: return "ADJUSTABLE DPI"
        case 0x2100: return "VERTICAL SCROLLING"
        case 0x2110: return "SMART SHIFT"
        case 0x2121: return "HIRES WHEEL"
        default:
            return nil
        }
    }

    /// Send one HID++ FAP command and synchronously read back the response.
    private func sendFAP(
        device: IOHIDDevice,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        functionIndex: UInt8,
        params: [UInt8]
    ) -> FAPResponse? {
        // HID++ 2.0 encodes the 4‑bit function index in the high nibble
        // and the 4‑bit software id in the low nibble.
        let softwareId: UInt8 = 0x01
        let funcIndexClientId =
            ((functionIndex & 0x0F) << 4) | (softwareId & 0x0F)

        var tx = [UInt8](
            repeating: 0,
            count: Int(HIDPPConstants.totalReportLength)
        )
        // Byte 0: report ID (0x11 for HID++ long report).
        tx[0] = UInt8(HIDPPConstants.longReportId)
        // Byte 1: device index.
        tx[1] = deviceIndex
        // Byte 2: feature index.
        tx[2] = featureIndex
        // Byte 3: funcindex_clientid.
        tx[3] = funcIndexClientId

        for (i, byte) in params.prefix(HIDPPConstants.maxParamCount).enumerated() {
            tx[4 + i] = byte
        }

        log(
            String(
                format:
                    "lsom/hid: FAP tx devIdx=0x%02X featIdx=0x%02X funcIdx=0x%X swId=0x%X raw=0x%02X params=%@",
                deviceIndex,
                featureIndex,
                functionIndex,
                softwareId,
                funcIndexClientId,
                params
                    .map { String(format: "0x%02X", $0) }
                    .joined(separator: " ")
            )
        )

        let setResult: IOReturn = tx.withUnsafeBytes { rawBuffer in
            let ptr = rawBuffer.bindMemory(to: UInt8.self).baseAddress!
            return IOHIDDeviceSetReport(
                device,
                // HID++ on Unifying uses OUTPUT reports for FAP.
                kIOHIDReportTypeOutput,
                HIDPPConstants.longReportId,
                ptr,
                HIDPPConstants.totalReportLength
            )
        }

        if setResult != kIOReturnSuccess {
            log(
                String(
                    format:
                        "lsom/hid: IOHIDDeviceSetReport FAP(devIdx=0x%02X featIdx=0x%02X func=0x%02X) failed: 0x%08X",
                    deviceIndex,
                    featureIndex,
                    functionIndex,
                    setResult
                )
            )
            return nil
        }

        var rx = [UInt8](
            repeating: 0,
            count: Int(HIDPPConstants.totalReportLength)
        )
        var length = HIDPPConstants.totalReportLength

        let getResult: IOReturn = rx.withUnsafeMutableBytes { rawBuffer in
            let ptr = rawBuffer.bindMemory(to: UInt8.self).baseAddress!
            return IOHIDDeviceGetReport(
                device,
                // Response comes back as an INPUT report with the same ID.
                kIOHIDReportTypeInput,
                HIDPPConstants.longReportId,
                ptr,
                &length
            )
        }

        if getResult != kIOReturnSuccess {
            log(
                String(
                    format:
                        "lsom/hid: IOHIDDeviceGetReport FAP(devIdx=0x%02X featIdx=0x%02X func=0x%02X) failed: 0x%08X",
                    deviceIndex,
                    featureIndex,
                    functionIndex,
                    getResult
                )
            )
            return nil
        }

        // Expect at least report ID + devIdx + featIdx + funcindex_clientid.
        guard length >= 4 else {
            log("lsom/hid: FAP response too short (\(length) bytes)")
            return nil
        }

        // Byte 0 is report ID; the rest mirrors what we sent.
        let respDeviceIndex = rx[1]
        let respFeatureIndex = rx[2]
        let respFuncIndexClientId = rx[3]
        let respFunctionIndex = respFuncIndexClientId & 0x0F
        let respClientId = respFuncIndexClientId >> 4

        let paramsCount = Int(length) - 4
        let respParams = paramsCount > 0
            ? Array(rx[4..<(4 + paramsCount)])
            : []

        return FAPResponse(
            deviceIndex: respDeviceIndex,
            featureIndex: respFeatureIndex,
            functionIndex: respFunctionIndex,
            clientId: respClientId,
            params: respParams
        )
    }

    // MARK: - HID++ 1.0 RAP helpers (battery etc.)

    /// Log raw HID++ 1.0 battery register values for each potential
    /// device index. This mirrors what the kernel's hid-logitech-hidpp
    /// driver does with HIDPP_GET_REGISTER on registers 0x07 and 0x0D.
    private func logHIDPP10BatteryState(receiver: IOHIDDevice) {
        log("lsom/hid: === HID++ 1.0 RAP battery debug start ===")

        for deviceIndex in 1...6 {
            let dIdx = UInt8(deviceIndex)
            log(
                String(
                    format: "lsom/hid: RAP battery probe devIdx=0x%02X", dIdx
                )
            )

            // Try to enable battery reporting on this device index.
            if var general = rapGetRegister(
                device: receiver,
                deviceIndex: dIdx,
                register: HIDPPConstants.rapRegEnableReports
            ) {
                while general.count < 3 {
                    general.append(0)
                }
                let before = general[0]
                general[0] = before | 0x10  // enable battery bit
                if before != general[0] {
                    _ = rapSetRegister(
                        device: receiver,
                        deviceIndex: dIdx,
                        register: HIDPPConstants.rapRegEnableReports,
                        params: Array(general.prefix(3))
                    )
                    log(
                        String(
                            format:
                                "lsom/hid:   devIdx=0x%02X enabled battery reporting (reg0 0x%02X -> 0x%02X)",
                            dIdx,
                            before,
                            general[0]
                        )
                    )
                }
            }

            guard
                let status = rapGetRegister(
                    device: receiver,
                    deviceIndex: dIdx,
                    register: HIDPPConstants.rapRegBatteryStatus
                )
            else {
                continue
            }

            let levelCode: UInt8 = status.count > 0 ? status[0] : 0
            let statusCode: UInt8 = status.count > 1 ? status[1] : 0
            let percentFromStatus = hidpp10BatteryPercentFromStatus(
                levelCode: levelCode
            )
            let statusText = hidpp10BatteryStatusText(from: statusCode)

                        log(
                String(
                    format:
                        "lsom/hid:   devIdx=0x%02X reg0x07 levelCode=0x%02X statusCode=0x%02X -> approx %d%% (%@)",
                    dIdx,
                    levelCode,
                    statusCode,
                    percentFromStatus,
                    statusText
                )
            )

            if let mileage = rapGetRegister(
                device: receiver,
                deviceIndex: dIdx,
                register: HIDPPConstants.rapRegBatteryMileage
            ) {
                let mileagePercent: UInt8 = mileage.count > 0
                    ? mileage[0]
                    : 0
                let mileageStatus: UInt8 = mileage.count > 2
                    ? mileage[2]
                    : 0
                let mileageStatusText = hidpp10BatteryMileageStatusText(
                    from: mileageStatus
                )
                log(
                    String(
                        format:
                            "lsom/hid:   devIdx=0x%02X reg0x0D mileage=%u%% flags=0x%02X (%@)",
                        dIdx,
                        mileagePercent,
                        mileageStatus,
                        mileageStatusText
                    )
                )
            }
        }

            log("lsom/hid: === HID++ 1.0 RAP battery debug end ===")
    }

    /// Convenience GET_REGISTER wrapper.
    private func rapGetRegister(
        device: IOHIDDevice,
        deviceIndex: UInt8,
        register: UInt8
    ) -> [UInt8]? {
        guard
            let response = sendRAPShort(
                device: device,
                deviceIndex: deviceIndex,
                subId: HIDPPConstants.rapGetRegister,
                register: register,
                params: []
            )
        else {
            return nil
        }
        if response.isError {
            if let code = response.errorCode {
                log(
                    String(
                        format:
                            "lsom/hid:   RAP GET_REGISTER devIdx=0x%02X reg=0x%02X error=0x%02X",
                        deviceIndex,
                        register,
                        code
                    )
                )
            }
            return nil
        }
        return response.params
    }

    /// Convenience SET_REGISTER wrapper.
    private func rapSetRegister(
        device: IOHIDDevice,
        deviceIndex: UInt8,
        register: UInt8,
        params: [UInt8]
    ) -> Bool {
        guard
            let response = sendRAPShort(
                device: device,
                deviceIndex: deviceIndex,
                subId: HIDPPConstants.rapSetRegister,
                register: register,
                params: params
            )
        else {
            return false
        }
        if response.isError {
            if let code = response.errorCode {
                log(
                    String(
                        format:
                            "lsom/hid:   RAP SET_REGISTER devIdx=0x%02X reg=0x%02X error=0x%02X",
                        deviceIndex,
                        register,
                        code
                    )
                )
            }
            return false
        }
        return true
    }

    /// Send a HID++ 1.0 short (RAP) message and read the response.
    private func sendRAPShort(
        device: IOHIDDevice,
        deviceIndex: UInt8,
        subId: UInt8,
        register: UInt8,
        params: [UInt8]
    ) -> RAPResponse? {
        var tx = [UInt8](repeating: 0, count: 7)
        tx[0] = UInt8(HIDPPConstants.shortReportId)  // report ID
        tx[1] = deviceIndex
        tx[2] = subId
        tx[3] = register
        for (i, byte) in params.prefix(3).enumerated() {
            tx[4 + i] = byte
        }

        log(
            String(
                format:
                    "lsom/hid: RAP tx devIdx=0x%02X subId=0x%02X reg=0x%02X params=%@",
                deviceIndex,
                subId,
                register,
                params
                    .map { String(format: "0x%02X", $0) }
                    .joined(separator: " ")
            )
        )

        let setResult: IOReturn = tx.withUnsafeBytes { rawBuffer in
            let ptr = rawBuffer.bindMemory(to: UInt8.self).baseAddress!
            return IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                HIDPPConstants.shortReportId,
                ptr,
                tx.count
            )
        }

        if setResult != kIOReturnSuccess {
            log(
                String(
                    format:
                        "lsom/hid: IOHIDDeviceSetReport RAP(devIdx=0x%02X subId=0x%02X reg=0x%02X) failed: 0x%08X",
                    deviceIndex,
                    subId,
                    register,
                    setResult
                )
            )
            return nil
        }

        var rx = [UInt8](repeating: 0, count: 7)
        var length: CFIndex = 7

        let getResult: IOReturn = rx.withUnsafeMutableBytes { rawBuffer in
            let ptr = rawBuffer.bindMemory(to: UInt8.self).baseAddress!
            return IOHIDDeviceGetReport(
                device,
                kIOHIDReportTypeInput,
                HIDPPConstants.shortReportId,
                ptr,
                &length
            )
        }

        if getResult != kIOReturnSuccess {
            log(
                String(
                    format:
                        "lsom/hid: IOHIDDeviceGetReport RAP(devIdx=0x%02X subId=0x%02X reg=0x%02X) failed: 0x%08X",
                    deviceIndex,
                    subId,
                    register,
                    getResult
                )
            )
            return nil
        }

        guard length >= 4 else {
            log("lsom/hid: RAP response too short (\(length) bytes)")
            return nil
        }

        let respDeviceIndex = rx[1]
        let respSubId = rx[2]
        let respRegister = rx[3]
        let paramsCount = Int(length) - 4
        let respParams = paramsCount > 0
            ? Array(rx[4..<(4 + paramsCount)])
            : []

        let isError = respSubId == HIDPPConstants.rapErrorSubId
        let errorCode: UInt8? = isError ? respParams.first : nil

        if isError {
            log(
                String(
                    format:
                        "lsom/hid: RAP rx ERROR devIdx=0x%02X reg=0x%02X code=0x%02X",
                    respDeviceIndex,
                    respRegister,
                    errorCode ?? 0
                )
            )
        } else {
            log(
                String(
                    format:
                        "lsom/hid: RAP rx devIdx=0x%02X subId=0x%02X reg=0x%02X params=%@",
                    respDeviceIndex,
                    respSubId,
                    respRegister,
                    respParams
                        .map { String(format: "0x%02X", $0) }
                        .joined(separator: " ")
                )
            )
        }

        return RAPResponse(
            deviceIndex: respDeviceIndex,
            subId: respSubId,
            register: respRegister,
            params: respParams,
            isError: isError,
            errorCode: errorCode
        )
    }

    /// Approximate battery percentage from HID++ 1.0 status register.
    private func hidpp10BatteryPercentFromStatus(levelCode: UInt8) -> Int {
        switch levelCode {
        case 1...2: return 5
        case 3...4: return 20
        case 5...6: return 55
        case 7: return 90
        default: return 0
        }
    }

    /// Human‑readable status for HID++ 1.0 battery status register.
    private func hidpp10BatteryStatusText(from statusCode: UInt8) -> String {
        switch statusCode {
        case 0x00: return "discharging"
        case 0x01: return "recharging"
        case 0x02: return "charge completed"
        case 0x03: return "error"
        default: return "unknown"
        }
    }

    /// Human‑readable flags for HID++ 1.0 battery mileage register.
    private func hidpp10BatteryMileageStatusText(from flags: UInt8) -> String {
        var parts: [String] = []
        if flags & 0x01 != 0 { parts.append("rechargeable") }
        if flags & 0x02 != 0 { parts.append("replaceable") }
        if flags & 0x04 != 0 { parts.append("single‑use") }
        if parts.isEmpty { return "none" }
        return parts.joined(separator: ", ")
    }

    // MARK: - Small helpers

    private func intProperty(_ device: IOHIDDevice, key: CFString) -> Int {
        guard let value = IOHIDDeviceGetProperty(device, key),
              let cfNumber = value as? NSNumber else {
            return 0
        }
        return cfNumber.intValue
    }

    private func stringProperty(_ device: IOHIDDevice, key: CFString) -> String?
    {
        guard let value = IOHIDDeviceGetProperty(device, key) else {
            return nil
        }
        if CFGetTypeID(value) == CFStringGetTypeID() {
            return value as? String
        }
        return nil
    }
}
