# NetworkBatcher

**Energy-efficient network request batching for iOS**

A Swift Package that reduces battery drain by intelligently batching non-essential network requests (analytics, telemetry, crash reports) and transmitting them when conditions are optimal.

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![iOS 15+](https://img.shields.io/badge/iOS-15+-blue.svg)](https://developer.apple.com/ios/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## The Problem

Modern iOS apps are riddled with constant network polling from multiple SDKs:

| SDK Type | Examples | Typical Frequency |
|----------|----------|-------------------|
| Analytics | Firebase, Amplitude, Mixpanel | 1-10 events/minute |
| Crash Reporting | Crashlytics, Sentry, Bugsnag | On crash + heartbeats |
| A/B Testing | LaunchDarkly, Optimizely | Config fetches |
| Attribution | Branch, AppsFlyer, Adjust | Events + attribution |
| Ads | AdMob, Facebook, ironSource | Impressions + events |

**Each request wakes the cellular radio**, which has a "tail energy" problem:

```
Radio Wake Cycle:
┌─────────┬──────────────┬───────────────────────────┬─────────┐
│  Ramp   │   Active     │      Tail (Idle)          │  Sleep  │
│  ~2s    │   (data)     │      5-10 seconds         │         │
└─────────┴──────────────┴───────────────────────────┴─────────┘
     ↑                            ↑
  High power                Still high power!
```

**A 50-byte analytics ping costs the same energy as a 500KB download.**

With 5 SDKs sending 1 event/minute each, you get:
- 300 radio wake-ups per hour
- ~50 minutes of radio activity per hour
- Significant battery drain from "idle" apps

## The Solution

NetworkBatcher reduces this to **12 batch transmissions per hour** - a **95% reduction** in radio activity.

```
Before NetworkBatcher          After NetworkBatcher
────────────────────          ────────────────────
│▌│▌│▌│▌│▌│▌│▌│▌│▌│          │          ▐████│
300 wake-ups/hour              12 batches/hour
50 min radio/hour              3 min radio/hour
```

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/NetworkBatcher.git", from: "1.0.0")
]
```

Or in Xcode: File → Add Packages → Enter repository URL

## Quick Start

### Basic Usage

```swift
import NetworkBatcher

// Enqueue analytics events for batched transmission
Task {
    try await NetworkBatcher.shared.enqueue(
        url: URL(string: "https://api.amplitude.com/2/httpapi")!,
        method: "POST",
        headers: ["Content-Type": "application/json"],
        body: eventData,
        priority: .deferrable
    )
}

// Events are automatically sent when:
// - Device connects to WiFi
// - Device starts charging
// - Another network request warms up the radio
// - Queue reaches size/time limits
```

### With Analytics Wrapper

```swift
import NetworkBatcher
import NetworkBatcherAnalytics

// Register your analytics providers
let amplitude = AmplitudeProvider(apiKey: "YOUR_API_KEY")
await BatchedAnalytics.shared.register(provider: amplitude)

// Track events - they're automatically batched!
await BatchedAnalytics.shared.track(
    event: "button_tapped",
    properties: ["screen": "home", "button": "signup"]
)
```

### Piggybacking on User Activity

```swift
// When user initiates network activity, notify the batcher
// This allows queued requests to piggyback on the warm radio
func fetchUserProfile() async throws -> Profile {
    await NetworkBatcher.shared.notifyUserNetworkActivity()
    return try await api.fetchProfile()
}
```

### Force Flush (Use Sparingly)

```swift
// Before user logout or critical sync point
try await NetworkBatcher.shared.flush(reason: "User logout")
```

## Configuration

```swift
var config = BatcherConfiguration.balanced

// Timing
config.maxDeferralTime = 15 * 60    // 15 minutes max wait
config.minBatchInterval = 60         // At least 1 min between batches
config.piggybackWindow = 5           // 5 sec window after user activity

// Size limits
config.maxQueueSize = 100            // Flush at 100 requests
config.maxPayloadSize = 100_000      // 100KB max batch

// Conditions
config.preferWiFi = true             // Wait for WiFi when possible
config.preferCharging = true         // Prefer charging state
config.piggybackOnUserRequests = true
config.flushOnBackground = true      // Flush when app backgrounds

// Apply configuration
NetworkBatcher.shared.configuration = config
```

### Presets

```swift
// Aggressive battery saving
NetworkBatcher.shared.configuration = .batterySaver

// Default balanced approach
NetworkBatcher.shared.configuration = .balanced

// Minimal batching (fresher data)
NetworkBatcher.shared.configuration = .minimal
```

## Priority Levels

| Priority | Max Delay | Use Case |
|----------|-----------|----------|
| `.immediate` | 0 | Auth, payments, user-blocking requests |
| `.soon` | 30s | Push token updates, config fetches |
| `.deferrable` | 15min | Analytics, telemetry, crash reports |
| `.bulk` | 60min | Large uploads, backups (WiFi only) |
| `.auto` | Varies | System classifies based on domain |

```swift
// Explicit priority
try await batcher.enqueue(url: analyticsURL, body: data, priority: .deferrable)

