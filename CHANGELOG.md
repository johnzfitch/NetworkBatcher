# Changelog

All notable changes to NetworkBatcher will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial release of NetworkBatcher

## [1.0.0] - 2024-XX-XX

### Added
- Core `NetworkBatcher` class with request batching engine
- `DeferredRequest` model for queued requests
- `BatcherConfiguration` with presets (balanced, batterySaver, minimal)
- `RequestStore` SQLite-backed persistence layer
- `DeviceStateMonitor` for WiFi/cellular and battery monitoring
- Priority levels: immediate, soon, deferrable, bulk, auto
- Domain classification for automatic priority assignment
- Piggybacking on user-initiated network activity
- Background task integration for app lifecycle
- `NetworkBatcherAnalytics` module with SDK wrappers:
  - `AmplitudeProvider`
  - `MixpanelProvider`
  - `SegmentProvider`
  - `GenericJSONProvider`
- Demo iOS app for testing and visualization
- Comprehensive test suite
- Documentation and examples

### Default Deferrable Domains
- Firebase Analytics (`app-measurement.com`)
- Amplitude (`api.amplitude.com`)
- Mixpanel (`api.mixpanel.com`)
- Segment (`api.segment.io`)
- Sentry (`sentry.io`)
- Branch (`api.branch.io`)
- AppsFlyer (`events.appsflyer.com`)
- Adjust (`app.adjust.com`)
- And many more...

### Default Immediate Domains
- Stripe (`api.stripe.com`)
- Apple services (`api.apple.com`, `appleid.apple.com`)
- Payment processors

---

## Future Releases

### Planned for v1.1.0
- [ ] Request compression support
- [ ] HTTP/2 multiplexing
- [ ] Request deduplication
- [ ] Improved metrics dashboard

### Planned for v1.2.0
- [ ] URLProtocol interceptor (automatic batching)
- [ ] More analytics SDK wrappers
- [ ] Instruments integration
- [ ] watchOS support
