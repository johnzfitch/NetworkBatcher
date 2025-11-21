import SwiftUI
import NetworkBatcher

@main
struct NetworkBatcherDemoApp: App {

    init() {
        // Configure NetworkBatcher for demo
        var config = BatcherConfiguration.balanced
        config.enableLogging = true
        config.minBatchInterval = 10  // Shorter interval for demo
        NetworkBatcher.shared.configuration = config
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
