import Foundation

/// Simulates realistic mobile app network traffic patterns
/// Based on observed patterns from modern iOS apps
public struct TrafficSimulator {

    // MARK: - Realistic Traffic Patterns

    /// Typical request sizes observed in production apps (bytes)
    public enum RequestSize {
        /// Small analytics ping (50-200 bytes)
        public static let analyticsEvent = 50...200

        /// Feature flag check (100-500 bytes)
        public static let featureFlag = 100...500

        /// Session replay chunk (1-5 KB)
        public static let sessionReplay = 1_000...5_000

        /// API response - small (1-5 KB)
        public static let apiSmall = 1_000...5_000

        /// API response - medium (10-50 KB)
        public static let apiMedium = 10_000...50_000

        /// API response - large (100-200 KB)
        public static let apiLarge = 100_000...200_000

        /// Image - thumbnail (5-15 KB)
        public static let imageThumbnail = 5_000...15_000

        /// Image - medium (30-80 KB)
        public static let imageMedium = 30_000...80_000

        /// Image - large (100-300 KB)
        public static let imageLarge = 100_000...300_000
    }

    /// Typical timing patterns observed in production apps
    public enum TimingPattern {
        /// Burst at app launch (0-2 seconds)
        case launchBurst

        /// Periodic analytics (every 10-60 seconds)
        case periodicAnalytics

        /// User-triggered (immediate)
        case userInitiated

        /// Background sync (when idle)
        case backgroundSync

        public var delayRange: ClosedRange<TimeInterval> {
            switch self {
            case .launchBurst:
                return 0...2
            case .periodicAnalytics:
                return 10...60
            case .userInitiated:
                return 0...0.1
            case .backgroundSync:
                return 30...300
            }
        }
    }

    // MARK: - Simulated Request Types

    /// Types of requests commonly seen in mobile apps
    public enum RequestType: CaseIterable {
        case analytics
        case featureFlags
        case pushRegistration
        case sessionReplay
        case contentFeed
        case userProfile
        case imageLoad
        case configFetch

        public var sizeRange: ClosedRange<Int> {
            switch self {
            case .analytics:
                return RequestSize.analyticsEvent
            case .featureFlags:
                return RequestSize.featureFlag
            case .pushRegistration:
                return RequestSize.analyticsEvent
            case .sessionReplay:
                return RequestSize.sessionReplay
            case .contentFeed:
                return RequestSize.apiLarge
            case .userProfile:
                return RequestSize.apiSmall
            case .imageLoad:
                return RequestSize.imageMedium
            case .configFetch:
                return RequestSize.apiSmall
            }
        }

        public var priority: RequestPriority {
            switch self {
            case .analytics, .sessionReplay:
                return .deferrable
            case .featureFlags, .configFetch:
                return .soon
            case .pushRegistration:
                return .soon
            case .contentFeed, .userProfile, .imageLoad:
                return .immediate
            }
        }

        public var typicalFrequency: TimeInterval {
            switch self {
            case .analytics:
                return 30  // Every 30 seconds
            case .featureFlags:
                return 300  // Every 5 minutes
            case .pushRegistration:
                return 3600  // Once per hour
            case .sessionReplay:
                return 10  // Every 10 seconds
            case .contentFeed:
                return 60  // On pull-to-refresh
            case .userProfile:
                return 300  // Every 5 minutes
            case .imageLoad:
                return 5  // Frequently during scroll
            case .configFetch:
                return 600  // Every 10 minutes
            }
        }
    }

    // MARK: - Launch Burst Simulation

