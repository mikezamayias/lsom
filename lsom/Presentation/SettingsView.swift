//
//  SettingsView.swift
//  lsom
//
//  Native macOS Settings window with clean tab-based UI.
//

import SwiftUI
import AppKit
import Combine
import Foundation

// MARK: - Settings ViewModel

@MainActor
final class SettingsViewModel: ObservableObject {
    private weak var appDelegate: AppDelegate?
    private let loginItemService: LoginItemService
    private let permissionsService: PermissionsService
    let mouseSettingsService: MouseSettingsService

    @Published var launchAtLogin: Bool
    @Published var showPercentage: Bool

    // Mouse settings
    @Published var currentDPI: Int = 800
    @Published var selectedDPI: Int = 800
    @Published var supportedDPIValues: [Int] = []
    @Published var currentPollingRate: Int = 1000
    @Published var supportedPollingRates: [Int] = [125, 250, 500, 1000]
    @Published var isLoadingMouse: Bool = false
    @Published var dpiSupported: Bool = true
    @Published var pollingSupported: Bool = true

    // Device/Button settings
    @Published var buttonMappings: [ButtonMappingDisplay] = []
    @Published var isLoadingDevice: Bool = false

    struct ButtonMappingDisplay: Identifiable {
        let id = UUID()
        let name: String
        let action: String
    }

