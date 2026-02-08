//
//  HIDPPParsingTests.swift
//  lsomTests
//
//  Unit tests for HID++ parsing functions.
//

import XCTest
@testable import lsom

final class HIDPPParsingTests: XCTestCase {

    // MARK: - parseUnifiedBatteryStatus Tests

    func testParseUnifiedBatteryStatus_validResponse_returns99Percent() {
        // Known good response from HID++ 2.0 Unified Battery (0x1004)
        // Device index 1, feature index 6, state_of_charge = 99 (0x63)
        let response: [UInt8] = [
            0x11,  // Report ID (long report)
            0x01,  // Device index
            0x06,  // Feature index
            0x10,  // Function | software ID
            0x63,  // State of charge (99%)
            0x08,  // Flags
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00  // Padding
        ]

        let result = HIDPPParsing.parseUnifiedBatteryStatus(response)
        XCTAssertEqual(result, 99)
    }

    func testParseUnifiedBatteryStatus_zeroPercent_returnsZero() {
        let response: [UInt8] = [0x11, 0x01, 0x06, 0x10, 0x00, 0x00]
        let result = HIDPPParsing.parseUnifiedBatteryStatus(response)
        XCTAssertEqual(result, 0)
    }

    func testParseUnifiedBatteryStatus_hundredPercent_returns100() {
        let response: [UInt8] = [0x11, 0x01, 0x06, 0x10, 0x64, 0x00]
        let result = HIDPPParsing.parseUnifiedBatteryStatus(response)
        XCTAssertEqual(result, 100)
    }

    func testParseUnifiedBatteryStatus_invalidReportId_returnsNil() {
        // Wrong report ID (0x10 = short report, not 0x11 = long report)
        let response: [UInt8] = [0x10, 0x01, 0x06, 0x10, 0x63, 0x00]
        let result = HIDPPParsing.parseUnifiedBatteryStatus(response)
        XCTAssertNil(result)
    }

    func testParseUnifiedBatteryStatus_tooShort_returnsNil() {
        // Only 4 bytes, need at least 5
        let response: [UInt8] = [0x11, 0x01, 0x06, 0x10]
        let result = HIDPPParsing.parseUnifiedBatteryStatus(response)
        XCTAssertNil(result)
    }

    func testParseUnifiedBatteryStatus_percentageOutOfRange_returnsNil() {
        // 150% is invalid
        let response: [UInt8] = [0x11, 0x01, 0x06, 0x10, 0x96, 0x00]
        let result = HIDPPParsing.parseUnifiedBatteryStatus(response)
        XCTAssertNil(result)
    }

    func testParseUnifiedBatteryStatus_emptyArray_returnsNil() {
        let response: [UInt8] = []
        let result = HIDPPParsing.parseUnifiedBatteryStatus(response)
        XCTAssertNil(result)
    }

    // MARK: - parseRootGetFeature Tests

