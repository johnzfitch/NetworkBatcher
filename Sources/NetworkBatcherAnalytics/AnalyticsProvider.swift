import Foundation
import NetworkBatcher

/// Protocol for analytics providers that can be batched
public protocol BatchableAnalyticsProvider: AnyObject {
    /// Unique identifier for this provider
    var providerID: String { get }

    /// Endpoint URL for analytics events
    var endpoint: URL { get }

    /// Serialize an event to data
    func serialize(event: AnalyticsEvent) throws -> Data

    /// Optional: HTTP headers for requests
    var headers: [String: String] { get }

    /// Priority for this provider's events
    var defaultPriority: RequestPriority { get }
}

public extension BatchableAnalyticsProvider {
    var headers: [String: String] { [:] }
    var defaultPriority: RequestPriority { .deferrable }
}

/// Generic analytics event
public struct AnalyticsEvent: Codable, Sendable {
    public let name: String
    public let timestamp: Date
    public let properties: [String: AnyCodable]
    public let userID: String?
    public let sessionID: String?

    public init(
        name: String,
        timestamp: Date = Date(),
        properties: [String: Any] = [:],
        userID: String? = nil,
        sessionID: String? = nil
    ) {
        self.name = name
        self.timestamp = timestamp
        self.properties = properties.mapValues { AnyCodable($0) }
        self.userID = userID
        self.sessionID = sessionID
    }
}

/// Type-erased Codable wrapper
public struct AnyCodable: Codable, Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

/// Batched analytics manager that wraps multiple providers
@MainActor
public final class BatchedAnalytics {

    public static let shared = BatchedAnalytics()

    private var providers: [String: BatchableAnalyticsProvider] = [:]
    private var eventBuffer: [String: [AnalyticsEvent]] = [:]
    private let batcher = NetworkBatcher.shared

    // MARK: - Provider Registration

    /// Register an analytics provider
    public func register(provider: BatchableAnalyticsProvider) {
        providers[provider.providerID] = provider
        eventBuffer[provider.providerID] = []
    }

    /// Unregister a provider
    public func unregister(providerID: String) {
        providers.removeValue(forKey: providerID)
        eventBuffer.removeValue(forKey: providerID)
    }

    // MARK: - Event Tracking

    /// Track an event to all registered providers
    public func track(
        event: String,
        properties: [String: Any] = [:],
        userID: String? = nil,
        sessionID: String? = nil
    ) async {
        let analyticsEvent = AnalyticsEvent(
            name: event,
            properties: properties,
            userID: userID,
            sessionID: sessionID
        )

        for (providerID, provider) in providers {
            await track(event: analyticsEvent, to: provider)
        }
    }

    /// Track an event to a specific provider
    public func track(
        event: String,
        properties: [String: Any] = [:],
        to providerID: String
    ) async {
        guard let provider = providers[providerID] else { return }

        let analyticsEvent = AnalyticsEvent(
            name: event,
            properties: properties
        )

        await track(event: analyticsEvent, to: provider)
    }

    private func track(event: AnalyticsEvent, to provider: BatchableAnalyticsProvider) async {
        do {
            let data = try provider.serialize(event: event)

            try await batcher.enqueue(
                url: provider.endpoint,
                method: "POST",
                headers: provider.headers,
                body: data,
                priority: provider.defaultPriority
            )
        } catch {
            // Log error but don't crash
            print("[BatchedAnalytics] Failed to enqueue event: \(error)")
        }
    }

    // MARK: - User Identity

    private var currentUserID: String?
    private var currentSessionID: String?

    /// Set the current user ID for all events
    public func identify(userID: String) {
        currentUserID = userID
    }

    /// Start a new session
    public func startSession() -> String {
        currentSessionID = UUID().uuidString
        return currentSessionID!
    }

    /// Clear user identity
    public func logout() {
        currentUserID = nil
        currentSessionID = nil
    }
}

// MARK: - Common Provider Implementations

/// Generic JSON-based analytics provider
public class GenericJSONProvider: BatchableAnalyticsProvider {
    public let providerID: String
    public let endpoint: URL
    public var headers: [String: String]
    public var defaultPriority: RequestPriority

    public init(
        id: String,
        endpoint: URL,
        headers: [String: String] = ["Content-Type": "application/json"],
        priority: RequestPriority = .deferrable
    ) {
        self.providerID = id
        self.endpoint = endpoint
        self.headers = headers
        self.defaultPriority = priority
    }

    public func serialize(event: AnalyticsEvent) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(event)
    }
}

/// Amplitude-compatible provider
public class AmplitudeProvider: BatchableAnalyticsProvider {
    public let providerID = "amplitude"
    public let endpoint: URL
    public let apiKey: String
    public var defaultPriority: RequestPriority = .deferrable

    public var headers: [String: String] {
        ["Content-Type": "application/json"]
    }

    public init(apiKey: String) {
        self.apiKey = apiKey
        self.endpoint = URL(string: "https://api.amplitude.com/2/httpapi")!
    }

    public func serialize(event: AnalyticsEvent) throws -> Data {
        let payload: [String: Any] = [
            "api_key": apiKey,
            "events": [[
                "event_type": event.name,
                "user_id": event.userID ?? "anonymous",
                "time": Int(event.timestamp.timeIntervalSince1970 * 1000),
                "event_properties": event.properties.mapValues { $0.value }
            ]]
        ]

        return try JSONSerialization.data(withJSONObject: payload)
    }
}

/// Mixpanel-compatible provider
public class MixpanelProvider: BatchableAnalyticsProvider {
    public let providerID = "mixpanel"
    public let endpoint: URL
    public let token: String
    public var defaultPriority: RequestPriority = .deferrable

    public var headers: [String: String] {
        ["Content-Type": "application/json"]
    }

    public init(token: String) {
        self.token = token
        self.endpoint = URL(string: "https://api.mixpanel.com/track")!
    }

    public func serialize(event: AnalyticsEvent) throws -> Data {
        var props = event.properties.mapValues { $0.value }
        props["token"] = token
        props["distinct_id"] = event.userID ?? "anonymous"
        props["time"] = Int(event.timestamp.timeIntervalSince1970)

        let payload: [String: Any] = [
            "event": event.name,
            "properties": props
        ]

        let data = try JSONSerialization.data(withJSONObject: [payload])
        let base64 = data.base64EncodedString()

        return "data=\(base64)".data(using: .utf8)!
    }
}

/// Segment-compatible provider
public class SegmentProvider: BatchableAnalyticsProvider {
    public let providerID = "segment"
    public let endpoint: URL
    public let writeKey: String
    public var defaultPriority: RequestPriority = .deferrable

    public var headers: [String: String] {
        let auth = Data("\(writeKey):".utf8).base64EncodedString()
        return [
            "Content-Type": "application/json",
            "Authorization": "Basic \(auth)"
        ]
    }

    public init(writeKey: String) {
        self.writeKey = writeKey
        self.endpoint = URL(string: "https://api.segment.io/v1/track")!
    }

    public func serialize(event: AnalyticsEvent) throws -> Data {
        let payload: [String: Any] = [
            "event": event.name,
            "userId": event.userID ?? "anonymous",
            "timestamp": ISO8601DateFormatter().string(from: event.timestamp),
            "properties": event.properties.mapValues { $0.value }
        ]

        return try JSONSerialization.data(withJSONObject: payload)
    }
}
