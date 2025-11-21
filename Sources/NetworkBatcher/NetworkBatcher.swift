import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// NetworkBatcher: Energy-efficient request batching for iOS
///
/// Reduces battery drain by intelligently batching non-essential network requests
/// (analytics, telemetry, crash reports) and transmitting them when conditions are optimal.
///
/// Based on Apple's energy efficiency guidelines:
/// - Batching reduces "fixed cost" of radio wake-ups
/// - Piggybacking on existing radio activity
/// - Preferring WiFi over cellular
/// - Deferring non-essential work
///
/// Usage:
/// ```swift
/// // Enqueue a request for later
/// await NetworkBatcher.shared.enqueue(url: analyticsURL, body: eventData)
///
/// // Force flush (e.g., on important user action)
/// await NetworkBatcher.shared.flush()
/// ```
@MainActor
public final class NetworkBatcher {

    /// Shared instance
    public static let shared = NetworkBatcher()

    // MARK: - Public Properties

    /// Configuration options
    public var configuration: BatcherConfiguration {
        didSet {
            scheduleNextBatchCheck()
        }
    }

    /// Whether the batcher is currently enabled
    public private(set) var isEnabled: Bool = true

    /// Number of requests currently queued
    public var queuedRequestCount: Int {
        get async {
            do {
                return try await store.count()
            } catch {
                return 0
            }
        }
    }

    // MARK: - Private Properties

    private let store: RequestStore
    private let deviceMonitor = DeviceStateMonitor.shared
    private var urlSession: URLSession
    private var batchTimer: Timer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var lastTransmissionTime: Date = .distantPast
    private var isTransmitting: Bool = false

    // MARK: - Initialization

    public init(configuration: BatcherConfiguration = .balanced, identifier: String = "default") {
        self.configuration = configuration

        do {
            self.store = try RequestStore(identifier: identifier)
        } catch {
            fatalError("NetworkBatcher: Failed to initialize store: \(error)")
        }

        // Configure URLSession for efficient batching
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.httpMaximumConnectionsPerHost = 4
        sessionConfig.timeoutIntervalForRequest = 30
        sessionConfig.timeoutIntervalForResource = 60
        sessionConfig.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: sessionConfig)

        setupLifecycleObservers()
        scheduleNextBatchCheck()

