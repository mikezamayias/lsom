//
//  HIDPPParsing.swift
//  lsom
//
//  Pure helpers for decoding HID++ responses.
//  These are designed to be easily unit tested.
//

import Foundation

enum HIDPPParsing {

    // MARK: - Battery Parsing

    /// Parse Unified Battery GET_STATUS response and return the
    /// state of charge in percent (0–100) when possible.
    ///
    /// Expected layout (20‑byte long report):
    /// [0]=0x11, [1]=deviceIndex, [2]=featureIndex,
    /// [3]=func|sw, [4]=state_of_charge, [5]=flags, ...
    static func parseUnifiedBatteryStatus(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 5 else { return nil }
        // Basic sanity: HID++ long report id.
        guard bytes[0] == 0x11 else { return nil }
        let stateOfCharge = Int(bytes[4])
        guard (0...100).contains(stateOfCharge) else { return nil }
        return stateOfCharge
    }

    /// Parse Root.GetFeature response for a given device index and
    /// return (featureIndex, featureType) if present.
    ///
    /// Expected layout (20‑byte long report):
    /// [0]=0x11, [1]=deviceIndex, [2]=0x00 (root index),
    /// [3]=func|sw with response bit set,
    /// [4]=featureIndex, [5]=featureType, ...
    static func parseRootGetFeature(
        _ bytes: [UInt8],
        expectedDeviceIndex: UInt8
    ) -> (index: UInt8, type: UInt8)? {
        guard bytes.count >= 6 else { return nil }
        guard bytes[0] == 0x11, bytes[1] == expectedDeviceIndex else {
            return nil
        }
        let featureIndex = bytes[4]
        let featureType = bytes[5]
        // Per spec, index 0 is reserved for Root / "not found".
        guard featureIndex != 0 else { return nil }
        return (featureIndex, featureType)
    }

    // MARK: - DPI Parsing (Feature 0x2201)

    /// Parse getSensorCount response.
    /// Returns the number of DPI sensors on the device.
    ///
    /// Response params[0] = sensor count
    static func parseDPISensorCount(_ params: [UInt8]) -> Int? {
        guard !params.isEmpty else { return nil }
        return Int(params[0])
    }

    /// Parse getSensorDpiList response.
    /// Returns an array of supported DPI values.
    ///
    /// The response can be either:
    /// - Discrete list: params[0..n] = DPI values as big-endian uint16
    /// - Range: params[0]=0xE0 marker, then min, max, step as uint16 BE
    ///
    /// Response layout varies by device. Common format:
    /// params[0..1] = DPI value 1 (BE uint16)
    /// params[2..3] = DPI value 2 (BE uint16)
    /// ... until 0x0000 terminator or end of params
    static func parseDPIList(_ params: [UInt8]) -> [Int] {
        guard params.count >= 2 else { return [] }

        let candidates: [[UInt8]] = [
            params,
            Array(params.dropFirst()),
            Array(params.dropFirst(2))
        ]

        for candidate in candidates {
            if let range = parseDPIRange(candidate) {
                return range
            }

            let list = parseDPIDiscrete(candidate)
            if !list.isEmpty {
                return list
            }
        }

        return []
    }

    /// Parse getSensorDpi response.
    /// Returns (currentDPI, defaultDPI).
    ///
    /// Response layout:
    /// params[0..1] = current DPI (BE uint16)
    /// params[2..3] = default DPI (BE uint16)
    static func parseDPICurrent(_ params: [UInt8]) -> (current: Int, defaultDPI: Int)? {
        guard params.count >= 4 else { return nil }

        for offset in [0, 1] {
            guard params.count >= offset + 4 else { continue }
            let current = Int(params[offset]) << 8 | Int(params[offset + 1])
            let defaultDPI = Int(params[offset + 2]) << 8 | Int(params[offset + 3])
            if isPlausibleDPI(current) && isPlausibleDPI(defaultDPI) {
                return (current, defaultDPI)
            }
        }

        let current = Int(params[0]) << 8 | Int(params[1])
        let defaultDPI = Int(params[2]) << 8 | Int(params[3])
        guard current > 0 else { return nil }
        return (current, defaultDPI)
    }

    private static func parseDPIRange(_ params: [UInt8]) -> [Int]? {
        if let range = parseDPIRangeMarkerFirst(params) {
            return range
        }

        if let range = parseDPIRangeMarkerAtIndexThree(params) {
            return range
        }

        return nil
    }

    // Format A: [0xE0, minHi, minLo, maxHi, maxLo, stepHi, stepLo]
    private static func parseDPIRangeMarkerFirst(_ params: [UInt8]) -> [Int]? {
        guard params.count >= 7, params[0] == 0xE0 else { return nil }

        let minDPI = Int(params[1]) << 8 | Int(params[2])
        let maxDPI = Int(params[3]) << 8 | Int(params[4])
        let step = Int(params[5]) << 8 | Int(params[6])
        return buildDPIRange(minDPI: minDPI, maxDPI: maxDPI, step: step)
    }

