import Foundation

/// Configuration options for NetworkBatcher
public struct BatcherConfiguration: Sendable {

    // MARK: - Timing Configuration

    /// Maximum time a request can be deferred (default: 15 minutes)
    public var maxDeferralTime: TimeInterval

    /// Minimum interval between batch transmissions (default: 60 seconds)
    public var minBatchInterval: TimeInterval

    /// How long to consider the radio "warm" after user activity (default: 5 seconds)
    public var piggybackWindow: TimeInterval

    // MARK: - Size Limits

    /// Maximum number of requests to queue (default: 100)
    public var maxQueueSize: Int

    /// Maximum total payload size before forcing transmission (default: 100KB)
    public var maxPayloadSize: Int

    /// Maximum requests per batch (default: 20)
    public var maxBatchSize: Int

    // MARK: - Conditions

    /// Prefer WiFi over cellular (default: true)
    public var preferWiFi: Bool

    /// Prefer charging state (default: true)
    public var preferCharging: Bool

    /// Piggyback on user-initiated network requests (default: true)
    public var piggybackOnUserRequests: Bool

    /// Flush queue when app enters background (default: true)
    public var flushOnBackground: Bool

    /// Allow transmission on cellular (default: true)
    public var allowCellular: Bool

    /// Require WiFi for bulk transfers (default: true)
    public var requireWiFiForBulk: Bool

    // MARK: - Domain Classification

    /// Domains that should always be sent immediately
    public var immediateDomains: Set<String>

    /// Domains that are known to be deferrable (analytics, telemetry)
    public var deferrableDomains: Set<String>

    // MARK: - Debugging

    /// Enable detailed logging (default: false)
    public var enableLogging: Bool

    /// Enable metrics collection (default: true)
    public var enableMetrics: Bool

    // MARK: - Initialization

    public init(
        maxDeferralTime: TimeInterval = 15 * 60,
        minBatchInterval: TimeInterval = 60,
        piggybackWindow: TimeInterval = 5,
        maxQueueSize: Int = 100,
        maxPayloadSize: Int = 100_000,
        maxBatchSize: Int = 20,
        preferWiFi: Bool = true,
        preferCharging: Bool = true,
        piggybackOnUserRequests: Bool = true,
        flushOnBackground: Bool = true,
        allowCellular: Bool = true,
        requireWiFiForBulk: Bool = true,
        immediateDomains: Set<String> = Self.defaultImmediateDomains,
        deferrableDomains: Set<String> = Self.defaultDeferrableDomains,
        enableLogging: Bool = false,
        enableMetrics: Bool = true
    ) {
        self.maxDeferralTime = maxDeferralTime
        self.minBatchInterval = minBatchInterval
        self.piggybackWindow = piggybackWindow
        self.maxQueueSize = maxQueueSize
        self.maxPayloadSize = maxPayloadSize
        self.maxBatchSize = maxBatchSize
        self.preferWiFi = preferWiFi
        self.preferCharging = preferCharging
        self.piggybackOnUserRequests = piggybackOnUserRequests
        self.flushOnBackground = flushOnBackground
        self.allowCellular = allowCellular
        self.requireWiFiForBulk = requireWiFiForBulk
        self.immediateDomains = immediateDomains
        self.deferrableDomains = deferrableDomains
        self.enableLogging = enableLogging
        self.enableMetrics = enableMetrics
    }

    // MARK: - Default Domain Lists

    /// Domains that must be sent immediately (auth, payments, etc.)
    public static let defaultImmediateDomains: Set<String> = [
        // Payment providers
        "api.stripe.com",
        "api.paypal.com",
        "api.square.com",
        "api.braintreegateway.com",

        // Apple services (auth, IAP)
        "api.apple.com",
        "appleid.apple.com",
        "buy.itunes.apple.com",
        "sandbox.itunes.apple.com",

        // Auth providers
        "accounts.google.com",
        "oauth.googleapis.com",
        "graph.facebook.com",  // When used for auth
        "api.twitter.com",

        // Real-time services
        "wss://",  // WebSocket connections
        "firebaseio.com",
    ]

    /// Domains known to be deferrable (analytics, telemetry, crash reporting)
    public static let defaultDeferrableDomains: Set<String> = [
        // Google/Firebase Analytics
        "app-measurement.com",
        "firebase-settings.crashlytics.com",
        "firebaselogging-pa.googleapis.com",
        "firebaseinstallations.googleapis.com",

        // Analytics platforms
        "api.amplitude.com",
        "api.mixpanel.com",
        "api.segment.io",
        "cdn.segment.com",
        "api.heap.io",
        "heapanalytics.com",

        // Crash reporting
        "sentry.io",
        "api.bugsnag.com",
        "api.rollbar.com",
        "intake.datadoghq.com",
        "mobile.launchdarkly.com",

        // Attribution/Marketing
        "api.branch.io",
        "events.appsflyer.com",
        "app.adjust.com",
        "app.adjust.io",
        "settings.adjust.com",
        "app.link",
        "clicks.kochava.com",
        "api.singular.net",

        // Facebook/Meta SDK
        "graph.facebook.com",

        // Advertising
        "googleads.g.doubleclick.net",
        "pagead2.googlesyndication.com",
        "adsserver.com",

        // Other telemetry
        "api.onesignal.com",
        "api.intercom.io",
        "api.braze.com",
        "sdk.iad-01.braze.com",
        "api.instabug.com",
        "logs.newrelic.com",
    ]

    // MARK: - Presets

    /// Aggressive battery saving (longer deferrals, WiFi preferred)
    public static var batterySaver: BatcherConfiguration {
        var config = BatcherConfiguration()
        config.maxDeferralTime = 30 * 60  // 30 minutes
        config.minBatchInterval = 5 * 60  // 5 minutes
        config.requireWiFiForBulk = true
        config.preferCharging = true
        return config
    }

    /// Balanced (default settings)
    public static var balanced: BatcherConfiguration {
        BatcherConfiguration()
    }

    /// Minimal batching (for apps that need fresher data)
    public static var minimal: BatcherConfiguration {
        var config = BatcherConfiguration()
        config.maxDeferralTime = 5 * 60  // 5 minutes
        config.minBatchInterval = 30  // 30 seconds
        config.requireWiFiForBulk = false
        return config
    }
}