        log("NetworkBatcher initialized")
    }

    // MARK: - Public API

    /// Enqueue a request for batched transmission
    ///
    /// - Parameters:
    ///   - url: The URL to send to
    ///   - method: HTTP method (default: POST)
    ///   - headers: Request headers
    ///   - body: Request body data
    ///   - priority: Transmission priority (default: auto)
    /// - Returns: The ID of the enqueued request
    @discardableResult
    public func enqueue(
        url: URL,
        method: String = "POST",
        headers: [String: String] = [:],
        body: Data? = nil,
        priority: RequestPriority = .auto
    ) async throws -> UUID {

        guard isEnabled else {
            throw BatcherError.disabled
        }

        // Classify priority if auto
        let effectivePriority = priority == .auto
            ? classifyPriority(for: url)
            : priority

        // Immediate priority bypasses queue
        if effectivePriority == .immediate {
            try await sendImmediately(url: url, method: method, headers: headers, body: body)
            return UUID()  // Immediate requests don't get tracked
        }

        // Create deferred request
        let request = DeferredRequest(
            url: url,
            method: method,
            headers: headers,
            body: body,
            priority: effectivePriority,
            maxDeferralTime: configuration.maxDeferralTime
        )

        // Persist to store
        try await store.save(request)

        log("Enqueued request to \(url.host ?? "unknown") with priority \(effectivePriority)")

        // Check if we should transmit now
        await checkAndTransmitIfNeeded()

        return request.id
    }

    /// Enqueue a request from a URLRequest
    @discardableResult
    public func enqueue(_ urlRequest: URLRequest, priority: RequestPriority = .auto) async throws -> UUID {
        guard let url = urlRequest.url else {
            throw BatcherError.invalidRequest
        }

        return try await enqueue(
            url: url,
            method: urlRequest.httpMethod ?? "GET",
            headers: urlRequest.allHTTPHeaderFields ?? [:],
            body: urlRequest.httpBody,
            priority: priority
        )
    }

    /// Force flush all queued requests
    ///
    /// Use sparingly - defeats the purpose of batching.
    /// Good for: app termination, user logout, critical sync points
    public func flush(reason: String = "Manual flush") async throws {
        log("Flush requested: \(reason)")
        try await transmitBatch(force: true, reason: reason)
    }

    /// Notify that user-initiated network activity occurred
    ///
    /// Enables piggybacking - will check if queued requests can be sent
    /// while the radio is already warm.
    public func notifyUserNetworkActivity() async {
        deviceMonitor.recordUserNetworkActivity()

        if configuration.piggybackOnUserRequests {
            await checkAndTransmitIfNeeded()
        }
    }

    /// Enable or disable the batcher
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled

        if enabled {
            scheduleNextBatchCheck()
        } else {
            batchTimer?.invalidate()
            batchTimer = nil
        }
    }

    /// Get statistics about batching efficiency
    public func statistics(since: Date = Date().addingTimeInterval(-24 * 60 * 60)) async throws -> BatcherStatistics {
        let transmissionStats = try await store.transmissionStats(since: since)
        let queuedCount = try await store.count()
        let queuedSize = try await store.totalPayloadSize()

        return BatcherStatistics(
            transmissionStats: transmissionStats,
            queuedRequests: queuedCount,
            queuedBytes: queuedSize,
            networkType: deviceMonitor.networkType,
            isCharging: deviceMonitor.isCharging,
            batteryLevel: deviceMonitor.batteryLevel
        )
    }

    // MARK: - Private: Transmission Logic

    private func checkAndTransmitIfNeeded() async {
        guard !isTransmitting else { return }

        // Get queue state
        let count: Int
        let totalSize: Int
        do {
            count = try await store.count()
            totalSize = try await store.totalPayloadSize()
        } catch {
            log("Error checking queue: \(error)")
            return
        }

        guard count > 0 else { return }

        // Check if forced transmission needed
        let shouldForce = count >= configuration.maxQueueSize ||
                          totalSize >= configuration.maxPayloadSize

        if shouldForce {
            try? await transmitBatch(force: true, reason: "Queue limits reached")
            return
        }

        // Check time since last transmission
        let timeSinceLastTransmit = Date().timeIntervalSince(lastTransmissionTime)
        if timeSinceLastTransmit < configuration.minBatchInterval {
            return
        }

        // Check device conditions
        let decision = deviceMonitor.shouldTransmit(config: configuration, priority: .deferrable)

        if decision.shouldTransmit {
            try? await transmitBatch(force: false, reason: decision.reason)
        }
    }

    private func transmitBatch(force: Bool, reason: String) async throws {
        guard !isTransmitting else { return }
        isTransmitting = true
        defer { isTransmitting = false }

        // Clean expired requests first
        let expiredCount = try await store.deleteExpired()
        if expiredCount > 0 {
            log("Deleted \(expiredCount) expired requests")
        }

        // Fetch batch
        let requests = try await store.fetchBatch(limit: configuration.maxBatchSize)
        guard !requests.isEmpty else { return }

        log("Transmitting batch of \(requests.count) requests. Reason: \(reason)")

        var successfulIDs: [UUID] = []
        var totalBytes = 0

        // Transmit requests
        // Group by host for connection reuse
        let byHost = Dictionary(grouping: requests) { $0.domain }

        for (host, hostRequests) in byHost {
            for request in hostRequests {
                do {
                    let urlRequest = request.toURLRequest()
                    let (_, response) = try await urlSession.data(for: urlRequest)

                    if let httpResponse = response as? HTTPURLResponse,
                       (200...299).contains(httpResponse.statusCode) {
                        successfulIDs.append(request.id)
                        totalBytes += request.payloadSize
                    } else {
                        log("Request to \(host) returned non-success status")
                    }
                } catch {
                    log("Request to \(host) failed: \(error.localizedDescription)")
                    // Keep in queue for retry
                }
            }
        }

        // Remove successful requests
        if !successfulIDs.isEmpty {
            try await store.delete(ids: successfulIDs)
        }

        // Log transmission
        try await store.logTransmission(
            requestCount: successfulIDs.count,
            totalBytes: totalBytes,
            networkType: deviceMonitor.networkType.rawValue,
            isCharging: deviceMonitor.isCharging,
            triggerReason: reason
        )

        lastTransmissionTime = Date()

        log("Batch complete: \(successfulIDs.count)/\(requests.count) succeeded")
    }

    private func sendImmediately(url: URL, method: String, headers: [String: String], body: Data?) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (_, response) = try await urlSession.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw BatcherError.requestFailed(statusCode: httpResponse.statusCode)
        }

        // Notify that network activity occurred (for piggybacking)
        deviceMonitor.recordUserNetworkActivity()
        await checkAndTransmitIfNeeded()
    }

    // MARK: - Private: Priority Classification

    private func classifyPriority(for url: URL) -> RequestPriority {
        guard let host = url.host?.lowercased() else {
            return .deferrable
        }

        // Check immediate domains
        for domain in configuration.immediateDomains {
            if host.contains(domain.lowercased()) {
                return .immediate
            }
        }

        // Check deferrable domains
        for domain in configuration.deferrableDomains {
            if host.contains(domain.lowercased()) {
                return .deferrable
            }
        }

        // Unknown domains get "soon" priority
        return .soon
    }

    // MARK: - Private: Lifecycle

    private func setupLifecycleObservers() {
        #if canImport(UIKit) && !os(watchOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterBackground),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        #endif
    }

    @objc private func appWillEnterBackground() {
        guard configuration.flushOnBackground else { return }

        #if canImport(UIKit) && !os(watchOS)
        // Begin background task
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }

        // Flush queue
        Task { @MainActor in
            try? await self.flush(reason: "App entering background")
            self.endBackgroundTask()
        }
        #endif
    }

    @objc private func appDidBecomeActive() {
        scheduleNextBatchCheck()
    }

    private func endBackgroundTask() {
        #if canImport(UIKit) && !os(watchOS)
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
        #endif
    }

    // MARK: - Private: Timer

    private func scheduleNextBatchCheck() {
        batchTimer?.invalidate()

        batchTimer = Timer.scheduledTimer(withTimeInterval: configuration.minBatchInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkAndTransmitIfNeeded()
            }
        }
    }

    // MARK: - Private: Logging

    private func log(_ message: String) {
        guard configuration.enableLogging else { return }
        print("[NetworkBatcher] \(message)")
    }
}

// MARK: - Supporting Types

public struct BatcherStatistics: Sendable {
    public let transmissionStats: TransmissionStats
    public let queuedRequests: Int
    public let queuedBytes: Int
    public let networkType: NetworkType
    public let isCharging: Bool
    public let batteryLevel: Float

    /// Estimated energy saved (rough approximation)
    public var estimatedEnergySavedPercent: Double {
        let wakeUpsSaved = transmissionStats.estimatedWakeUpsSaved
        let totalRequests = transmissionStats.totalRequests

        guard totalRequests > 0 else { return 0 }

        // Each wake-up avoided = ~12 seconds of radio time saved
        // This is a rough estimate based on Apple's documentation
        return min(100, Double(wakeUpsSaved) / Double(totalRequests) * 100)
    }
}

public enum BatcherError: Error, LocalizedError {
    case disabled
    case invalidRequest
    case requestFailed(statusCode: Int)
    case storeError(Error)

    public var errorDescription: String? {
        switch self {
        case .disabled:
            return "NetworkBatcher is disabled"
        case .invalidRequest:
            return "Invalid request"
        case .requestFailed(let code):
            return "Request failed with status \(code)"
        case .storeError(let error):
            return "Store error: \(error.localizedDescription)"
        }
    }
}
