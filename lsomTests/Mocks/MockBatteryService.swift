//
//  MockBatteryService.swift
//  lsomTests
//
//  Mock implementation of BatteryService for testing.
//

import Foundation
@testable import lsom

final class MockBatteryService: BatteryService {
    var batteryPercentageToReturn: Int?
    var errorToThrow: Error?
    var callCount = 0

    func batteryPercentage() throws -> Int {
        callCount += 1

        if let error = errorToThrow {
            throw error
        }

        if let percentage = batteryPercentageToReturn {
            return percentage
        }

        throw LogitechHIDError.receiverNotFound
    }
}
