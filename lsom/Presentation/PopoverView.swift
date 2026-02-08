//
//  PopoverView.swift
//  lsom
//
//  Native macOS popover UI for the menu bar status item.
//

import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
final class PopoverViewModel: ObservableObject {
    private let permissionsService: PermissionsService
    private weak var appDelegate: AppDelegate?

    @Published var batteryPercent: Int?
    @Published var isConnected: Bool = false
    @Published var deviceName: String = ""
    @Published var lastUpdatedText: String = "Updated just now"
    @Published var currentDPI: Int = 0
    @Published var currentPollingRate: Int = 0
    @Published var showPermissionHint: Bool = false

    private var lastUpdatedAt: Date?
    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(
        appDelegate: AppDelegate,
        permissionsService: PermissionsService
    ) {
        self.appDelegate = appDelegate
        self.permissionsService = permissionsService

        // Load cached data immediately for instant display
        batteryPercent = appDelegate.lastBatteryPercent
        currentDPI = appDelegate.lastDPI
        currentPollingRate = appDelegate.lastPollingRate
        deviceName = appDelegate.lastDeviceName.isEmpty ? "Logitech Mouse" : appDelegate.lastDeviceName
        isConnected = appDelegate.isReceiverConnected
        if let lastUpdate = appDelegate.lastUpdatedAt {
            lastUpdatedAt = lastUpdate
            updateLastUpdatedText()
        }

        // Permission hint: only show when receiver is not connected AND user
        // hasn't dismissed. This avoids conflating "feature not supported" or
        // transient errors with a permissions issue.
        let hasDismissedHint = UserDefaults.standard.bool(forKey: UserDefaultsKey.hasDismissedInputMonitoringHint)
        showPermissionHint = !hasDismissedHint && !appDelegate.isReceiverConnected

        // Subscribe to battery updates
        appDelegate.$lastBatteryPercent
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self else { return }
                self.batteryPercent = value
            }
            .store(in: &cancellables)

        // Subscribe to connection state — drives permission hint visibility
        appDelegate.$isReceiverConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                guard let self else { return }
                self.isConnected = connected
                let dismissed = UserDefaults.standard.bool(forKey: UserDefaultsKey.hasDismissedInputMonitoringHint)
                if connected {
                    self.showPermissionHint = false
                } else if !dismissed {
                    self.showPermissionHint = true
                }
            }
            .store(in: &cancellables)

        // Subscribe to DPI updates
        appDelegate.$lastDPI
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentDPI)

        // Subscribe to polling rate updates
        appDelegate.$lastPollingRate
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentPollingRate)

        // Subscribe to device name updates
        appDelegate.$lastDeviceName
            .receive(on: DispatchQueue.main)
            .map { $0.isEmpty ? "Logitech Mouse" : $0 }
            .assign(to: &$deviceName)

        // Subscribe to last updated time
        appDelegate.$lastUpdatedAt
            .receive(on: DispatchQueue.main)
            .sink { [weak self] date in
                self?.lastUpdatedAt = date
                self?.updateLastUpdatedText()
                self?.startUpdateTimer()
            }
            .store(in: &cancellables)
    }

    deinit {
        updateTimer?.invalidate()
    }

    #if DEBUG
    /// Preview-only initializer that sets state directly without dependencies.
    init(
        batteryPercent: Int?,
        isConnected: Bool,
        deviceName: String,
        lastUpdatedText: String,
        currentDPI: Int,
        currentPollingRate: Int,
        showPermissionHint: Bool
    ) {
        self.permissionsService = PreviewPermissionsService()
        self.appDelegate = nil
        self.batteryPercent = batteryPercent
        self.isConnected = isConnected
        self.deviceName = deviceName
        self.lastUpdatedText = lastUpdatedText
        self.currentDPI = currentDPI
        self.currentPollingRate = currentPollingRate
        self.showPermissionHint = showPermissionHint
    }

    /// Creates a preview ViewModel with connected device state.
    static func previewConnected() -> PopoverViewModel {
        PopoverViewModel(
            batteryPercent: 89,
            isConnected: true,
            deviceName: "PRO X Wireless",
            lastUpdatedText: "Just now",
            currentDPI: 1200,
            currentPollingRate: 1000,
            showPermissionHint: false
        )
    }

    /// Creates a preview ViewModel with disconnected device state.
    static func previewDisconnected() -> PopoverViewModel {
        PopoverViewModel(
            batteryPercent: nil,
            isConnected: false,
            deviceName: "",
            lastUpdatedText: "",
            currentDPI: 0,
            currentPollingRate: 0,
            showPermissionHint: true
        )
    }
    #endif

    func refresh() {
        // Trigger background refresh via AppDelegate (data flows back via publishers)
        appDelegate?.refreshAllData()
    }

    func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func openInputMonitoring() {
        permissionsService.openInputMonitoringSettings()
    }

    func dismissPermissionHint() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKey.hasDismissedInputMonitoringHint)
        showPermissionHint = false
    }

    private func updateLastUpdatedText() {
        guard let lastUpdatedAt else {
            lastUpdatedText = ""
            return
        }

        let interval = Date().timeIntervalSince(lastUpdatedAt)
        if interval < 5 {
            lastUpdatedText = "Just now"
        } else if interval < 60 {
            lastUpdatedText = "\(Int(interval))s ago"
        } else if interval < 3600 {
            lastUpdatedText = "\(Int(interval / 60))m ago"
        } else {
            lastUpdatedText = "\(Int(interval / 3600))h ago"
        }
    }

    private func startUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.updateLastUpdatedText()
            }
        }
    }
}

