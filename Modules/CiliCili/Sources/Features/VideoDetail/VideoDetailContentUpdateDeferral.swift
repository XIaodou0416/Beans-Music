import Combine
import Foundation

nonisolated enum VideoDetailFormalPerformancePolicy {
    static let navigationTraceDetail = "group=formal transition=1 freeze=1 deferred=1"
}

@MainActor
final class VideoDetailContentUpdateGate: ObservableObject {
    @Published private(set) var revision = 0

    private var isDeferred = false
    private var hasPendingUpdate = false
    private var isDeliveryScheduled = false
    private var deliveryGeneration = 0

    func receiveUpdate() {
        if isDeferred {
            hasPendingUpdate = true
            return
        }
        guard !isDeliveryScheduled else { return }
        isDeliveryScheduled = true
        deliveryGeneration &+= 1
        let generation = deliveryGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.deliveryGeneration == generation else { return }
            self.isDeliveryScheduled = false
            if self.isDeferred {
                self.hasPendingUpdate = true
            } else {
                self.revision &+= 1
            }
        }
    }

    func setUpdatesDeferred(_ deferred: Bool) {
        guard isDeferred != deferred else { return }
        isDeferred = deferred
        if deferred, isDeliveryScheduled {
            deliveryGeneration &+= 1
            isDeliveryScheduled = false
            hasPendingUpdate = true
        }
        guard !deferred, hasPendingUpdate else { return }
        hasPendingUpdate = false
        revision &+= 1
    }
}

struct VideoDetailDeferredValue<Value> {
    private var isDeferred = false
    private var pendingValue: Value?

    var pendingOrNil: Value? { pendingValue }

    mutating func submit(
        _ value: Value,
        current: Value,
        isEquivalent: (Value, Value) -> Bool
    ) -> Value? {
        let latest = pendingValue ?? current
        guard !isEquivalent(value, latest) else { return nil }
        guard isDeferred else { return value }
        pendingValue = value
        return nil
    }

    mutating func setDeferred(_ deferred: Bool) -> Value? {
        guard isDeferred != deferred else { return nil }
        isDeferred = deferred
        guard !deferred else { return nil }
        defer { pendingValue = nil }
        return pendingValue
    }
}
