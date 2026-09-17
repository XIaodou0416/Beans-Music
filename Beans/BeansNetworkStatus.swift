import Foundation
import Network

/// Shared reachability state used by page caches to avoid refreshing while offline.
final class BeansNetworkStatus {
    static let shared = BeansNetworkStatus()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var reachable = true

    var isReachable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return reachable
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.reachable = path.status == .satisfied
            self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "Beans.NetworkStatus"))
    }
}
