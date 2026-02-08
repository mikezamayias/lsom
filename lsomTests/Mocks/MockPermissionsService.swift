//
//  MockPermissionsService.swift
//  lsomTests
//
//  Mock implementation of PermissionsService for testing.
//

import Foundation
@testable import lsom

final class MockPermissionsService: PermissionsService {
    var inputMonitoringSettingsOpened = false
    var loginItemsSettingsOpened = false

    func openInputMonitoringSettings() {
        inputMonitoringSettingsOpened = true
    }

    func openLoginItemsSettings() {
        loginItemsSettingsOpened = true
    }
}
