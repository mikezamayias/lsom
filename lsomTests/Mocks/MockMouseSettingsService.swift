//
//  MockMouseSettingsService.swift
//  lsomTests
//
//  Mock implementation of MouseSettingsService for testing.
//

import Combine
import Foundation
@testable import lsom

final class MockMouseSettingsService: MouseSettingsService {

    // MARK: - Connection Publisher

    private let connectionSubject = PassthroughSubject<Bool, Never>()
    var deviceConnectionPublisher: AnyPublisher<Bool, Never> {
        connectionSubject.eraseToAnyPublisher()
    }

    func simulateConnectionChange(_ connected: Bool) {
        connectionSubject.send(connected)
    }

    // MARK: - Settings Change Publisher

    private let settingsSubject = PassthroughSubject<MouseSettingsChange, Never>()
    var settingsChangePublisher: AnyPublisher<MouseSettingsChange, Never> {
        settingsSubject.eraseToAnyPublisher()
    }

    func simulateSettingsChange(_ change: MouseSettingsChange) {
        settingsSubject.send(change)
    }

    // MARK: - Stubbed Return Values

    var dpiSensorCountToReturn: Int = 1
    var dpiSettingsToReturn: DPISensorInfo?
    var pollingRateInfoToReturn: PollingRateInfo?
    var buttonMappingsToReturn: [ButtonMapping] = []
    var supportsOnboardProfilesToReturn: Bool = false
    var onboardProfilesEnabledToReturn: Bool = false

    // MARK: - Errors

    var errorToThrow: Error?

    // MARK: - Call Tracking

    var setDPICalls: [(dpi: Int, sensorIndex: Int)] = []
    var setPollingRateCalls: [Int] = []
    var setOnboardProfilesCalls: [Bool] = []
    var remapButtonCalls: [(controlId: Int, targetCID: Int?)] = []
    var setButtonDivertCalls: [(controlId: Int, diverted: Bool)] = []

    // MARK: - Protocol Implementation

    func dpiSensorCount() async throws -> Int {
        if let error = errorToThrow { throw error }
        return dpiSensorCountToReturn
    }

    func dpiSettings(forSensor sensorIndex: Int) async throws -> DPISensorInfo {
        if let error = errorToThrow { throw error }
        if let settings = dpiSettingsToReturn {
            return settings
        }
        return DPISensorInfo(
            sensorIndex: sensorIndex,
            currentDPI: 800,
            defaultDPI: 800,
            supportedValues: [400, 800, 1600, 3200]
        )
    }

    func setDPI(_ dpi: Int, forSensor sensorIndex: Int) async throws {
        if let error = errorToThrow { throw error }
        setDPICalls.append((dpi, sensorIndex))
    }

    func pollingRateInfo() async throws -> PollingRateInfo {
        if let error = errorToThrow { throw error }
        if let info = pollingRateInfoToReturn {
            return info
        }
        return PollingRateInfo(
            currentHz: 1000,
            supportedHz: [125, 250, 500, 1000],
            supportedMask: 0x0087
        )
    }

    func setPollingRate(_ rateHz: Int) async throws {
        if let error = errorToThrow { throw error }
        setPollingRateCalls.append(rateHz)
    }

    func buttonMappings() async throws -> [ButtonMapping] {
        if let error = errorToThrow { throw error }
        return buttonMappingsToReturn
    }

    func remapButton(controlId: Int, to targetCID: Int?) async throws {
        if let error = errorToThrow { throw error }
        remapButtonCalls.append((controlId, targetCID))
    }

    func setButtonDivert(controlId: Int, diverted: Bool) async throws {
        if let error = errorToThrow { throw error }
        setButtonDivertCalls.append((controlId, diverted))
    }

    func supportsOnboardProfiles() async throws -> Bool {
        if let error = errorToThrow { throw error }
        return supportsOnboardProfilesToReturn
    }

    func onboardProfilesEnabled() async throws -> Bool {
        if let error = errorToThrow { throw error }
        return onboardProfilesEnabledToReturn
    }

    func setOnboardProfilesEnabled(_ enabled: Bool) async throws {
        if let error = errorToThrow { throw error }
        setOnboardProfilesCalls.append(enabled)
        onboardProfilesEnabledToReturn = enabled
    }

    var deviceStateToReturn: MouseDeviceState?

    func deviceState() async -> MouseDeviceState {
        if let state = deviceStateToReturn {
            return state
        }

        let dpiInfo = try? await dpiSettings(forSensor: 0)
        let pollingInfo = try? await pollingRateInfo()

        return MouseDeviceState(
            deviceName: "Mock Mouse",
            batteryPercentage: 75,
            dpiState: dpiInfo.map {
                MouseDeviceState.DPIState(
                    isSupported: true,
                    sensorCount: dpiSensorCountToReturn,
                    currentDPI: $0.currentDPI,
                    defaultDPI: $0.defaultDPI,
                    supportedValues: $0.supportedValues
                )
            },
            pollingRateState: pollingInfo.map {
                MouseDeviceState.PollingRateState(
                    isSupported: true,
                    currentHz: $0.currentHz,
                    supportedHz: $0.supportedHz
                )
            },
            onboardProfilesState: MouseDeviceState.OnboardProfilesState(
                isSupported: supportsOnboardProfilesToReturn,
                isEnabled: onboardProfilesEnabledToReturn
            ),
            buttonMappingState: MouseDeviceState.ButtonMappingState(
                isSupported: !buttonMappingsToReturn.isEmpty,
                buttonCount: buttonMappingsToReturn.count,
                mappings: buttonMappingsToReturn
            ),
            timestamp: Date()
        )
    }
}