// MARK: - Main View

struct PopoverView: View {
    @StateObject var viewModel: PopoverViewModel

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("lsom")
                    .font(.headline)
                Spacer()
                Text(viewModel.deviceName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Battery Card
            BatteryCard(
                percent: viewModel.batteryPercent,
                isConnected: viewModel.isConnected,
                lastUpdated: viewModel.lastUpdatedText
            )

            // Stats Row
            if viewModel.isConnected {
                HStack(spacing: 12) {
                    StatCard(
                        icon: "display",
                        title: "POLLING",
                        value: viewModel.currentPollingRate > 0 ? "\(viewModel.currentPollingRate) Hz" : "–",
                        color: .blue
                    )
                    StatCard(
                        icon: "target",
                        title: "DPI",
                        value: viewModel.currentDPI > 0 ? "\(viewModel.currentDPI)" : "–",
                        color: .orange
                    )
                }
            }

            // Permission Hint
            if viewModel.showPermissionHint {
                PermissionHintView(
                    onOpenSettings: { viewModel.openInputMonitoring() },
                    onDismiss: { viewModel.dismissPermissionHint() }
                )
            }

            // Footer
            HStack {
                Button {
                    viewModel.quit()
                } label: {
                    Label("Quit lsom", systemImage: "power")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            viewModel.refresh()
        }
    }
}

// MARK: - Battery Card

private struct BatteryCard: View {
    let percent: Int?
    let isConnected: Bool
    let lastUpdated: String

    var body: some View {
        HStack(spacing: 16) {
            // Circular Progress
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 6)
                    .frame(width: 60, height: 60)

                if let percent {
                    Circle()
                        .trim(from: 0, to: CGFloat(percent) / 100)
                        .stroke(
                            batteryColor,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(duration: 0.5), value: percent)
                }

                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(percent.map { "\($0)" } ?? "–")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // Status
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(isConnected ? "Connected" : "Disconnected")
                        .font(.subheadline.weight(.medium))
                }

                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                    Text("Updated \(lastUpdated)")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var batteryColor: Color {
        guard let percent else { return .gray }
        if percent >= 50 { return .green }
        if percent >= 20 { return .yellow }
        return .red
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Permission Hint

private struct PermissionHintView: View {
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Input Monitoring Required")
                .font(.caption.weight(.medium))

            Text("lsom needs permission to communicate with your mouse.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Button("Open Settings", action: onOpenSettings)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.plain)
                    .font(.caption)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Preview Helpers

#if DEBUG
/// Mock PermissionsService for SwiftUI previews.
private struct PreviewPermissionsService: PermissionsService {
    func openInputMonitoringSettings() {}
    func openLoginItemsSettings() {}
}
#endif

// MARK: - Previews

#Preview("Battery Card - Connected") {
    BatteryCard(
        percent: 89,
        isConnected: true,
        lastUpdated: "Just now"
    )
    .padding()
    .frame(width: 320)
}

#Preview("Battery Card - Low Battery") {
    BatteryCard(
        percent: 15,
        isConnected: true,
        lastUpdated: "5m ago"
    )
    .padding()
    .frame(width: 320)
}

#Preview("Battery Card - Disconnected") {
    BatteryCard(
        percent: nil,
        isConnected: false,
        lastUpdated: ""
    )
    .padding()
    .frame(width: 320)
}

#Preview("Stat Card") {
    HStack(spacing: 12) {
        StatCard(
            icon: "display",
            title: "POLLING",
            value: "1000 Hz",
            color: .blue
        )
        StatCard(
            icon: "target",
            title: "DPI",
            value: "1200",
            color: .orange
        )
    }
    .padding()
    .frame(width: 320)
}

#Preview("Permission Hint") {
    PermissionHintView(
        onOpenSettings: {},
        onDismiss: {}
    )
    .padding()
    .frame(width: 320)
}

#if DEBUG
#Preview("Full Popover - Connected") {
    PopoverView(viewModel: .previewConnected())
}

#Preview("Full Popover - Disconnected") {
    PopoverView(viewModel: .previewDisconnected())
}
#endif
