//
//  lsomApp.swift
//  lsom
//
//  Created by Mike Zamagias on 26/12/2025.
//

import AppKit
import Combine
import SwiftUI

@main
struct LsomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                viewModel: SettingsViewModel(
                    appDelegate: appDelegate,
                    loginItemService: appDelegate.environment.loginItemService,
                    permissionsService: appDelegate.environment.permissionsService,
                    mouseSettingsService: appDelegate.environment.mouseSettingsService
                )
            )
        }
    }
}

// MARK: - UserDefaults Keys

enum UserDefaultsKey {
    static let autoRefreshInterval = "AutoRefreshIntervalSeconds"
    static let showPercentageInMenuBar = "ShowPercentageInMenuBar"
    static let hasDismissedInputMonitoringHint = "HasDismissedInputMonitoringHint"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    /// Centralized dependency container for all services.
    let environment: AppEnvironment

    private var refreshTimer: Timer?
    private var deviceConnectionCancellable: AnyCancellable?
    private var settingsChangeCancellable: AnyCancellable?
    private var windowObservers: [NSObjectProtocol] = []

    // Shared cached values for status item and popover (instant display).
    @Published var lastBatteryPercent: Int?
    @Published var lastDPI: Int = 0
    @Published var lastPollingRate: Int = 0
    @Published var lastDeviceName: String = ""
    @Published var lastUpdatedAt: Date?
    @Published var isReceiverConnected: Bool = false

    override init() {
        self.environment = AppEnvironment()
        super.init()

        // Register default values for UserDefaults (single source of truth)
        UserDefaults.standard.register(defaults: [
            UserDefaultsKey.showPercentageInMenuBar: true,
            UserDefaultsKey.autoRefreshInterval: 0,
            UserDefaultsKey.hasDismissedInputMonitoringHint: false
        ])

        // Configure auto‑refresh timer from stored settings.
        let storedSeconds = UserDefaults.standard.integer(
            forKey: UserDefaultsKey.autoRefreshInterval
        )
        let interval = AutoRefreshInterval(rawValue: storedSeconds)
            ?? .off
        configureRefreshTimer(for: interval)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "computermouse",
                accessibilityDescription: "lsom"
            )
            button.imagePosition = .imageLeft
            button.title = ""
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        let contentView = PopoverView(
            viewModel: PopoverViewModel(
                appDelegate: self,
                permissionsService: self.environment.permissionsService
            )
        )

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 280)
        popover.contentViewController = NSHostingController(
            rootView: contentView
        )

        // Subscribe to device connection changes for real-time updates
        deviceConnectionCancellable = environment.hidDebugService.deviceConnectionSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                guard let self else { return }
                self.isReceiverConnected = isConnected
                if isConnected {
                    // Device connected - wait for system to enumerate device, then refresh
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1))
                        self.refreshAllData()
                    }
                } else {
                    // Device disconnected - clear battery display
                    self.lastBatteryPercent = nil
                    self.updateStatusItemTitle()
                }
            }

        // Subscribe to settings changes (DPI / polling)
        settingsChangeCancellable = environment.mouseSettingsService.settingsChangePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard let self else { return }
                switch change {
                case .dpiChanged(let dpi):
                    self.lastDPI = dpi
                case .pollingRateChanged(let hz):
                    self.lastPollingRate = hz
                }
                self.lastUpdatedAt = Date()
            }

        refreshAllData()
        setupWindowObservers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up window observers
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowObservers.removeAll()

        // Clean up timer
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func setupWindowObservers() {
        // Show in Dock/app switcher when any titled app window opens (e.g., Settings).
        let keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.updateActivationPolicyForWindows()
            }
        }
        windowObservers.append(keyObserver)

        // Hide from Dock/app switcher when the last normal app window closes.
        let closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let closingWindow = notification.object as? NSWindow else { return }
            Task { @MainActor [self] in
                self.updateActivationPolicyForWindows(excluding: closingWindow)
            }
        }
        windowObservers.append(closeObserver)
    }

    private func setActivationPolicy(_ policy: NSApplication.ActivationPolicy) {
        NSApp.setActivationPolicy(policy)
        if policy == .regular {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func updateActivationPolicyForWindows(excluding closingWindow: NSWindow? = nil) {
        let hasVisibleWindow = NSApp.windows.contains { window in
            guard window !== closingWindow else { return false }
            return shouldShowInDock(for: window)
        }
        setActivationPolicy(hasVisibleWindow ? .regular : .accessory)
    }

    private func shouldShowInDock(for window: NSWindow) -> Bool {
        let isOpen = window.isVisible || window.isMiniaturized
        let hasTitleBar = window.styleMask.contains(.titled)
        return isOpen && hasTitleBar
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Refreshes all cached data (battery, DPI, polling rate, device name) from the device.
    ///
    /// HID I/O requires a run-loop–backed thread because IOKit callbacks fire on the
    /// current run loop. A dedicated `Thread` is used (dispatch queues don't guarantee
    /// a persistent run loop). All UI updates are dispatched back to `@MainActor`.
    func refreshAllData() {
        let hidService = environment.hidDebugService

        Thread.detachNewThread { [weak self] in
            let battery = try? hidService.batteryPercentage()
            let deviceName = hidService.deviceName()
            let dpi = try? hidService.dpiSettingsSync(forSensor: 0)
            let polling = try? hidService.pollingRateInfoSync()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lastBatteryPercent = battery
                self.lastDeviceName = deviceName ?? "Logitech Mouse"
                self.lastDPI = dpi?.currentDPI ?? 0
                self.lastPollingRate = polling?.currentHz ?? 0
                self.lastUpdatedAt = Date()
                self.isReceiverConnected = battery != nil
                self.updateStatusItemTitle()
            }
        }
    }

    /// Updates the status item title based on current battery value and settings.
    private func updateStatusItemTitle() {
        guard let button = statusItem.button else { return }

        // Default registered in init, just read directly
        let showPercentage = UserDefaults.standard.bool(forKey: UserDefaultsKey.showPercentageInMenuBar)

        if showPercentage, let value = lastBatteryPercent {
            button.title = " \(value)%"
        } else {
            button.title = ""
        }
    }

    /// Called by Settings when the "Show percentage" toggle changes.
    func refreshStatusItemDisplay() {
        updateStatusItemTitle()
    }

    func setAutoRefreshInterval(_ interval: AutoRefreshInterval) {
        UserDefaults.standard.set(interval.rawValue, forKey: UserDefaultsKey.autoRefreshInterval)
        configureRefreshTimer(for: interval)
    }

    private func configureRefreshTimer(for interval: AutoRefreshInterval) {
        refreshTimer?.invalidate()
        refreshTimer = nil

        guard interval != .off else { return }

        let timer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(interval.rawValue),
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refreshAllData()
            }
        }
        refreshTimer = timer
    }
}