    /// Simulates the burst of requests that occur at app launch
    /// Typical apps make 10-20 requests in the first 2-3 seconds
    public static func simulateLaunchBurst() -> [SimulatedRequest] {
        var requests: [SimulatedRequest] = []

        // Analytics initialization (3-5 services)
        for i in 0..<Int.random(in: 3...5) {
            requests.append(SimulatedRequest(
                type: .analytics,
                delay: Double.random(in: 0...0.5),
                size: Int.random(in: RequestSize.analyticsEvent)
            ))
        }

        // Feature flags check
        requests.append(SimulatedRequest(
            type: .featureFlags,
            delay: Double.random(in: 0.1...0.3),
            size: Int.random(in: RequestSize.featureFlag)
        ))

        // Push registration
        requests.append(SimulatedRequest(
            type: .pushRegistration,
            delay: Double.random(in: 0.2...0.5),
            size: Int.random(in: RequestSize.analyticsEvent)
        ))

        // Config fetch
        requests.append(SimulatedRequest(
            type: .configFetch,
            delay: Double.random(in: 0.1...0.4),
            size: Int.random(in: RequestSize.apiSmall)
        ))

        // Main content feed
        requests.append(SimulatedRequest(
            type: .contentFeed,
            delay: Double.random(in: 0.3...0.8),
            size: Int.random(in: RequestSize.apiLarge)
        ))

        // Initial images (5-10)
        for _ in 0..<Int.random(in: 5...10) {
            requests.append(SimulatedRequest(
                type: .imageLoad,
                delay: Double.random(in: 0.5...2.0),
                size: Int.random(in: RequestSize.imageMedium)
            ))
        }

        return requests.sorted { $0.delay < $1.delay }
    }

    /// Simulates ongoing background traffic during app use
    public static func simulateBackgroundTraffic(duration: TimeInterval) -> [SimulatedRequest] {
        var requests: [SimulatedRequest] = []
        var currentTime: TimeInterval = 0

        while currentTime < duration {
            // Analytics events (every 10-30 seconds)
            let analyticsInterval = Double.random(in: 10...30)
            currentTime += analyticsInterval

            if currentTime < duration {
                requests.append(SimulatedRequest(
                    type: .analytics,
                    delay: currentTime,
                    size: Int.random(in: RequestSize.analyticsEvent)
                ))
            }

            // Session replay chunks (every 5-15 seconds)
            if Bool.random() {
                requests.append(SimulatedRequest(
                    type: .sessionReplay,
                    delay: currentTime + Double.random(in: 0...5),
                    size: Int.random(in: RequestSize.sessionReplay)
                ))
            }
        }

        return requests.sorted { $0.delay < $1.delay }
    }
}

// MARK: - Simulated Request

public struct SimulatedRequest {
    public let id = UUID()
    public let type: TrafficSimulator.RequestType
    public let delay: TimeInterval
    public let size: Int

    public var priority: RequestPriority {
        type.priority
    }

    /// Generate mock URL for this request type
    public var mockURL: URL {
        switch type {
        case .analytics:
            return URL(string: "https://api.analytics-service.com/v2/track")!
        case .featureFlags:
            return URL(string: "https://api.feature-flags.com/sdk/v2/flags")!
        case .pushRegistration:
            return URL(string: "https://api.push-service.com/register")!
        case .sessionReplay:
            return URL(string: "https://api.session-replay.com/capture")!
        case .contentFeed:
            return URL(string: "https://api.example.com/v1/feed")!
        case .userProfile:
            return URL(string: "https://api.example.com/v1/user/profile")!
        case .imageLoad:
            return URL(string: "https://cdn.example.com/images/\(UUID().uuidString).jpg")!
        case .configFetch:
            return URL(string: "https://api.example.com/v1/config")!
        }
    }

    /// Generate mock body data of the appropriate size
    public func mockBody() -> Data {
        Data(repeating: 0, count: size)
    }
}

// MARK: - Traffic Statistics

public struct TrafficStatistics {
    public let totalRequests: Int
    public let totalBytes: Int
    public let byType: [TrafficSimulator.RequestType: (count: Int, bytes: Int)]
    public let duration: TimeInterval

    /// Requests per minute
    public var requestsPerMinute: Double {
        guard duration > 0 else { return 0 }
        return Double(totalRequests) / (duration / 60)
    }

    /// Bytes per second
    public var bytesPerSecond: Double {
        guard duration > 0 else { return 0 }
        return Double(totalBytes) / duration
    }

    /// Estimated radio wake-ups without batching
    public var estimatedWakeUpsWithoutBatching: Int {
        totalRequests
    }

    /// Estimated radio wake-ups with batching (assuming 1-minute batches)
    public var estimatedWakeUpsWithBatching: Int {
        max(1, Int(duration / 60))
    }

    /// Energy savings percentage
    public var energySavingsPercent: Double {
        guard estimatedWakeUpsWithoutBatching > 0 else { return 0 }
        let saved = estimatedWakeUpsWithoutBatching - estimatedWakeUpsWithBatching
        return Double(saved) / Double(estimatedWakeUpsWithoutBatching) * 100
    }
}
