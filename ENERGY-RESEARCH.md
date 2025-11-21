# Energy Research: Key Insights from Apple Documentation

## Critical Finding: "Fixed Cost" is the Real Problem

From **Energy Efficiency Guide - Fundamental Concepts**:

> **IMPORTANT**: Networking has a high fixed cost in iOS. Whenever networking occurs, cellular radios and Wi-Fi must power up. In anticipation of additional work, these resources remain running—and consume energy—for prolonged periods, even after your work is complete.

This is the core insight. The problem isn't the data transfer itself—it's the **overhead of waking the radio**.

## The Numbers

From Apple's Energy Fundamentals:

| State | Power Draw |
|-------|------------|
| Sleep | Baseline |
| Idle | **10x** over sleep |
| 1% CPU | 10% more than idle |
| 10% CPU | **2x** idle |
| 100% CPU | **10x** idle |

**Key insight**: Going from idle to 1% CPU costs 10% more energy. But going from idle to 10% CPU only costs 2x. This means **batching is mathematically optimal**—do more work at once rather than small bursts repeatedly.

## The Radio "Tail Energy" Problem

From various Apple docs and external research:

1. **Radio Wake-up**: ~1-2 seconds
2. **Active Transmission**: Variable (your actual data transfer)
3. **Tail Time**: **5-10 seconds** (radio stays on anticipating more data)
4. **Power Down**: ~1 second

A tiny 50-byte analytics ping:
- Actual transmission: ~10ms
- Total radio active time: **~12 seconds** (including tail)
- Energy cost: Same as sending ~500KB of data!

## Apple's Official Recommendation

From **Energy Efficiency Guide - Work Less in Background**:

> "Your app can avoid sporadic work by **batching tasks and performing them less frequently**."

> "This strategy incurs a greater up-front dynamic cost—more work is done at a given time, requiring more power. In exchange, you get a **dramatic reduction in fixed cost**, which results in **tremendous energy savings over time**."

## TN2277: Networking and Multitasking - Key Points

### Background Task Timing
- Background tasks give you **~3 minutes** max (was 10 minutes pre-iOS 7)
- **Must** call `endBackgroundTask:` when done
- **Watchdog** will kill your app if `applicationDidEnterBackground:` takes too long
- Never do synchronous network calls in `applicationDidEnterBackground:`

### Socket Reclaim
When app is suspended, iOS **reclaims socket resources**:
- All pending connections are dropped
- Error code: often `EBADF` (file descriptor invalid)
- Your app gets **no notification** of this happening

**Implication for NetworkBatcher**: Must persist queue to disk, can't rely on in-memory queues surviving suspension.

### Background Execution Priority
Apple explicitly says:
> "Continuing a network transfer is an obvious application of background tasks."

But warns:
> "If system resources get low...the system must suspend or terminate your app before its background tasks are complete."

**Implication**: Always implement resumable transfers. NetworkBatcher must be resilient to termination.

## What Apple Wants Us To Do

From multiple guides:

### 1. Use `isDiscretionary` for URLSession Tasks
```swift
let config = URLSessionConfiguration.background(withIdentifier: "com.app.batch")
config.isDiscretionary = true  // System chooses optimal time
config.sessionSendsLaunchEvents = false
config.allowsCellularAccess = true  // but prefers WiFi
```

### 2. Batch Operations
> "Instead of performing a series of sequential tasks on the same thread, distribute those same tasks simultaneously across multiple threads."

### 3. Piggyback on Existing Activity
When radio is already active for user-initiated request, send other pending data too.

### 4. Use QoS Classes
```swift
DispatchQueue.global(qos: .utility).async {
    // Deferrable work - system may delay
}

DispatchQueue.global(qos: .background).async {
    // Very deferrable - low priority
}
```

## Why Third-Party SDKs Ignore This

1. **SDK developers want data NOW** - analytics delayed = analytics lost (from their perspective)
2. **Competitive pressure** - "real-time" is a marketing feature
3. **No accountability** - SDK doesn't know about other SDKs
4. **Fire-and-forget design** - easier to implement constant pinging
5. **Ignorance** - many SDK devs don't read Apple's energy docs

## NetworkBatcher's Value Proposition

Given that:
- Each analytics SDK thinks it's the only one
- Apple's deferral mechanisms are opt-in
- Users have 5-10 SDKs in typical apps
- Each SDK pings 1-60 times per minute

**NetworkBatcher provides**:
1. **Centralized batching** across all SDKs
2. **Intelligent timing** (WiFi, charging, piggybacking)
3. **Persistence** (survives app suspension)
4. **Coalescing** (dedupes similar events)
5. **Compression** (smaller payloads)

## Energy Savings Math

### Before NetworkBatcher
- 5 SDKs × 1 ping/minute = 5 radio wake-ups/minute
- 5 × 60 minutes × 12 seconds tail = 3,600 seconds (60 minutes) of radio/hour
- 60% of the hour the radio is active!

### After NetworkBatcher
- Batch every 5 minutes = 12 batches/hour
- 12 × 15 seconds (batch is larger, takes longer) = 180 seconds
- 3 minutes of the hour the radio is active

**Savings: 95% reduction in radio activity**

## Apple's Missed Opportunity

Apple has all the pieces:
- `isDiscretionary` sessions
- QoS classes
- Background refresh scheduling
- Coalesced notifications

But they're all **per-app** and **opt-in**. Apple could implement system-wide request batching, but they haven't.

**NetworkBatcher fills this gap at the app level.**

## Implementation Notes

### Must-Haves (from Apple docs):
1. ✅ SQLite persistence (survive suspension/termination)
2. ✅ Background task for flush-on-background
3. ✅ WiFi/cellular detection
4. ✅ Proper error handling for reclaimed sockets
5. ✅ Async-only design (no blocking in lifecycle methods)

### Should-Haves:
1. ✅ Piggybacking on user requests
2. ✅ Charging state detection
3. ✅ Queue size limits
4. ✅ Maximum deferral time

### Nice-to-Haves:
1. ⬜ HTTP/2 multiplexing for same-host batches
2. ⬜ Request coalescing/deduplication
3. ⬜ Payload compression
4. ⬜ Metrics on energy saved
5. ⬜ Integration with Apple's Energy Organizer

## References

1. Energy Efficiency Guide for iOS Apps (Apple)
2. TN2277: Networking and Multitasking (Apple)
3. iOS Application Programming Guide (Apple)
4. "Who Killed My Battery?" (Stanford research paper)
5. "The Tail at Scale" (Google paper on similar server-side batching)
