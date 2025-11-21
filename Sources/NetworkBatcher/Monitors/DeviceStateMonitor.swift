import Foundation
import Network

#if canImport(UIKit)
import UIKit
#endif

/// Monitors device state (network, battery, charging) for optimal transmission timing
public final class DeviceStateMonitor: @unchecked Sendable {

    public static let shared = DeviceStateMonitor()

    // MARK: - Published State

    /// Current network connection type
    public private(set) var networkType: NetworkType = .unknown {
        didSet {
            if networkType != oldValue {
                notifyObservers(\.networkType)
            }
        }
    }

    /// Whether device is currently connected to network
    public private(set) var isConnected: Bool = false {
        didSet {
            if isConnected != oldValue {
                notifyObservers(\.isConnected)
            }
        }
    }

    /// Whether device is connected to WiFi
    public var isOnWiFi: Bool {
        networkType == .wifi
    }

    /// Whether device is connected to cellular
    public var isOnCellular: Bool {
        networkType == .cellular
    }

    /// Whether device is currently charging
    public private(set) var isCharging: Bool = false {
        didSet {
            if isCharging != oldValue {
                notifyObservers(\.isCharging)
            }
        }
    }

    /// Current battery level (0.0 - 1.0)
    public private(set) var batteryLevel: Float = 1.0

    /// Whether battery is low (<20%)
    public var isBatteryLow: Bool {
        batteryLevel < 0.2
    }

    /// Last time user-initiated network activity was detected
    public private(set) var lastUserNetworkActivity: Date = .distantPast

    /// Whether we're within the piggyback window
    public func isWithinPiggybackWindow(window: TimeInterval) -> Bool {
        Date().timeIntervalSince(lastUserNetworkActivity) < window
    }

    // MARK: - Private

    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.networkbatcher.monitor")
    private var observers: [ObjectIdentifier: (KeyPath<DeviceStateMonitor, Any>) -> Void] = [:]
    private let lock = NSLock()

    // MARK: - Initialization

    private init() {
        setupNetworkMonitor()
        setupBatteryMonitor()
    }

    // MARK: - Network Monitoring

    private func setupNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            self.isConnected = path.status == .satisfied

            if path.usesInterfaceType(.wifi) {
                self.networkType = .wifi
            } else if path.usesInterfaceType(.cellular) {
                self.networkType = .cellular
            } else if path.usesInterfaceType(.wiredEthernet) {
                self.networkType = .ethernet
            } else {
                self.networkType = path.status == .satisfied ? .other : .none
            }
        }

        networkMonitor.start(queue: monitorQueue)
    }

    // MARK: - Battery Monitoring

    private func setupBatteryMonitor() {
        #if canImport(UIKit) && !os(watchOS)
        DispatchQueue.main.async {
            UIDevice.current.isBatteryMonitoringEnabled = true

            self.updateBatteryState()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.batteryStateChanged),
                name: UIDevice.batteryStateDidChangeNotification,
                object: nil
            )

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.batteryLevelChanged),
                name: UIDevice.batteryLevelDidChangeNotification,
                object: nil
            )
        }
        #endif
    }

    @objc private func batteryStateChanged() {
        updateBatteryState()
    }

    @objc private func batteryLevelChanged() {
        updateBatteryState()
    }

    private func updateBatteryState() {
        #if canImport(UIKit) && !os(watchOS)
        DispatchQueue.main.async {
            let device = UIDevice.current
            self.batteryLevel = device.batteryLevel
            self.isCharging = device.batteryState == .charging || device.batteryState == .full
        }
        #endif
    }

    // MARK: - User Activity Tracking

    /// Call this when user-initiated network activity occurs
    /// Enables piggybacking on warm radio
    public func recordUserNetworkActivity() {
        lastUserNetworkActivity = Date()
    }

    // MARK: - Observation

    /// Add an observer for state changes
    public func addObserver<T>(_ observer: AnyObject, keyPath: KeyPath<DeviceStateMonitor, T>, handler: @escaping (T) -> Void) {
        lock.lock()
        defer { lock.unlock() }

        observers[ObjectIdentifier(observer)] = { [weak self] _ in
            guard let self = self else { return }
            handler(self[keyPath: keyPath])
        }
    }

    /// Remove an observer
    public func removeObserver(_ observer: AnyObject) {
        lock.lock()
        defer { lock.unlock() }

        observers.removeValue(forKey: ObjectIdentifier(observer))
    }

    private func notifyObservers<T>(_ keyPath: KeyPath<DeviceStateMonitor, T>) {
        lock.lock()
        let currentObservers = observers
        lock.unlock()

        for (_, handler) in currentObservers {
            handler(keyPath as! KeyPath<DeviceStateMonitor, Any>)
        }
    }

    // MARK: - Transmission Conditions

    /// Check if current conditions are optimal for transmission
    public func shouldTransmit(config: BatcherConfiguration, priority: RequestPriority) -> TransmissionDecision {

        // No connection - can't transmit
        guard isConnected else {
            return .wait(reason: "No network connection")
        }

        // Immediate priority always transmits
        if priority == .immediate {
            return .transmit(reason: "Immediate priority")
        }

        // Check cellular restrictions
        if isOnCellular && !config.allowCellular {
            return .wait(reason: "Cellular not allowed")
        }

        // Bulk transfers require WiFi
        if priority == .bulk && config.requireWiFiForBulk && !isOnWiFi {
            return .wait(reason: "Bulk requires WiFi")
        }

        // Low battery - be conservative
        if isBatteryLow && !isCharging {
            if priority == .deferrable || priority == .bulk {
                return .wait(reason: "Low battery")
            }
        }

        // Optimal conditions: WiFi + Charging
        if isOnWiFi && isCharging {
            return .transmit(reason: "Optimal: WiFi + Charging")
        }

        // Good conditions: WiFi or Charging
        if isOnWiFi || isCharging {
            if priority != .bulk {
                return .transmit(reason: "Good conditions")
            }
        }

        // Within piggyback window - radio is already warm
        if isWithinPiggybackWindow(window: config.piggybackWindow) {
            return .transmit(reason: "Radio warm from user activity")
        }

        // For deferrable/bulk, wait for better conditions
        if priority == .deferrable || priority == .bulk {
            return .wait(reason: "Waiting for optimal conditions")
        }

        // Default: allow transmission
        return .transmit(reason: "Default allow")
    }
}

// MARK: - Supporting Types

/// Type of network connection
public enum NetworkType: String, Sendable {
    case wifi = "WiFi"
    case cellular = "Cellular"
    case ethernet = "Ethernet"
    case other = "Other"
    case none = "None"
    case unknown = "Unknown"
}

/// Decision about whether to transmit now
public enum TransmissionDecision: Sendable {
    case transmit(reason: String)
    case wait(reason: String)

    public var shouldTransmit: Bool {
        if case .transmit = self { return true }
        return false
    }

    public var reason: String {
        switch self {
        case .transmit(let reason), .wait(let reason):
            return reason
        }
    }
}
