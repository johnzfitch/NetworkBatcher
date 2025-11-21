import Foundation

// MARK: - Convenience Extensions

public extension NetworkBatcher {

    /// Enqueue a JSON-encodable event
    func enqueue<T: Encodable>(
        url: URL,
        event: T,
        priority: RequestPriority = .auto
    ) async throws -> UUID {
        let data = try JSONEncoder().encode(event)

        return try await enqueue(
            url: url,
            method: "POST",
            headers: ["Content-Type": "application/json"],
            body: data,
            priority: priority
        )
    }

    /// Enqueue a dictionary as JSON
    func enqueue(
        url: URL,
        json: [String: Any],
        priority: RequestPriority = .auto
    ) async throws -> UUID {
        let data = try JSONSerialization.data(withJSONObject: json)

        return try await enqueue(
            url: url,
            method: "POST",
            headers: ["Content-Type": "application/json"],
            body: data,
            priority: priority
        )
    }

    /// Enqueue form-encoded data
    func enqueue(
        url: URL,
        formData: [String: String],
        priority: RequestPriority = .auto
    ) async throws -> UUID {
        let body = formData
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        return try await enqueue(
            url: url,
            method: "POST",
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: body,
            priority: priority
        )
    }
}

// MARK: - URLSession Integration

public extension URLSession {

    /// Perform a request through NetworkBatcher if appropriate
    ///
    /// - If the request is to a deferrable domain, it gets batched
    /// - Otherwise, it's sent immediately
    /// - User-initiated requests trigger piggybacking
    func batchedData(for request: URLRequest) async throws -> (Data, URLResponse) {
        // Always notify about user activity for piggybacking
        await NetworkBatcher.shared.notifyUserNetworkActivity()

        // Check if this should be batched
        if let host = request.url?.host,
           NetworkBatcher.shared.configuration.deferrableDomains.contains(where: { host.contains($0) }) {

            try await NetworkBatcher.shared.enqueue(request, priority: .deferrable)

            // Return empty success for batched requests
            let emptyResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 202,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), emptyResponse)
        }

        // Send immediately
        return try await data(for: request)
    }
}

// MARK: - Debug/Development Helpers

#if DEBUG
public extension NetworkBatcher {

    /// Print current queue status
    func debugPrintStatus() async {
        let count = await queuedRequestCount
        let stats = try? await statistics()

        print("""
        ╔════════════════════════════════════════╗
        ║     NetworkBatcher Status              ║
        ╠════════════════════════════════════════╣
        ║ Queued Requests: \(String(format: "%-20d", count))  ║
        ║ Network: \(String(format: "%-27@", DeviceStateMonitor.shared.networkType.rawValue)) ║
        ║ Charging: \(String(format: "%-26@", DeviceStateMonitor.shared.isCharging ? "Yes" : "No")) ║
        ║ Battery: \(String(format: "%-27@", String(format: "%.0f%%", DeviceStateMonitor.shared.batteryLevel * 100))) ║
        \(stats.map { """
        ╠════════════════════════════════════════╣
        ║ Last 24h Stats:                        ║
        ║   Batches: \(String(format: "%-25d", $0.transmissionStats.batchCount))  ║
        ║   Requests: \(String(format: "%-24d", $0.transmissionStats.totalRequests))  ║
        ║   Wake-ups saved: \(String(format: "%-18d", $0.transmissionStats.estimatedWakeUpsSaved))  ║
        ║   Est. energy saved: \(String(format: "%-15.1f%%", $0.estimatedEnergySavedPercent)) ║
        """ } ?? "")
        ╚════════════════════════════════════════╝
        """)
    }

    /// Simulate various network conditions
    func simulateConditions(wifi: Bool, charging: Bool) {
        print("[DEBUG] Simulating: WiFi=\(wifi), Charging=\(charging)")
        // In debug mode, you could override DeviceStateMonitor values
    }
}
#endif
