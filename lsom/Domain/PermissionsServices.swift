//
//  PermissionsServices.swift
//  lsom
//
//  Domain‑level protocols for permissions and
//  login item management. Implementations live
//  in the Infrastructure layer.
//

import Foundation

protocol PermissionsService: Sendable {
    /// Opens System Settings at the Input Monitoring pane
    /// so the user can enable access for lsom.
    func openInputMonitoringSettings()

    /// Opens System Settings at the Login Items section.
    func openLoginItemsSettings()
}

protocol LoginItemService: Sendable {
    /// Indicates whether the app is currently configured
    /// to launch at login (best‑effort).
    var isEnabled: Bool { get }

    /// Enables or disables launch at login.
    func setEnabled(_ enabled: Bool) throws
}