// Auto-classification (checks domain against known lists)
try await batcher.enqueue(url: analyticsURL, body: data, priority: .auto)
```

## Domain Classification

NetworkBatcher automatically classifies requests based on domain:

### Immediate (Never Batched)
- `api.stripe.com` - Payments
- `api.apple.com` - Apple services
- `appleid.apple.com` - Authentication

### Deferrable (Always Batched)
- `app-measurement.com` - Firebase Analytics
- `api.amplitude.com` - Amplitude
- `api.mixpanel.com` - Mixpanel
- `api.segment.io` - Segment
- `sentry.io` - Sentry
- `api.branch.io` - Branch
- `events.appsflyer.com` - AppsFlyer
- `app.adjust.com` - Adjust
- And many more...

### Custom Domains

```swift
// Add your own deferrable domains
config.deferrableDomains.insert("analytics.mycompany.com")

// Add domains that must be immediate
config.immediateDomains.insert("critical-api.mycompany.com")
```

## Statistics & Debugging

```swift
// Get batching statistics
let stats = try await NetworkBatcher.shared.statistics()

print("Batches sent: \(stats.transmissionStats.batchCount)")
print("Total requests: \(stats.transmissionStats.totalRequests)")
print("Radio wake-ups saved: \(stats.transmissionStats.estimatedWakeUpsSaved)")
print("Est. energy saved: \(stats.estimatedEnergySavedPercent)%")

// Debug logging
#if DEBUG
NetworkBatcher.shared.configuration.enableLogging = true
await NetworkBatcher.shared.debugPrintStatus()
#endif
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Your App                                 │
├─────────────────────────────────────────────────────────────────┤
│  Analytics SDK  │  Crash Reporter  │  Telemetry  │  Your Code  │
│       ↓                 ↓                ↓             ↓       │
├─────────────────────────────────────────────────────────────────┤
│                    NetworkBatcher                               │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Priority Classifier (immediate vs deferrable)           │  │
│  │    ↓                                                     │  │
│  │  Request Queue (SQLite-backed, persists across launches) │  │
│  │    ↓                                                     │  │
│  │  Device Monitor (WiFi, charging, battery)                │  │
│  │    ↓                                                     │  │
│  │  Batch Scheduler (optimal transmission timing)           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           ↓                                     │
├─────────────────────────────────────────────────────────────────┤
│                     URLSession                                  │
└─────────────────────────────────────────────────────────────────┘
```

## App Store Compatibility

**Yes, NetworkBatcher is App Store compatible.**

It works as an SDK within your app, batching requests that originate from your app. It does NOT:
- Intercept traffic from other apps
- Require VPN profiles
- Use private APIs
- Modify system behavior

## iOS System Integration

### Background Tasks

NetworkBatcher automatically handles app lifecycle:

```swift
// Requests are flushed when app enters background
// Uses UIApplication background tasks for completion
// Persists queue to SQLite - survives termination
```

### Background App Refresh (Optional)

For periodic background flushing:

```swift
// In AppDelegate
BGTaskScheduler.shared.register(
    forTaskWithIdentifier: "com.yourapp.networkbatcher.flush",
    using: nil
) { task in
    Task {
        try? await NetworkBatcher.shared.flush(reason: "Background refresh")
        task.setTaskCompleted(success: true)
    }
}
```

## Privacy Benefits

Batching provides an unexpected privacy benefit:

| Without Batching | With Batching |
|------------------|---------------|
| Server sees exact timestamp of each action | Server sees batch arrival time only |
| Easy to correlate user behavior patterns | Timing information is anonymized |

## Limitations

1. **Real-time requirements**: Some features genuinely need instant updates
2. **Crash reporting**: Critical crashes should be sent immediately (use `.immediate` priority)
3. **SDK initialization**: Some SDKs expect immediate network access at launch
4. **Debugging**: Delayed telemetry can complicate debugging (disable batching in DEBUG)

## Why Apple Hasn't Done This

Apple has the pieces (`isDiscretionary`, QoS classes, background sessions) but they're:
- Per-app and opt-in
- Not used by most SDKs
- No system-wide batching across apps

**NetworkBatcher fills this gap at the app level.**

## References

- [Apple Energy Efficiency Guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/)
- [TN2277: Networking and Multitasking](https://developer.apple.com/library/archive/technotes/tn2277/)
- [WWDC 2014: Writing Energy Efficient Code](https://developer.apple.com/videos/play/wwdc2014/710/)
- "The Tail at Scale" - Google paper on server-side batching

## License

MIT License - See [LICENSE](LICENSE) for details.

## Contributing

Contributions welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.