    init(
        appDelegate: AppDelegate,
        loginItemService: LoginItemService,
        permissionsService: PermissionsService,
        mouseSettingsService: MouseSettingsService
    ) {
        self.appDelegate = appDelegate
        self.loginItemService = loginItemService
        self.permissionsService = permissionsService
        self.mouseSettingsService = mouseSettingsService
        self.launchAtLogin = loginItemService.isEnabled
        // Default registered in AppDelegate.init, just read directly
        self.showPercentage = UserDefaults.standard.bool(forKey: UserDefaultsKey.showPercentageInMenuBar)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItemService.setEnabled(enabled)
        } catch {
            launchAtLogin = loginItemService.isEnabled
        }
    }

    func setShowPercentage(_ show: Bool) {
        UserDefaults.standard.set(show, forKey: UserDefaultsKey.showPercentageInMenuBar)
        appDelegate?.refreshStatusItemDisplay()
    }

    func loadMouseSettings() {
        guard !isLoadingMouse else { return }
        isLoadingMouse = true
        let mouseService = mouseSettingsService
        let dpiKey = UserDefaultsKey.lastUsedDPI
        let pollingRateKey = UserDefaultsKey.lastUsedPollingRate
        let savedDPI = UserDefaults.standard.integer(forKey: dpiKey)
        let savedPollingRate = UserDefaults.standard.integer(forKey: pollingRateKey)

        Task.detached(priority: .userInitiated) { [weak self] in
            let dpiResult: Result<DPISensorInfo, Error>
            let pollingResult: Result<PollingRateInfo, Error>

            do {
                dpiResult = .success(try await mouseService.dpiSettings(forSensor: 0))
            } catch {
                dpiResult = .failure(error)
            }

            do {
                pollingResult = .success(try await mouseService.pollingRateInfo())
            } catch {
                pollingResult = .failure(error)
            }

            await MainActor.run { [weak self] in
                guard let self else { return }

                switch dpiResult {
                case .success(let dpiInfo):
                    currentDPI = dpiInfo.currentDPI
                    selectedDPI = dpiInfo.currentDPI
                    supportedDPIValues = dpiInfo.supportedValues
                    dpiSupported = true
                    
                    // If device DPI differs from saved preference and saved is supported,
                    // auto-restore the saved DPI
                    if savedDPI > 0 && savedDPI != dpiInfo.currentDPI && 
                       dpiInfo.supportedValues.contains(savedDPI) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.selectedDPI = savedDPI
                            self.commitDPI()
                        }
                    }
                case .failure:
                    dpiSupported = false
                }

                switch pollingResult {
                case .success(let pollingInfo):
                    currentPollingRate = pollingInfo.currentHz
                    supportedPollingRates = pollingInfo.supportedHz.sorted()
                    pollingSupported = true
                    
                    // If device polling rate differs from saved preference and saved is supported,
                    // auto-restore the saved polling rate
                    if savedPollingRate > 0 && savedPollingRate != pollingInfo.currentHz &&
                       pollingInfo.supportedHz.contains(savedPollingRate) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.applyPollingRate(savedPollingRate, previousRate: pollingInfo.currentHz)
                        }
                    }
                case .failure:
                    pollingSupported = false
                }

                isLoadingMouse = false
            }
        }
    }

    /// Commits the selected DPI to the device. Called when slider interaction ends.
    func commitDPI() {
        guard selectedDPI != currentDPI else { return }

        let targetDPI = selectedDPI
        let mouseService = mouseSettingsService

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try await mouseService.setDPI(targetDPI, forSensor: 0)
                
                // Persist the DPI selection to UserDefaults
                UserDefaults.standard.set(targetDPI, forKey: UserDefaultsKey.lastUsedDPI)
                
                await MainActor.run { [weak self] in
                    self?.currentDPI = targetDPI
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.selectedDPI = self.currentDPI
                }
            }
        }
    }

    func applyPollingRate(_ rate: Int, previousRate: Int) {
        #if DEBUG
        print("lsom/polling-ui: applyPollingRate called - new=\(rate), previous=\(previousRate)")
        #endif
        guard rate != previousRate else {
            #if DEBUG
            print("lsom/polling-ui: Rate unchanged, skipping")
            #endif
            return
        }

        #if DEBUG
        print("lsom/polling-ui: Will set polling rate from \(previousRate) to \(rate)")
        #endif

        let mouseService = mouseSettingsService
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                #if DEBUG
                print("lsom/polling-ui: Calling mouseService.setPollingRate(\(rate))")
                #endif
                try await mouseService.setPollingRate(rate)
                
                // Persist the polling rate selection to UserDefaults
                UserDefaults.standard.set(rate, forKey: UserDefaultsKey.lastUsedPollingRate)
                
                #if DEBUG
                print("lsom/polling-ui: setPollingRate completed successfully")
                #endif
            } catch {
                #if DEBUG
                print("lsom/polling-ui: setPollingRate failed: \(error)")
                #endif
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    #if DEBUG
                    print("lsom/polling-ui: Reverting currentPollingRate to \(previousRate)")
                    #endif
                    self.currentPollingRate = previousRate
                }
            }
        }
    }

    func loadDeviceSettings() {
        guard !isLoadingDevice else { return }
        isLoadingDevice = true
        let mouseService = mouseSettingsService

        Task.detached(priority: .userInitiated) { [weak self] in
            let result: Result<[ButtonMapping], Error>
            do {
                result = .success(try await mouseService.buttonMappings())
            } catch {
                result = .failure(error)
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let mappings):
                    buttonMappings = mappings.map { mapping in
                        ButtonMappingDisplay(
                            name: mapping.control.name,
                            action: self.actionName(for: mapping)
                        )
                    }
                case .failure:
                    buttonMappings = []
                }
                isLoadingDevice = false
            }
        }
    }

    private func actionName(for mapping: ButtonMapping) -> String {
        if mapping.isDiverted {
            return "Diverted"
        }
        if let remapped = mapping.remappedTo {
            return HIDPPParsing.controlName(for: remapped)
        }
        return defaultActionName(for: mapping.control.controlId)
    }

    private func defaultActionName(for controlId: Int) -> String {
        switch controlId {
        case 0x0050: return "Primary Click"
        case 0x0051: return "Secondary Click"
        case 0x0052: return "Mission Control"
        case 0x0053: return "Back"
        case 0x0056: return "Forward"
        case 0x00D7: return "DPI Shift"
        default: return "Default"
        }
    }

    func openInputMonitoring() {
        permissionsService.openInputMonitoringSettings()
    }
}

// MARK: - Main Settings View

struct SettingsView: View {
    @StateObject var viewModel: SettingsViewModel

