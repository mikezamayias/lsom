//
//  AppEnvironment.swift
//  lsom
//
//  Created by Claude on 28/12/2025.
//

import Foundation

/// Centralized dependency container for all application services.
/// Created once and owned by AppDelegate; passed to ViewModels via init injection.
@MainActor
final class AppEnvironment {

    // MARK: - Services

    let batteryService: BatteryService
    let permissionsService: PermissionsService
    let loginItemService: LoginItemService

    /// Mouse settings service for DPI, polling rate, and button configuration.
    let mouseSettingsService: MouseSettingsService

    /// The underlying HID service for debug logging.
    /// Only exposed for debug features; normal code should use `batteryService`.
    let hidDebugService: LogitechHIDService

    /// HID protocol logging service.
    let hidLogService: HIDLogService

    // MARK: - Initialization

    init() {
        let logService = HIDLogService()
        self.hidLogService = logService

        let hidService = LogitechHIDService(logService: logService)
        self.batteryService = hidService
        self.mouseSettingsService = hidService
        self.hidDebugService = hidService
        self.permissionsService = SystemPermissionsService()

        if #available(macOS 13.0, *) {
            self.loginItemService = MainAppLoginItemService()
        } else {
            self.loginItemService = NoopLoginItemService()
        }
    }
}
