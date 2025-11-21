import XCTest
@testable import NetworkBatcher

final class NetworkBatcherTests: XCTestCase {

    // MARK: - DeferredRequest Tests

    func testDeferredRequestCreation() {
        let url = URL(string: "https://api.amplitude.com/event")!
        let request = DeferredRequest(
            url: url,
            method: "POST",
            headers: ["Content-Type": "application/json"],
            body: "{}".data(using: .utf8),
            priority: .deferrable
        )

        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.priority, .deferrable)
        XCTAssertEqual(request.domain, "api.amplitude.com")
        XCTAssertFalse(request.isExpired)
    }

    func testDeferredRequestExpiry() {
        let url = URL(string: "https://api.test.com/event")!
        let request = DeferredRequest(
            url: url,
            enqueuedAt: Date().addingTimeInterval(-1000),  // 1000 seconds ago
            maxDeferralTime: 900  // 15 minutes = 900 seconds
        )

        XCTAssertTrue(request.isExpired)
        XCTAssertEqual(request.timeUntilExpiry, 0)
    }

    func testDeferredRequestPayloadSize() {
        let url = URL(string: "https://api.test.com/event")!
        let body = String(repeating: "x", count: 100).data(using: .utf8)!

        let request = DeferredRequest(
            url: url,
            headers: ["X-Custom": "value"],
            body: body
        )

        // URL + headers + body
        XCTAssertGreaterThan(request.payloadSize, 100)
    }

    func testURLRequestConversion() {
        let url = URL(string: "https://api.test.com/event")!
        let request = DeferredRequest(
            url: url,
            method: "POST",
            headers: ["Content-Type": "application/json", "X-API-Key": "test"],
            body: "{\"event\":\"test\"}".data(using: .utf8)
        )

        let urlRequest = request.toURLRequest()

        XCTAssertEqual(urlRequest.url, url)
        XCTAssertEqual(urlRequest.httpMethod, "POST")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "X-API-Key"), "test")
        XCTAssertNotNil(urlRequest.httpBody)
    }

    // MARK: - Priority Tests

    func testPriorityOrdering() {
        XCTAssertLessThan(RequestPriority.immediate.rawValue, RequestPriority.soon.rawValue)
        XCTAssertLessThan(RequestPriority.soon.rawValue, RequestPriority.deferrable.rawValue)
        XCTAssertLessThan(RequestPriority.deferrable.rawValue, RequestPriority.bulk.rawValue)
    }

    func testPriorityMaxDeferralTime() {
        XCTAssertEqual(RequestPriority.immediate.maxDeferralTime, 0)
        XCTAssertEqual(RequestPriority.soon.maxDeferralTime, 30)
        XCTAssertEqual(RequestPriority.deferrable.maxDeferralTime, 15 * 60)
        XCTAssertEqual(RequestPriority.bulk.maxDeferralTime, 60 * 60)
    }

    // MARK: - Configuration Tests

    func testDefaultConfiguration() {
        let config = BatcherConfiguration()

        XCTAssertEqual(config.maxDeferralTime, 15 * 60)
        XCTAssertEqual(config.minBatchInterval, 60)
        XCTAssertEqual(config.maxQueueSize, 100)
        XCTAssertTrue(config.preferWiFi)
        XCTAssertTrue(config.preferCharging)
        XCTAssertTrue(config.piggybackOnUserRequests)
        XCTAssertTrue(config.flushOnBackground)
    }

    func testBatterySaverPreset() {
        let config = BatcherConfiguration.batterySaver

        XCTAssertEqual(config.maxDeferralTime, 30 * 60)  // 30 minutes
        XCTAssertEqual(config.minBatchInterval, 5 * 60)  // 5 minutes
        XCTAssertTrue(config.requireWiFiForBulk)
    }

    func testMinimalPreset() {
        let config = BatcherConfiguration.minimal

        XCTAssertEqual(config.maxDeferralTime, 5 * 60)  // 5 minutes
        XCTAssertEqual(config.minBatchInterval, 30)  // 30 seconds
        XCTAssertFalse(config.requireWiFiForBulk)
    }

    func testDefaultDomainClassification() {
        // Immediate domains
        XCTAssertTrue(BatcherConfiguration.defaultImmediateDomains.contains("api.stripe.com"))
        XCTAssertTrue(BatcherConfiguration.defaultImmediateDomains.contains("api.apple.com"))

        // Deferrable domains
        XCTAssertTrue(BatcherConfiguration.defaultDeferrableDomains.contains("app-measurement.com"))
        XCTAssertTrue(BatcherConfiguration.defaultDeferrableDomains.contains("api.amplitude.com"))
        XCTAssertTrue(BatcherConfiguration.defaultDeferrableDomains.contains("api.mixpanel.com"))
        XCTAssertTrue(BatcherConfiguration.defaultDeferrableDomains.contains("sentry.io"))
    }

    // MARK: - Network Type Tests

    func testNetworkTypeDescriptions() {
        XCTAssertEqual(NetworkType.wifi.rawValue, "WiFi")
        XCTAssertEqual(NetworkType.cellular.rawValue, "Cellular")
        XCTAssertEqual(NetworkType.none.rawValue, "None")
    }

    // MARK: - Transmission Decision Tests

    func testTransmissionDecision() {
        let transmit = TransmissionDecision.transmit(reason: "Test")
        let wait = TransmissionDecision.wait(reason: "Test")

        XCTAssertTrue(transmit.shouldTransmit)
        XCTAssertFalse(wait.shouldTransmit)
        XCTAssertEqual(transmit.reason, "Test")
        XCTAssertEqual(wait.reason, "Test")
    }

    // MARK: - Statistics Tests

    func testTransmissionStats() {
        let stats = TransmissionStats(batchCount: 10, totalRequests: 100, totalBytes: 50000)

        XCTAssertEqual(stats.averageRequestsPerBatch, 10.0)
        XCTAssertEqual(stats.estimatedWakeUpsSaved, 90)  // 100 requests - 10 batches
    }

    func testTransmissionStatsEmpty() {
        let stats = TransmissionStats(batchCount: 0, totalRequests: 0, totalBytes: 0)

        XCTAssertEqual(stats.averageRequestsPerBatch, 0)
        XCTAssertEqual(stats.estimatedWakeUpsSaved, 0)
    }
}