    var body: some View {
        TabView {
            GeneralTab(viewModel: viewModel)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            MouseTab(viewModel: viewModel)
                .tabItem {
                    Label("Mouse", systemImage: "computermouse")
                }

            DeviceTab(viewModel: viewModel)
                .tabItem {
                    Label("Device", systemImage: "gamecontroller")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $viewModel.launchAtLogin)
                    .onChange(of: viewModel.launchAtLogin) { _, newValue in
                        viewModel.setLaunchAtLogin(newValue)
                    }

                Toggle("Show Percentage", isOn: $viewModel.showPercentage)
                    .onChange(of: viewModel.showPercentage) { _, newValue in
                        viewModel.setShowPercentage(newValue)
                    }
            }

            Section {
                Text("lsom requires Input Monitoring permission to communicate with your device.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

// MARK: - Mouse Tab

private struct MouseTab: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            if viewModel.dpiSupported && !viewModel.supportedDPIValues.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Tracking Speed (DPI)")
                                .font(.headline)
                            Spacer()
                            Text("\(viewModel.selectedDPI)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        LogDpiSlider(
                            supportedValues: viewModel.supportedDPIValues,
                            selection: $viewModel.selectedDPI,
                            onEditingEnded: {
                                viewModel.commitDPI()
                            }
                        )
                    }
                }
            }

            if viewModel.pollingSupported {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Polling Rate")
                                .font(.headline)
                            Text("Higher rates use more battery")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Picker("", selection: $viewModel.currentPollingRate) {
                            ForEach(viewModel.supportedPollingRates, id: \.self) { rate in
                                Text(verbatim: "\(rate) Hz").tag(rate)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                        .onChange(of: viewModel.currentPollingRate) { oldValue, newValue in
                            viewModel.applyPollingRate(newValue, previousRate: oldValue)
                        }

#if DEBUG
                        Button("Dump State") {
                            Task {
                                let state = await viewModel.mouseSettingsService.deviceState()
                                NSLog("lsom/debug: deviceState -> \(state)")
                            }
                        }
                        .buttonStyle(.bordered)
#endif
                    }
                }
            }

