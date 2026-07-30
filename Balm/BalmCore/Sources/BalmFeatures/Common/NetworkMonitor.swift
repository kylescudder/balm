import Foundation
import Network
import Observation

/// Wraps `NWPathMonitor` so the app can show an offline banner and refuse
/// mutations when offline. Lives at the `AppEnvironment` level.
@MainActor
@Observable
public final class NetworkMonitor {
    public private(set) var isOnline: Bool = true
    public private(set) var isExpensive: Bool = false
    public private(set) var isConstrained: Bool = false

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "app.balm.NetworkMonitor")

    public init() {
        self.monitor = NWPathMonitor()
        start()
    }

    private func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let expensive = path.isExpensive
            let constrained = path.isConstrained
            Task { @MainActor [weak self] in
                self?.isOnline = online
                self?.isExpensive = expensive
                self?.isConstrained = constrained
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
