import SwiftUI
import NetworkBatcher

struct ContentView: View {
    @StateObject private var viewModel = DemoViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Status Card
                    StatusCard(viewModel: viewModel)

                    // Quick Actions
                    QuickActionsSection(viewModel: viewModel)

                    // Statistics
                    StatisticsSection(viewModel: viewModel)

                    // Event Log
                    EventLogSection(viewModel: viewModel)
                }
                .padding()
            }
            .navigationTitle("NetworkBatcher")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings") {
                        viewModel.showSettings = true
                    }
                }
            }
            .sheet(isPresented: $viewModel.showSettings) {
                SettingsView(viewModel: viewModel)
            }
            .task {
                await viewModel.loadStatistics()
            }
        }
    }
}

// MARK: - Status Card

struct StatusCard: View {
    @ObservedObject var viewModel: DemoViewModel

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Device Status")
                        .font(.headline)
                    Text(viewModel.isEnabled ? "Batching Active" : "Batching Disabled")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $viewModel.isEnabled)
                    .labelsHidden()
            }

            Divider()

            HStack(spacing: 24) {
                StatusItem(
                    icon: viewModel.networkIcon,
                    title: "Network",
                    value: viewModel.networkType,
                    color: viewModel.networkColor
                )

                StatusItem(
                    icon: viewModel.batteryIcon,
                    title: "Battery",
                    value: viewModel.batteryStatus,
                    color: viewModel.batteryColor
                )

                StatusItem(
                    icon: "tray.full",
                    title: "Queued",
                    value: "\(viewModel.queuedCount)",
                    color: .orange
                )
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct StatusItem: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.caption)
                .fontWeight(.medium)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Quick Actions

struct QuickActionsSection: View {
    @ObservedObject var viewModel: DemoViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Simulate Events")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ActionButton(
                    title: "Analytics Event",
                    icon: "chart.bar",
                    color: .blue
                ) {
                    await viewModel.sendAnalyticsEvent()
                }

                ActionButton(
                    title: "Crash Report",
                    icon: "exclamationmark.triangle",
                    color: .red
                ) {
                    await viewModel.sendCrashReport()
                }

                ActionButton(
                    title: "Telemetry",
                    icon: "antenna.radiowaves.left.and.right",
                    color: .purple
                ) {
                    await viewModel.sendTelemetry()
                }

                ActionButton(
                    title: "Attribution",
                    icon: "link",
                    color: .green
                ) {
                    await viewModel.sendAttribution()
                }
            }

            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.sendBurst() }
                } label: {
                    Label("Send 10 Events", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await viewModel.flushQueue() }
                } label: {
                    Label("Flush Now", systemImage: "arrow.up.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () async -> Void

    @State private var isLoading = false

    var body: some View {
        Button {
            Task {
                isLoading = true
                await action()
                isLoading = false
            }
        } label: {
            VStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .frame(height: 24)
                } else {
                    Image(systemName: icon)
                        .font(.title3)
                }

                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color.opacity(0.1))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Statistics Section

struct StatisticsSection: View {
    @ObservedObject var viewModel: DemoViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Energy Savings (24h)")
                    .font(.headline)

                Spacer()

                Button("Refresh") {
                    Task { await viewModel.loadStatistics() }
                }
                .font(.caption)
            }

            VStack(spacing: 16) {
                HStack {
                    StatBox(
                        title: "Batches Sent",
                        value: "\(viewModel.stats?.transmissionStats.batchCount ?? 0)",
                        icon: "shippingbox"
                    )

                    StatBox(
                        title: "Requests Batched",
                        value: "\(viewModel.stats?.transmissionStats.totalRequests ?? 0)",
                        icon: "doc.on.doc"
                    )
                }

                HStack {
                    StatBox(
                        title: "Wake-ups Saved",
                        value: "\(viewModel.stats?.transmissionStats.estimatedWakeUpsSaved ?? 0)",
                        icon: "battery.100.bolt"
                    )

                    StatBox(
                        title: "Est. Energy Saved",
                        value: String(format: "%.0f%%", viewModel.stats?.estimatedEnergySavedPercent ?? 0),
                        icon: "leaf"
                    )
                }

                // Energy Savings Visualization
                if let stats = viewModel.stats, stats.transmissionStats.totalRequests > 0 {
                    EnergySavingsBar(
                        saved: stats.transmissionStats.estimatedWakeUpsSaved,
                        total: stats.transmissionStats.totalRequests
                    )
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct StatBox: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 40)

            VStack(alignment: .leading) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct EnergySavingsBar: View {
    let saved: Int
    let total: Int

    var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(saved) / Double(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Radio Activity Reduction")
                .font(.caption)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background (what it would have been)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.red.opacity(0.3))

                    // Actual (after batching)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.green)
                        .frame(width: geo.size.width * (1 - percentage))
                }
            }
            .frame(height: 24)

            HStack {
                Label("Without batching: \(total) wake-ups", systemImage: "xmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.red)

                Spacer()

                Label("With batching: \(total - saved)", systemImage: "checkmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
    }
}

// MARK: - Event Log

struct EventLogSection: View {
    @ObservedObject var viewModel: DemoViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Event Log")
                    .font(.headline)

                Spacer()

                Button("Clear") {
                    viewModel.clearLog()
                }
                .font(.caption)
            }

            if viewModel.eventLog.isEmpty {
                Text("No events yet. Tap buttons above to simulate SDK traffic.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(viewModel.eventLog.suffix(10).reversed()) { event in
                    EventLogRow(event: event)
                }
            }
        }
    }
}

struct EventLogRow: View {
    let event: LogEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.icon)
                .foregroundStyle(event.color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.caption)
                    .fontWeight(.medium)

                Text(event.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(event.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var viewModel: DemoViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Timing") {
                    Stepper(
                        "Max Deferral: \(Int(viewModel.maxDeferralTime / 60)) min",
                        value: $viewModel.maxDeferralTime,
                        in: 60...3600,
                        step: 60
                    )

                    Stepper(
                        "Batch Interval: \(Int(viewModel.batchInterval)) sec",
                        value: $viewModel.batchInterval,
                        in: 10...300,
                        step: 10
                    )
                }

                Section("Conditions") {
                    Toggle("Prefer WiFi", isOn: $viewModel.preferWiFi)
                    Toggle("Prefer Charging", isOn: $viewModel.preferCharging)
                    Toggle("Piggyback on User Requests", isOn: $viewModel.piggybackEnabled)
                    Toggle("Flush on Background", isOn: $viewModel.flushOnBackground)
                }

                Section("Presets") {
                    Button("Battery Saver") {
                        viewModel.applyPreset(.batterySaver)
                    }

                    Button("Balanced") {
                        viewModel.applyPreset(.balanced)
                    }

                    Button("Minimal Batching") {
                        viewModel.applyPreset(.minimal)
                    }
                }

                Section("Debug") {
                    Toggle("Enable Logging", isOn: $viewModel.loggingEnabled)

                    Button("Clear All Data", role: .destructive) {
                        Task { await viewModel.clearAllData() }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