            if !viewModel.dpiSupported && !viewModel.pollingSupported {
                Section {
                    ContentUnavailableView(
                        "Device Not Connected",
                        systemImage: "computermouse",
                        description: Text("Connect your Logitech mouse to adjust settings.")
                    )
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .onAppear {
            viewModel.loadMouseSettings()
        }
    }
}

// MARK: - Device Tab

private struct DeviceTab: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Button Assignments") {
                if viewModel.buttonMappings.isEmpty && !viewModel.isLoadingDevice {
                    ContentUnavailableView(
                        "No Button Data",
                        systemImage: "gamecontroller",
                        description: Text("Connect your mouse to view button assignments.")
                    )
                } else {
                    ForEach(viewModel.buttonMappings) { mapping in
                        HStack {
                            Text(mapping.name)
                            Spacer()
                            Text(mapping.action)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            viewModel.loadDeviceSettings()
        }
    }
}

// MARK: - About Tab

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // App Icon
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "computermouse")
                    .font(.system(size: 36))
                    .foregroundStyle(.primary)
            }

            // App Name & Version
            VStack(spacing: 4) {
                Text("lsom")
                    .font(.title.weight(.semibold))

                Text("Version \(Bundle.main.appVersionString) (\(Bundle.main.buildNumberString))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Description
            VStack(spacing: 2) {
                Text("Designed for macOS.")
                Text("Communicates with Logitech devices via HID++ 2.0.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            // Check for Updates
            Button("Check for Updates") {
                // Future: Implement update checking
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Bundle Extension

fileprivate extension Bundle {
    var appVersionString: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var buildNumberString: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

// MARK: - Logarithmic DPI Slider

private struct LogDpiSlider: View {
    let supportedValues: [Int]
    @Binding var selection: Int
    var onEditingEnded: (() -> Void)?
    @State private var trackMetrics: SliderTrackMetrics = .zero

    private var sortedValues: [Int] {
        let unique = Array(Set(supportedValues))
        return unique.sorted()
    }

    var body: some View {
        let values = sortedValues
        if values.count >= 2 {
            let minLog = logValue(values.first ?? 1)
            let maxLog = logValue(values.last ?? 1)
            let sliderBinding = Binding<Double>(
                get: {
                    normalizedLogValue(
                        for: selection,
                        minLog: minLog,
                        maxLog: maxLog
                    )
                },
                set: { newValue in
                    let next = nearestValue(
                        for: newValue,
                        values: values,
                        minLog: minLog,
                        maxLog: maxLog
                    )
                    selection = next
                }
            )

            let sliderPadding: CGFloat = 12

            VStack(spacing: 6) {
                FullWidthSlider(
                    value: sliderBinding,
                    trackMetrics: $trackMetrics,
                    range: 0...1,
                    onEditingEnded: onEditingEnded
                )
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, sliderPadding)

                DpiTickMarks(
                    values: indicatorValues(from: values),
                    minLog: minLog,
                    maxLog: maxLog,
                    trackMetrics: trackMetrics
                )
                .padding(.horizontal, sliderPadding)
            }
        } else {
            Text("No DPI values available")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private func indicatorValues(from values: [Int]) -> [Int] {
        if values.count <= 7 {
            return values
        }

        let minLog = logValue(values.first ?? 1)
        let maxLog = logValue(values.last ?? 1)
        let targets: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]
        var indicators: [Int] = []

        for target in targets {
            let candidate = nearestValue(
                for: target,
                values: values,
                minLog: minLog,
                maxLog: maxLog
            )
            indicators.append(candidate)
        }

        let unique = Array(Set(indicators)).sorted()
        return unique
    }

    private func logValue(_ value: Int) -> Double {
        log10(Double(max(value, 1)))
    }

    private func normalizedLogValue(
        for value: Int,
        minLog: Double,
        maxLog: Double
    ) -> Double {
        guard maxLog > minLog else { return 0 }
        let logVal = logValue(value)
        return (logVal - minLog) / (maxLog - minLog)
    }

    private func nearestValue(
        for normalized: Double,
        values: [Int],
        minLog: Double,
        maxLog: Double
    ) -> Int {
        guard maxLog > minLog else { return values.first ?? selection }
        let targetLog = minLog + (maxLog - minLog) * normalized
        var closest = values.first ?? selection
        var closestDistance = Double.greatestFiniteMagnitude

        for value in values {
            let distance = abs(logValue(value) - targetLog)
            if distance < closestDistance {
                closest = value
                closestDistance = distance
            }
        }

        return closest
    }
}

private struct FullWidthSlider: NSViewRepresentable {
    @Binding var value: Double
    @Binding var trackMetrics: SliderTrackMetrics
    let range: ClosedRange<Double>
    var onEditingEnded: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onChange: { newValue in
                self.value = newValue
            },
            onEditingEnded: {
                self.onEditingEnded?()
            }
        )
    }

    func makeNSView(context: Context) -> FullWidthSliderView {
        FullWidthSliderView(
            value: value,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            coordinator: context.coordinator
        )
    }

    func updateNSView(_ nsView: FullWidthSliderView, context: Context) {
        nsView.slider.minValue = range.lowerBound
        nsView.slider.maxValue = range.upperBound
        if nsView.slider.doubleValue != value {
            nsView.slider.doubleValue = value
        }
        nsView.onTrackMetricsChange = { metrics in
            if self.trackMetrics != metrics {
                self.trackMetrics = metrics
            }
        }
    }

    final class Coordinator: NSObject {
        let onChange: (Double) -> Void
        let onEditingEnded: () -> Void

        init(onChange: @escaping (Double) -> Void, onEditingEnded: @escaping () -> Void) {
            self.onChange = onChange
            self.onEditingEnded = onEditingEnded
        }

        @objc func valueChanged(_ sender: NSSlider) {
            onChange(sender.doubleValue)
        }

        @objc func editingEnded(_ sender: NSSlider) {
            onEditingEnded()
        }
    }
}

private final class FullWidthSliderView: NSView {
    let slider: TrackingSlider
    var onTrackMetricsChange: ((SliderTrackMetrics) -> Void)?
    private var lastMetrics: SliderTrackMetrics = .zero

    init(
        value: Double,
        minValue: Double,
        maxValue: Double,
        coordinator: FullWidthSlider.Coordinator
    ) {
        self.slider = TrackingSlider(
            value: value,
            minValue: minValue,
            maxValue: maxValue,
            target: coordinator,
            action: #selector(FullWidthSlider.Coordinator.valueChanged(_:))
        )
        slider.onTrackingEnded = { [weak coordinator] in
            coordinator?.onEditingEnded()
        }
        super.init(frame: .zero)
        slider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(slider)

        let height = slider.intrinsicContentSize.height
        NSLayoutConstraint.activate([
            slider.leadingAnchor.constraint(equalTo: leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
            slider.heightAnchor.constraint(equalToConstant: height)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: NSView.noIntrinsicMetric,
            height: slider.intrinsicContentSize.height
        )
    }

    override func layout() {
        super.layout()
        guard let cell = slider.cell as? NSSliderCell else { return }
        let originalValue = slider.doubleValue
        let originalTarget = slider.target
        let originalAction = slider.action
        slider.target = nil
        slider.action = nil

        slider.doubleValue = slider.minValue
        let minKnobRect = cell.knobRect(flipped: slider.isFlipped)
        slider.doubleValue = slider.maxValue
        let maxKnobRect = cell.knobRect(flipped: slider.isFlipped)

        slider.doubleValue = originalValue
        slider.target = originalTarget
        slider.action = originalAction

        let startInset = minKnobRect.midX
        let endInset = slider.bounds.width - maxKnobRect.midX
        let metrics = SliderTrackMetrics(startInset: startInset, endInset: endInset)
        if metrics != lastMetrics {
            lastMetrics = metrics
            onTrackMetricsChange?(metrics)
        }
    }
}

/// NSSlider subclass that detects when mouse tracking ends
private final class TrackingSlider: NSSlider {
    var onTrackingEnded: (() -> Void)?
    private var isTracking = false

    init(
        value: Double,
        minValue: Double,
        maxValue: Double,
        target: AnyObject?,
        action: Selector?
    ) {
        super.init(frame: .zero)
        self.doubleValue = value
        self.minValue = minValue
        self.maxValue = maxValue
        self.target = target
        self.action = action
        self.isContinuous = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        isTracking = true
        super.mouseDown(with: event)
        // mouseDown doesn't return until tracking ends
        isTracking = false
        onTrackingEnded?()
    }
}

private struct SliderTrackMetrics: Equatable {
    let startInset: CGFloat
    let endInset: CGFloat

    static let zero = SliderTrackMetrics(startInset: 0, endInset: 0)
}

private struct DpiTickMarks: View {
    let values: [Int]
    let minLog: Double
    let maxLog: Double
    let trackMetrics: SliderTrackMetrics

    var body: some View {
        GeometryReader { proxy in
            let trackWidth = proxy.size.width - trackMetrics.startInset - trackMetrics.endInset
            ForEach(values, id: \.self) { value in
                let normalized = normalizedLogValue(for: value)
                let x = trackMetrics.startInset + (trackWidth * normalized)

                VStack(spacing: 2) {
                    Rectangle()
                        .frame(width: 1, height: 6)
                        .foregroundStyle(.secondary)
                    Text("\(value)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .position(x: x, y: 14)
            }
        }
        .frame(height: 26)
    }

    private func normalizedLogValue(for value: Int) -> Double {
        guard maxLog > minLog else { return 0 }
        let logVal = log10(Double(max(value, 1)))
        return (logVal - minLog) / (maxLog - minLog)
    }
}

// MARK: - Previews

#Preview("General Tab") {
    GeneralTabPreview()
        .frame(width: 500, height: 400)
}

#Preview("Mouse Tab - Connected") {
    MouseTabPreview(
        dpiSupported: true,
        pollingSupported: true,
        currentDPI: 1200,
        supportedDPIValues: [400, 800, 1200, 1600, 2400, 25600],
        currentPollingRate: 1000,
        supportedPollingRates: [125, 250, 500, 1000]
    )
    .frame(width: 500, height: 400)
}

#Preview("Mouse Tab - Disconnected") {
    MouseTabPreview(
        dpiSupported: false,
        pollingSupported: false,
        currentDPI: 0,
        supportedDPIValues: [],
        currentPollingRate: 0,
        supportedPollingRates: []
    )
    .frame(width: 500, height: 400)
}

#Preview("Device Tab - With Mappings") {
    DeviceTabPreview(
        buttonMappings: [
            ("Left Click", "Primary Click"),
            ("Right Click", "Secondary Click"),
            ("Middle Click", "Mission Control"),
            ("Back", "Back"),
            ("Forward", "Forward"),
            ("DPI Shift", "DPI Shift")
        ]
    )
    .frame(width: 500, height: 400)
}

#Preview("Device Tab - No Device") {
    DeviceTabPreview(buttonMappings: [])
        .frame(width: 500, height: 400)
}

#Preview("About Tab") {
    AboutTab()
        .frame(width: 500, height: 400)
}

#Preview("DPI Slider") {
    DpiSliderPreview()
        .padding()
        .frame(width: 450)
}

#Preview("Full Settings Window") {
    SettingsPreviewContainer()
        .frame(width: 500, height: 400)
}

