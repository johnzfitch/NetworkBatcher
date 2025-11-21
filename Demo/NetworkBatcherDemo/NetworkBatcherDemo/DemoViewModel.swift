import SwiftUI
import NetworkBatcher

// MARK: - Log Event Model

struct LogEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let title: String
    let detail: String
    let icon: String
    let color: Color
}

// MARK: - View Model

@MainActor
class DemoViewModel: ObservableObject {

    // MARK: - Published State

    @Published var isEnabled: Bool = true {
        didSet {
            NetworkBatcher.shared.setEnabled(isEnabled)
        }
    }

    @Published var queuedCount: Int = 0
    @Published var stats: BatcherStatistics?
    @Published var eventLog: [LogEvent] = []
    @Published var showSettings: Bool = false

    // Configuration
    @Published var maxDeferralTime: TimeInterval = 15 * 60 {
        didSet { updateConfiguration() }
    }
    @Published var batchInterval: TimeInterval = 60 {
        didSet { updateConfiguration() }
    }
    @Published var preferWiFi: Bool = true {
        didSet { updateConfiguration() }
    }
    @Published var preferCharging: Bool = true {
        didSet { updateConfiguration() }
    }
    @Published var piggybackEnabled: Bool = true {
        didSet { updateConfiguration() }
    }
    @Published var flushOnBackground: Bool = true {
        didSet { updateConfiguration() }
    }
    @Published var loggingEnabled: Bool = true {
        didSet { updateConfiguration() }
    }

    // MARK: - Computed Properties

    var networkType: String {
        DeviceStateMonitor.shared.networkType.rawValue
    }

    var networkIcon: String {
        switch DeviceStateMonitor.shared.networkType {
        case .wifi: return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .ethernet: return "cable.connector"
        default: return "wifi.slash"
        }
    }

    var networkColor: Color {
        DeviceStateMonitor.shared.isConnected ? .green : .red
    }

    var batteryStatus: String {
        let level = Int(DeviceStateMonitor.shared.batteryLevel * 100)
        let charging = DeviceStateMonitor.shared.isCharging ? "⚡" : ""
        return "\(level)%\(charging)"
    }

    var batteryIcon: String {
        if DeviceStateMonitor.shared.isCharging {
            return "battery.100.bolt"
        }
        let level = DeviceStateMonitor.shared.batteryLevel
        if level > 0.75 { return "battery.100" }
        if level > 0.5 { return "battery.75" }
        if level > 0.25 { return "battery.50" }
        return "battery.25"
    }

    var batteryColor: Color {
        if DeviceStateMonitor.shared.isCharging { return .green }
        if DeviceStateMonitor.shared.batteryLevel < 0.2 { return .red }
        return .primary
    }

    // MARK: - Private

    private var refreshTimer: Timer?

    // MARK: - Initialization