    func testParseRootGetFeature_validResponse_returnsFeatureInfo() {
        // Root.GetFeature response for Unified Battery (0x1004)
        // Device index 1, feature found at index 6
        let response: [UInt8] = [
            0x11,  // Report ID
            0x01,  // Device index
            0x00,  // Root feature index
            0x00,  // Function | software ID
            0x06,  // Feature index (where 0x1004 was found)
            0x00,  // Feature type
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00
        ]

        let result = HIDPPParsing.parseRootGetFeature(response, expectedDeviceIndex: 0x01)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.index, 6)
        XCTAssertEqual(result?.type, 0)
    }

    func testParseRootGetFeature_featureNotFound_returnsNil() {
        // Feature index 0 means "not found" per HID++ spec
        let response: [UInt8] = [0x11, 0x01, 0x00, 0x00, 0x00, 0x00]
        let result = HIDPPParsing.parseRootGetFeature(response, expectedDeviceIndex: 0x01)
        XCTAssertNil(result)
    }

    func testParseRootGetFeature_wrongDeviceIndex_returnsNil() {
        // Response has device index 2, but we expect 1
        let response: [UInt8] = [0x11, 0x02, 0x00, 0x00, 0x06, 0x00]
        let result = HIDPPParsing.parseRootGetFeature(response, expectedDeviceIndex: 0x01)
        XCTAssertNil(result)
    }

    func testParseRootGetFeature_wrongReportId_returnsNil() {
        let response: [UInt8] = [0x10, 0x01, 0x00, 0x00, 0x06, 0x00]
        let result = HIDPPParsing.parseRootGetFeature(response, expectedDeviceIndex: 0x01)
        XCTAssertNil(result)
    }

    func testParseRootGetFeature_tooShort_returnsNil() {
        // Only 5 bytes, need at least 6
        let response: [UInt8] = [0x11, 0x01, 0x00, 0x00, 0x06]
        let result = HIDPPParsing.parseRootGetFeature(response, expectedDeviceIndex: 0x01)
        XCTAssertNil(result)
    }

    func testParseRootGetFeature_withDifferentFeatureTypes() {
        // Feature type 0x20 (hidden feature) at index 3
        let response: [UInt8] = [0x11, 0x01, 0x00, 0x00, 0x03, 0x20]
        let result = HIDPPParsing.parseRootGetFeature(response, expectedDeviceIndex: 0x01)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.index, 3)
        XCTAssertEqual(result?.type, 0x20)
    }

    // MARK: - parseDPISensorCount Tests

    func testParseDPISensorCount_validResponse_returns1() {
        let params: [UInt8] = [0x01]
        let result = HIDPPParsing.parseDPISensorCount(params)
        XCTAssertEqual(result, 1)
    }

    func testParseDPISensorCount_emptyParams_returnsNil() {
        let params: [UInt8] = []
        let result = HIDPPParsing.parseDPISensorCount(params)
        XCTAssertNil(result)
    }

    // MARK: - parseDPIList Tests

    func testParseDPIList_discreteValues_returnsValues() {
        // Discrete DPI values: 800, 1600, 3200 as big-endian uint16
        let params: [UInt8] = [
            0x03, 0x20,  // 800
            0x06, 0x40,  // 1600
            0x0C, 0x80,  // 3200
            0x00, 0x00   // Terminator
        ]
        let result = HIDPPParsing.parseDPIList(params)
        XCTAssertTrue(result.contains(800))
        XCTAssertTrue(result.contains(1600))
        XCTAssertTrue(result.contains(3200))
    }

    func testParseDPIList_rangeFormatA_returnsRange() {
        // Range format: 0xE0 marker, min=100, max=25600, step=50
        let params: [UInt8] = [
            0xE0,        // Range marker
            0x00, 0x64,  // min = 100
            0x64, 0x00,  // max = 25600
            0x00, 0x32   // step = 50
        ]
        let result = HIDPPParsing.parseDPIList(params)
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains(100))
        XCTAssertTrue(result.contains(150))
    }

    func testParseDPIList_emptyParams_returnsEmpty() {
        let params: [UInt8] = []
        let result = HIDPPParsing.parseDPIList(params)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - parseDPICurrent Tests

    func testParseDPICurrent_validResponse_returnsBothValues() {
        // Current DPI = 1600 (0x0640), Default = 800 (0x0320)
        let params: [UInt8] = [0x06, 0x40, 0x03, 0x20]
        let result = HIDPPParsing.parseDPICurrent(params)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.current, 1600)
        XCTAssertEqual(result?.defaultDPI, 800)
    }

    func testParseDPICurrent_tooShort_returnsNil() {
        let params: [UInt8] = [0x06, 0x40]
        let result = HIDPPParsing.parseDPICurrent(params)
        XCTAssertNil(result)
    }

    // MARK: - Polling Rate Parsing Tests

    func testParseReportRateMask_validResponse_returnsMask() {
        // Mask 0x00FF = bits 0-7 set (1-8ms intervals)
        let params: [UInt8] = [0xFF, 0x00]
        let result = HIDPPParsing.parseReportRateMask(params)
        XCTAssertEqual(result, 0x00FF)
    }

    func testParseReportRateMask_singleByte_returnsLowByte() {
        let params: [UInt8] = [0x07]  // Bits 0,1,2 = 1ms,2ms,4ms
        let result = HIDPPParsing.parseReportRateMask(params)
        XCTAssertEqual(result, 0x0007)
    }

    func testParseReportRateList_mask_returnsHzValues() {
        // Mask with bit 0 (1ms=1000Hz) and bit 1 (2ms=500Hz) set
        let params: [UInt8] = [0x03, 0x00]
        let result = HIDPPParsing.parseReportRateList(params)
        XCTAssertTrue(result.contains(1000))  // 1ms
        XCTAssertTrue(result.contains(500))   // 2ms
    }

    func testParseCurrentReportRate_msValue_returnsHz() {
        // Current rate = 1ms (params[0] = 1), should return 1000Hz
        let params: [UInt8] = [0x01, 0x00]
        let supportedMask: UInt16 = 0x0003
        let result = HIDPPParsing.parseCurrentReportRate(params, supportedMask: supportedMask)
        XCTAssertEqual(result, 1000)
    }

    func testReportRateSettingValue_1000Hz_returns1() {
        // 1000Hz = 1ms interval
        let supportedMask: UInt16 = 0x0003  // 1ms and 2ms supported
        let result = HIDPPParsing.reportRateSettingValue(forHz: 1000, supportedMask: supportedMask)
        XCTAssertEqual(result, 1)
    }

    func testReportRateSettingValue_unsupportedHz_returnsNil() {
        let supportedMask: UInt16 = 0x0001  // Only 1ms (1000Hz) supported
        let result = HIDPPParsing.reportRateSettingValue(forHz: 500, supportedMask: supportedMask)
        XCTAssertNil(result)
    }

    // MARK: - Button Mapping Parsing Tests

    func testParseControlCount_validResponse_returnsCount() {
        let params: [UInt8] = [0x08]  // 8 buttons
        let result = HIDPPParsing.parseControlCount(params)
        XCTAssertEqual(result, 8)
    }

    func testParseControlCount_emptyParams_returnsNil() {
        let params: [UInt8] = []
        let result = HIDPPParsing.parseControlCount(params)
        XCTAssertNil(result)
    }

    func testParseControlInfo_validResponse_returnsInfo() {
        // CID=0x0050 (Left Click), TID=0x0038, flags=0x0001, group=1, gmask=1
        let params: [UInt8] = [
            0x00, 0x50,  // CID
            0x00, 0x38,  // TID
            0x00, 0x01,  // flags
            0x01,        // position
            0x01,        // group
            0x01         // gmask
        ]
        let result = HIDPPParsing.parseControlInfo(params)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.cid, 0x50)
        XCTAssertEqual(result?.tid, 0x38)
        XCTAssertEqual(result?.group, 1)
    }

    func testParseControlInfo_tooShort_returnsNil() {
        let params: [UInt8] = [0x00, 0x50, 0x00, 0x38]
        let result = HIDPPParsing.parseControlInfo(params)
        XCTAssertNil(result)
    }

    func testParseControlReporting_divertedButton_returnsDiverted() {
        // CID=0x0050, flags with divert bit set, no remap
        let params: [UInt8] = [
            0x00, 0x50,  // CID
            0x00, 0x01,  // flags (bit 0 = diverted)
            0x00, 0x00   // no remap
        ]
        let result = HIDPPParsing.parseControlReporting(params)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.diverted == true)
        XCTAssertNil(result?.remappedCID)
    }

    func testParseControlReporting_remappedButton_returnsRemapCID() {
        // CID=0x0050, not diverted, remapped to 0x0051
        let params: [UInt8] = [
            0x00, 0x50,  // CID
            0x00, 0x00,  // flags (not diverted)
            0x00, 0x51   // remapped to right click
        ]
        let result = HIDPPParsing.parseControlReporting(params)
        XCTAssertNotNil(result)
        XCTAssertFalse(result?.diverted == true)
        XCTAssertEqual(result?.remappedCID, 0x51)
    }

    // MARK: - controlName Tests

    func testControlName_knownCID_returnsName() {
        XCTAssertEqual(HIDPPParsing.controlName(for: 0x0050), "Left Click")
        XCTAssertEqual(HIDPPParsing.controlName(for: 0x0051), "Right Click")
        XCTAssertEqual(HIDPPParsing.controlName(for: 0x0052), "Middle Click")
    }

    func testControlName_unknownCID_returnsFormattedHex() {
        let result = HIDPPParsing.controlName(for: 0x1234)
        XCTAssertTrue(result.contains("0x1234"))
    }
}
