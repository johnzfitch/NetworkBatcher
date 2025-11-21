import Foundation

/// A network request that has been queued for deferred transmission
public struct DeferredRequest: Codable, Identifiable, Sendable {

    /// Unique identifier for this request
    public let id: UUID

    /// Original URL of the request
    public let url: URL

    /// HTTP method (GET, POST, etc.)
    public let method: String

    /// Request headers
    public let headers: [String: String]

    /// Request body data
    public let body: Data?

    /// Priority classification
    public let priority: RequestPriority

    /// When the request was enqueued
    public let enqueuedAt: Date

    /// Maximum time this request can be deferred
    public let maxDeferralTime: TimeInterval

    /// Domain extracted from URL for batching decisions
    public var domain: String {
        url.host ?? "unknown"
    }

    /// Size of the request in bytes
    public var payloadSize: Int {
        var size = url.absoluteString.utf8.count
        size += headers.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }
        size += body?.count ?? 0
        return size
    }

    /// Whether this request has exceeded its maximum deferral time
    public var isExpired: Bool {
        Date().timeIntervalSince(enqueuedAt) > maxDeferralTime
    }

    /// Time remaining before expiry
    public var timeUntilExpiry: TimeInterval {
        max(0, maxDeferralTime - Date().timeIntervalSince(enqueuedAt))
    }

    public init(
        id: UUID = UUID(),
        url: URL,
        method: String = "POST",
        headers: [String: String] = [:],
        body: Data? = nil,
        priority: RequestPriority = .auto,
        enqueuedAt: Date = Date(),
        maxDeferralTime: TimeInterval = 15 * 60
    ) {
        self.id = id
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.priority = priority
        self.enqueuedAt = enqueuedAt
        self.maxDeferralTime = maxDeferralTime
    }

    /// Create a URLRequest from this deferred request
    public func toURLRequest() -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }
}

/// Priority levels for network requests
public enum RequestPriority: Int, Codable, Sendable, CaseIterable {
    /// System determines priority based on domain classification
    case auto = 0

    /// Must be sent immediately (auth, payments)
    case immediate = 1

    /// Should be sent within 30 seconds
    case soon = 2

    /// Can be deferred up to 15 minutes
    case deferrable = 3

    /// Can be deferred indefinitely until optimal conditions
    case bulk = 4

    /// Human-readable description
    public var description: String {
        switch self {
        case .auto: return "Auto"
        case .immediate: return "Immediate"
        case .soon: return "Soon"
        case .deferrable: return "Deferrable"
        case .bulk: return "Bulk"
        }
    }

    /// Maximum deferral time for this priority
    public var maxDeferralTime: TimeInterval {
        switch self {
        case .auto: return 15 * 60  // Will be overridden by classification
        case .immediate: return 0
        case .soon: return 30
        case .deferrable: return 15 * 60
        case .bulk: return 60 * 60
        }
    }
}