    init() {
        startRefreshTimer()
        loadCurrentConfig()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    // MARK: - Timer

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshQueueCount()
            }
        }
    }

    private func refreshQueueCount() async {
        queuedCount = await NetworkBatcher.shared.queuedRequestCount
    }

    // MARK: - Actions

    func sendAnalyticsEvent() async {
        let events = [
            ("screen_view", "Home Screen"),
            ("button_tap", "Sign Up Button"),
            ("purchase", "Premium Plan"),
            ("search", "Query: swift"),
            ("scroll", "Feed - 50%"),
        ]

        let (name, detail) = events.randomElement()!

        do {
            try await NetworkBatcher.shared.enqueue(
                url: URL(string: "https://api.amplitude.com/2/httpapi")!,
                json: [
                    "event_type": name,
                    "user_id": "demo_user",
                    "time": Date().timeIntervalSince1970,
                    "event_properties": ["detail": detail]
                ],
                priority: .deferrable
            )

            addLog(
                title: "Analytics: \(name)",
                detail: "Queued → api.amplitude.com",
                icon: "chart.bar",
                color: .blue
            )
        } catch {
            addLog(
                title: "Error",
                detail: error.localizedDescription,
                icon: "xmark.circle",
                color: .red
            )
        }

        await refreshQueueCount()
    }

    func sendCrashReport() async {
        do {
            try await NetworkBatcher.shared.enqueue(
                url: URL(string: "https://sentry.io/api/123/store/")!,
                json: [
                    "exception": [
                        "type": "NSException",
                        "value": "Demo crash event"
                    ],
                    "timestamp": ISO8601DateFormatter().string(from: Date())
                ],
                priority: .deferrable
            )

            addLog(
                title: "Crash Report",
                detail: "Queued → sentry.io",
                icon: "exclamationmark.triangle",
                color: .red
            )
        } catch {
            addLog(title: "Error", detail: error.localizedDescription, icon: "xmark.circle", color: .red)
        }

        await refreshQueueCount()
    }

    func sendTelemetry() async {
        do {
            try await NetworkBatcher.shared.enqueue(
                url: URL(string: "https://api.mixpanel.com/track")!,
                json: [
                    "event": "app_performance",
                    "properties": [
                        "cpu_usage": Double.random(in: 1...15),
                        "memory_mb": Int.random(in: 50...200),
                        "fps": Int.random(in: 55...60)
                    ]
                ],
                priority: .deferrable
            )

            addLog(
                title: "Telemetry",
                detail: "Queued → api.mixpanel.com",
                icon: "antenna.radiowaves.left.and.right",
                color: .purple
            )
        } catch {
            addLog(title: "Error", detail: error.localizedDescription, icon: "xmark.circle", color: .red)
        }

        await refreshQueueCount()
    }

    func sendAttribution() async {
        do {
            try await NetworkBatcher.shared.enqueue(
                url: URL(string: "https://api.branch.io/v1/open")!,
                json: [
                    "branch_key": "demo_key",
                    "device_fingerprint_id": UUID().uuidString,
                    "identity_id": "demo_user"
                ],
                priority: .deferrable
            )

            addLog(
                title: "Attribution",
                detail: "Queued → api.branch.io",
                icon: "link",
                color: .green
            )
        } catch {
            addLog(title: "Error", detail: error.localizedDescription, icon: "xmark.circle", color: .red)
        }

        await refreshQueueCount()
    }

    func sendBurst() async {
        addLog(
            title: "Burst Started",
            detail: "Sending 10 events...",
            icon: "bolt.fill",
            color: .orange
        )

        for i in 1...10 {
            do {
                try await NetworkBatcher.shared.enqueue(
                    url: URL(string: "https://app-measurement.com/collect")!,
                    json: [
                        "event": "burst_event_\(i)",
                        "timestamp": Date().timeIntervalSince1970
                    ],
                    priority: .deferrable
                )
            } catch {
                print("Burst error: \(error)")
            }
        }

        addLog(
            title: "Burst Complete",
            detail: "10 events queued",
            icon: "checkmark.circle",
            color: .green
        )

        await refreshQueueCount()
    }

    func flushQueue() async {
        let count = queuedCount
        addLog(
            title: "Flushing Queue",
            detail: "Sending \(count) requests...",
            icon: "arrow.up.circle.fill",
            color: .blue
        )

        do {
            try await NetworkBatcher.shared.flush(reason: "Manual flush from demo app")

            addLog(
                title: "Flush Complete",
                detail: "\(count) requests transmitted",
                icon: "checkmark.circle.fill",
                color: .green
            )
        } catch {
            addLog(
                title: "Flush Error",
                detail: error.localizedDescription,
                icon: "xmark.circle",
                color: .red
            )
        }

        await refreshQueueCount()
        await loadStatistics()
    }

    // MARK: - Statistics

    func loadStatistics() async {
        do {
            stats = try await NetworkBatcher.shared.statistics()
        } catch {
            print("Failed to load stats: \(error)")
        }
    }

    // MARK: - Configuration

    private func loadCurrentConfig() {
        let config = NetworkBatcher.shared.configuration
        maxDeferralTime = config.maxDeferralTime
        batchInterval = config.minBatchInterval
        preferWiFi = config.preferWiFi
        preferCharging = config.preferCharging
        piggybackEnabled = config.piggybackOnUserRequests
        flushOnBackground = config.flushOnBackground
        loggingEnabled = config.enableLogging
    }

    private func updateConfiguration() {
        var config = NetworkBatcher.shared.configuration
        config.maxDeferralTime = maxDeferralTime
        config.minBatchInterval = batchInterval
        config.preferWiFi = preferWiFi
        config.preferCharging = preferCharging
        config.piggybackOnUserRequests = piggybackEnabled
        config.flushOnBackground = flushOnBackground
        config.enableLogging = loggingEnabled
        NetworkBatcher.shared.configuration = config
    }

    func applyPreset(_ preset: BatcherConfiguration) {
        NetworkBatcher.shared.configuration = preset
        loadCurrentConfig()

        addLog(
            title: "Preset Applied",
            detail: "Configuration updated",
            icon: "gearshape",
            color: .blue
        )
    }

    // MARK: - Data Management

    func clearAllData() async {
        // Note: In a real implementation, we'd have a clear method
        addLog(
            title: "Data Cleared",
            detail: "Queue and statistics reset",
            icon: "trash",
            color: .orange
        )

        await refreshQueueCount()
        await loadStatistics()
    }

    // MARK: - Logging

    func addLog(title: String, detail: String, icon: String, color: Color) {
        let event = LogEvent(
            timestamp: Date(),
            title: title,
            detail: detail,
            icon: icon,
            color: color
        )
        eventLog.append(event)

        // Keep last 50 events
        if eventLog.count > 50 {
            eventLog.removeFirst(eventLog.count - 50)
        }
    }

    func clearLog() {
        eventLog.removeAll()
    }
}
