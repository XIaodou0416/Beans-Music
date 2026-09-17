import Foundation
import Network

enum BeansNetworkConnectionKind: Equatable {
    case wifi
    case cellular
    case other
    case unavailable
}

/// Shared reachability state used by page caches to avoid refreshing while offline.
final class BeansNetworkStatus {
    static let shared = BeansNetworkStatus()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var reachable = true
    private var currentConnectionKind: BeansNetworkConnectionKind = .other

    var isReachable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return reachable
    }

    var connectionKind: BeansNetworkConnectionKind {
        lock.lock()
        defer { lock.unlock() }
        return currentConnectionKind
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.reachable = path.status == .satisfied
            if path.status != .satisfied {
                self.currentConnectionKind = .unavailable
            } else if path.usesInterfaceType(.wifi) {
                self.currentConnectionKind = .wifi
            } else if path.usesInterfaceType(.cellular) {
                self.currentConnectionKind = .cellular
            } else {
                self.currentConnectionKind = .other
            }
            self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "Beans.NetworkStatus"))
    }
}