    // Format B (seen in ratbag logs): [sensorIndex, minHi, minLo, 0xE0, step, maxHi, maxLo]
    private static func parseDPIRangeMarkerAtIndexThree(_ params: [UInt8]) -> [Int]? {
        guard params.count >= 7, params[3] == 0xE0 else { return nil }

        let minDPI = Int(params[1]) << 8 | Int(params[2])
        let step = Int(params[4])
        let maxDPI = Int(params[5]) << 8 | Int(params[6])
        return buildDPIRange(minDPI: minDPI, maxDPI: maxDPI, step: step)
    }

    private static func buildDPIRange(minDPI: Int, maxDPI: Int, step: Int) -> [Int]? {
        guard isPlausibleDPI(minDPI),
              isPlausibleDPI(maxDPI),
              maxDPI >= minDPI,
              step > 0,
              step <= 5000
        else {
            return nil
        }

        var values: [Int] = []
        var current = minDPI
        while current <= maxDPI {
            values.append(current)
            current += step
        }
        return values
    }

    private static func parseDPIDiscrete(_ params: [UInt8]) -> [Int] {
        var seen = Set<Int>()
        var values: [Int] = []
        var i = 0
        while i + 1 < params.count {
            let dpi = Int(params[i]) << 8 | Int(params[i + 1])
            if dpi == 0 { break }  // 0x0000 terminator
            if isPlausibleDPI(dpi) && seen.insert(dpi).inserted {
                values.append(dpi)
            }
            i += 2
        }
        return values.sorted()
    }

    private static func isPlausibleDPI(_ value: Int) -> Bool {
        value >= 50 && value <= 50_000
    }

    // MARK: - Polling Rate Parsing (Feature 0x8060)

    /// Parse getReportRateList response.
    /// Returns array of supported polling rates in Hz.
    ///
    /// Response is a bitmask; bit index corresponds to report interval in ms.
    static func parseReportRateList(_ params: [UInt8]) -> [Int] {
        let mask = parseReportRateMask(params)
        return reportRateHzList(fromMask: mask)
    }

    /// Parse a polling-rate bitmask from a report-rate response.
    /// The mask is encoded little-endian.
    static func parseReportRateMask(_ params: [UInt8]) -> UInt16 {
        guard !params.isEmpty else { return 0 }
        let low = UInt16(params[0])
        let high = params.count > 1 ? UInt16(params[1]) << 8 : 0
        return low | high
    }

    /// Parse getReportRate response.
    /// Returns current polling rate in Hz using a ms-based encoding.
    ///
    /// Response params[0..1] = current report interval in ms (1..8),
    /// but some devices may also echo a mask bit.
    static func parseCurrentReportRate(
        _ params: [UInt8],
        supportedMask: UInt16
    ) -> Int? {
        let value = parseReportRateMask(params)
        guard value != 0 else { return nil }

        if value <= 16 {
            return reportRateHz(fromMs: Int(value))
        }

        if value & (value - 1) == 0, supportedMask & value != 0 {
            let bit = Int(value.trailingZeroBitCount)
            return reportRateHz(fromMs: bit + 1)
        }

        return nil
    }

    /// Convert Hz rate to a report-rate setting value for setReportRate (Feature 0x8060).
    /// Returns the report interval in ms (1..8) if supported by the device mask.
    static func reportRateSettingValue(forHz hz: Int, supportedMask: UInt16) -> UInt8? {
        for bit in 0..<16 {
            let bitMask = UInt16(1 << bit)
            guard supportedMask & bitMask != 0 else { continue }
            let ms = bit + 1
            let rateHz = ms > 0 ? Int(1000 / ms) : 0
            if rateHz == hz {
                return UInt8(ms)
            }
        }
        return nil
    }

    // MARK: - Extended Report Rate Parsing (Feature 0x8061)

    /// Parse a polling-rate bitmask for extended report rate responses.
    /// The mask is encoded little-endian, bits 0..6 map to indices 0..6.
    static func parseExtendedReportRateMask(_ params: [UInt8]) -> UInt16 {
        parseReportRateMask(params)
    }

    /// Returns supported polling rates in Hz for the extended report rate feature.
    static func parseExtendedReportRateList(fromMask mask: UInt16) -> [Int] {
        let options = extendedReportRateOptions()
        return options.compactMap { option in
            let bit = UInt16(1 << option.index)
            guard mask & bit != 0 else { return nil }
            return option.hz
        }
    }

    /// Parse getReportRate response for extended report rate.
    /// Response params[0] = index into the extended report rate table.
    static func parseExtendedCurrentReportRate(
        _ params: [UInt8],
        supportedMask: UInt16
    ) -> Int? {
        guard let indexValue = params.first else { return nil }
        let options = extendedReportRateOptions()
        guard let option = options.first(where: { $0.index == Int(indexValue) }) else {
            return nil
        }
        let bit = UInt16(1 << option.index)
        guard supportedMask & bit != 0 else { return nil }
        return option.hz
    }