// MARK: - Preview Containers

private struct GeneralTabPreview: View {
    @State private var launchAtLogin = false
    @State private var showPercentage = true

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                Toggle("Show Percentage", isOn: $showPercentage)
            }

            Section {
                Text("lsom requires Input Monitoring permission to communicate with your device.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

private struct MouseTabPreview: View {
    let dpiSupported: Bool
    let pollingSupported: Bool
    let currentDPI: Int
    let supportedDPIValues: [Int]
    let currentPollingRate: Int
    let supportedPollingRates: [Int]

    @State private var selectedDPI: Int = 800
    @State private var selectedPollingRate: Int = 1000

    var body: some View {
        Form {
            if dpiSupported && !supportedDPIValues.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Tracking Speed (DPI)")
                                .font(.headline)
                            Spacer()
                            Text("\(selectedDPI)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        LogDpiSlider(
                            supportedValues: supportedDPIValues,
                            selection: $selectedDPI
                        )
                    }
                }
            }

            if pollingSupported {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Polling Rate")
                                .font(.headline)
                            Text("Higher rates use more battery")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Picker("", selection: $selectedPollingRate) {
                            ForEach(supportedPollingRates, id: \.self) { rate in
                                Text("\(rate) Hz").tag(rate)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                }
            }

            if !dpiSupported && !pollingSupported {
                Section {
                    ContentUnavailableView(
                        "Device Not Connected",
                        systemImage: "computermouse",
                        description: Text("Connect your Logitech mouse to adjust settings.")
                    )
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .onAppear {
            selectedDPI = currentDPI > 0 ? currentDPI : (supportedDPIValues.first ?? 800)
            selectedPollingRate = currentPollingRate > 0 ? currentPollingRate : 1000
        }
    }
}

private struct DeviceTabPreview: View {
    let buttonMappings: [(name: String, action: String)]

    var body: some View {
        Form {
            Section("Button Assignments") {
                if buttonMappings.isEmpty {
                    ContentUnavailableView(
                        "No Button Data",
                        systemImage: "gamecontroller",
                        description: Text("Connect your mouse to view button assignments.")
                    )
                } else {
                    ForEach(buttonMappings, id: \.name) { mapping in
                        HStack {
                            Text(mapping.name)
                            Spacer()
                            Text(mapping.action)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct DpiSliderPreview: View {
    @State private var selectedDPI: Int = 1200

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tracking Speed (DPI)")
                    .font(.headline)
                Spacer()
                Text("\(selectedDPI)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            LogDpiSlider(
                supportedValues: [100, 400, 1600, 6400, 12800, 25600],
                selection: $selectedDPI
            )
        }
    }
}

private struct SettingsPreviewContainer: View {
    var body: some View {
        TabView {
            GeneralTabPreview()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            MouseTabPreview(
                dpiSupported: true,
                pollingSupported: true,
                currentDPI: 1200,
                supportedDPIValues: [100, 400, 1600, 6400, 12800, 25600],
                currentPollingRate: 1000,
                supportedPollingRates: [125, 250, 500, 1000]
            )
            .tabItem {
                Label("Mouse", systemImage: "computermouse")
            }

            DeviceTabPreview(
                buttonMappings: [
                    ("Left Click", "Primary Click"),
                    ("Right Click", "Secondary Click"),
                    ("Middle Click", "Mission Control")
                ]
            )
            .tabItem {
                Label("Device", systemImage: "gamecontroller")
            }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
    }
}