// MARK: - Request Store Tests

final class RequestStoreTests: XCTestCase {

    var store: RequestStore!

    override func setUp() async throws {
        store = try RequestStore(identifier: "test-\(UUID().uuidString)")
    }

    func testSaveAndFetch() async throws {
        let url = URL(string: "https://api.test.com/event")!
        let request = DeferredRequest(
            url: url,
            method: "POST",
            headers: ["Content-Type": "application/json"],
            body: "{\"test\":true}".data(using: .utf8),
            priority: .deferrable
        )

        try await store.save(request)

        let fetched = try await store.fetchAll()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, request.id)
        XCTAssertEqual(fetched.first?.url, request.url)
        XCTAssertEqual(fetched.first?.method, request.method)
    }

    func testDelete() async throws {
        let url = URL(string: "https://api.test.com/event")!
        let request = DeferredRequest(url: url, priority: .deferrable)

        try await store.save(request)
        XCTAssertEqual(try await store.count(), 1)

        try await store.delete(id: request.id)
        XCTAssertEqual(try await store.count(), 0)
    }

    func testFetchBatch() async throws {
        let url = URL(string: "https://api.test.com/event")!

        // Add 10 requests
        for _ in 0..<10 {
            let request = DeferredRequest(url: url, priority: .deferrable)
            try await store.save(request)
        }

        // Fetch batch of 5
        let batch = try await store.fetchBatch(limit: 5)
        XCTAssertEqual(batch.count, 5)

        // Total should still be 10
        XCTAssertEqual(try await store.count(), 10)
    }

    func testDeleteExpired() async throws {
        let url = URL(string: "https://api.test.com/event")!

        // Add expired request
        let expired = DeferredRequest(
            url: url,
            priority: .deferrable,
            enqueuedAt: Date().addingTimeInterval(-1000),
            maxDeferralTime: 100
        )
        try await store.save(expired)

        // Add fresh request
        let fresh = DeferredRequest(
            url: url,
            priority: .deferrable,
            maxDeferralTime: 1000
        )
        try await store.save(fresh)

        XCTAssertEqual(try await store.count(), 2)

        let deleted = try await store.deleteExpired()
        XCTAssertEqual(deleted, 1)
        XCTAssertEqual(try await store.count(), 1)
    }

    func testClear() async throws {
        let url = URL(string: "https://api.test.com/event")!

        for _ in 0..<5 {
            try await store.save(DeferredRequest(url: url))
        }

        XCTAssertEqual(try await store.count(), 5)

        try await store.clear()
        XCTAssertEqual(try await store.count(), 0)
    }

    func testTransmissionLogging() async throws {
        try await store.logTransmission(
            requestCount: 10,
            totalBytes: 5000,
            networkType: "WiFi",
            isCharging: true,
            triggerReason: "Test"
        )

        let stats = try await store.transmissionStats(since: Date().addingTimeInterval(-60))
        XCTAssertEqual(stats.batchCount, 1)
        XCTAssertEqual(stats.totalRequests, 10)
        XCTAssertEqual(stats.totalBytes, 5000)
    }
}