    /// Convert Hz rate to an extended report-rate setting value (index 0..6).
    static func extendedReportRateSettingValue(
        forHz hz: Int,
        supportedMask: UInt16
    ) -> UInt8? {
        let options = extendedReportRateOptions()
        guard let option = options.first(where: { $0.hz == hz }) else { return nil }
        let bit = UInt16(1 << option.index)
        guard supportedMask & bit != 0 else { return nil }
        return UInt8(option.index)
    }

    private static func extendedReportRateOptions() -> [(index: Int, hz: Int)] {
        [
            (index: 0, hz: 125),   // 8ms
            (index: 1, hz: 250),   // 4ms
            (index: 2, hz: 500),   // 2ms
            (index: 3, hz: 1000),  // 1ms
            (index: 4, hz: 2000),  // 500us
            (index: 5, hz: 4000),  // 250us
            (index: 6, hz: 8000)   // 125us
        ]
    }

    private static func reportRateHzList(fromMask mask: UInt16) -> [Int] {
        reportRateMsList(fromMask: mask).map { $0.hz }
    }

    private static func reportRateMsList(fromMask mask: UInt16) -> [(ms: Int, hz: Int)] {
        guard mask != 0 else { return [] }

        var values: [(Int, Int)] = []
        for bit in 0..<16 {
            let bitMask = UInt16(1 << bit)
            guard mask & bitMask != 0 else { continue }
            let ms = bit + 1
            values.append((ms, reportRateHz(fromMs: ms)))
        }
        return values
    }

    private static func reportRateHz(fromMs ms: Int) -> Int {
        guard ms > 0 else { return 0 }
        return Int(Double(1000) / Double(ms))
    }

    // MARK: - Button Mapping Parsing (Feature 0x1B04)

    /// Parse getControlCount response.
    /// Returns the number of controls/buttons on the device.
    ///
    /// Response params[0] = control count
    static func parseControlCount(_ params: [UInt8]) -> Int? {
        guard !params.isEmpty else { return nil }
        return Int(params[0])
    }

    /// Parse getControlInfo response.
    /// Returns control information for a single button.
    ///
    /// Response layout:
    /// params[0..1] = CID (Control ID, BE uint16)
    /// params[2..3] = TID (Task ID, BE uint16)
    /// params[4..5] = flags (BE uint16)
    /// params[6] = position (physical location)
    /// params[7] = group (remap compatibility)
    /// params[8] = gmask (group mask)
    /// params[9..10] = additionalFlags (optional)
    static func parseControlInfo(_ params: [UInt8]) -> (
        cid: Int, tid: Int, flags: UInt16, group: Int, gmask: Int
    )? {
        guard params.count >= 9 else { return nil }

        let cid = Int(params[0]) << 8 | Int(params[1])
        let tid = Int(params[2]) << 8 | Int(params[3])
        let flags = UInt16(params[4]) << 8 | UInt16(params[5])
        let group = Int(params[7])
        let gmask = Int(params[8])

        guard cid > 0 else { return nil }
        return (cid, tid, flags, group, gmask)
    }

    /// Parse getControlReporting response.
    /// Returns divert state and remap CID if any.
    ///
    /// Response layout:
    /// params[0..1] = CID being reported on
    /// params[2..3] = flags/reporting state
    /// params[4..5] = remapped CID (0 if default)
    static func parseControlReporting(_ params: [UInt8]) -> (
        diverted: Bool, remappedCID: Int?
    )? {
        guard params.count >= 6 else { return nil }

        let reportingFlags = UInt16(params[2]) << 8 | UInt16(params[3])
        let remappedCID = Int(params[4]) << 8 | Int(params[5])

        let diverted = (reportingFlags & 0x01) != 0
        let remapped: Int? = remappedCID > 0 ? remappedCID : nil

        return (diverted, remapped)
    }

    /// Lookup table for common Control ID names.
    static func controlName(for cid: Int) -> String {
        switch cid {
        case 0x0050: return "Left Click"
        case 0x0051: return "Right Click"
        case 0x0052: return "Middle Click"
        case 0x0053: return "Back"
        case 0x0054: return "Forward"
        case 0x0055: return "Middle Button"
        case 0x0056: return "Forward"
        case 0x00C3: return "DPI Shift"
        case 0x00C4: return "DPI Switch"
        case 0x00D0: return "DPI Down"
        case 0x00D1: return "DPI Up"
        case 0x00D7: return "Scroll Left"
        case 0x00D8: return "Scroll Right"
        case 0x00E0: return "Volume Up"
        case 0x00E1: return "Volume Down"
        case 0x00E2: return "Mute"
        case 0x00E3: return "Play/Pause"
        case 0x00E4: return "Next Track"
        case 0x00E5: return "Previous Track"
        default: return "Button \(String(format: "0x%04X", cid))"
        }
    }
}
