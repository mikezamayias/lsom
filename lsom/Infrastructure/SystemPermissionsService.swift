//
//  SystemPermissionsService.swift
//  lsom
//
//  Concrete implementations of domain permissions
//  and login item services, using macOS system APIs.
//

import AppKit
import ServiceManagement

final class SystemPermissionsService: PermissionsService {
    func openInputMonitoringSettings() {
        // Input Monitoring pane in Privacy & Security.
        if let url = URL(
            string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    func openLoginItemsSettings() {
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}

@available(macOS 13.0, *)
final class MainAppLoginItemService: LoginItemService {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        }
    }
}

/// Fallback no‑op implementation for platforms where SMAppService
/// is not available or when you intentionally disable login items.
final class NoopLoginItemService: LoginItemService {
    var isEnabled: Bool { false }
    func setEnabled(_ enabled: Bool) throws { }
}

