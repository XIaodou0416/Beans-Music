import SwiftUI

enum FastScrollImageLoadSuppression {
    static let resumeDelayNanoseconds: UInt64 = 120_000_000
}

enum FastScrollImageLoadSuppressionPolicy {
    nonisolated static func suppressesNetworkLoads(phase: ScrollPhase) -> Bool {
        switch phase {
        case .interacting, .decelerating:
            return true
        default:
            return false
        }
    }

    nonisolated static func shouldWaitForNetwork(hasCachedImage: Bool, suppressionActive: Bool) -> Bool {
        !hasCachedImage && suppressionActive
    }
}

nonisolated struct RemoteImageScrollLoadSuppressionStatistics: Sendable, Equatable {
    let visibleBypassCount: Int
    let deferredPrefetchCount: Int
    let activeScopeCount: Int

    static let empty = RemoteImageScrollLoadSuppressionStatistics(
        visibleBypassCount: 0,
        deferredPrefetchCount: 0,
        activeScopeCount: 0
    )
}

actor RemoteImageLoadSuppressionGate {
    static let shared = RemoteImageLoadSuppressionGate()

    private var activeScopes = Set<UUID>()
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var visibleBypassCount = 0
    private var deferredPrefetchCount = 0

    func setSuppressed(_ isSuppressed: Bool, for scopeID: UUID) {
        if isSuppressed {
            activeScopes.insert(scopeID)
        } else {
            activeScopes.remove(scopeID)
            resumeWaitersIfAllowed()
        }
    }

    func waitUntilAllowed(
        priority: RemoteImageLoadPriority = .prefetch,
        hasCachedImage: Bool = false
    ) async {
        guard !hasCachedImage else { return }
        switch priority {
        case .visible:
            if RemoteImageDiagnosticsSettings.isRecordingEnabled,
               !activeScopes.isEmpty {
                visibleBypassCount += 1
            }
            return
        case .prefetch:
            break
        }
        guard FastScrollImageLoadSuppressionPolicy.shouldWaitForNetwork(
            hasCachedImage: hasCachedImage,
            suppressionActive: !activeScopes.isEmpty
        ) else { return }

        if RemoteImageDiagnosticsSettings.isRecordingEnabled {
            deferredPrefetchCount += 1
        }
        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !activeScopes.isEmpty, !Task.isCancelled else {
                    continuation.resume()
                    return
                }
                waiters[waiterID] = continuation
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(waiterID)
            }
        }
    }

#if DEBUG
    func waiterCountForTesting() -> Int {
        waiters.count
    }
#endif

    func statistics() -> RemoteImageScrollLoadSuppressionStatistics {
        RemoteImageScrollLoadSuppressionStatistics(
            visibleBypassCount: visibleBypassCount,
            deferredPrefetchCount: deferredPrefetchCount,
            activeScopeCount: activeScopes.count
        )
    }

    func resetDiagnostics() {
        visibleBypassCount = 0
        deferredPrefetchCount = 0
    }

    private func cancelWaiter(_ waiterID: UUID) {
        waiters.removeValue(forKey: waiterID)?.resume()
    }

    private func resumeWaitersIfAllowed() {
        guard activeScopes.isEmpty else { return }
        let continuations = Array(waiters.values)
        waiters.removeAll()
        continuations.forEach { $0.resume() }
    }
}

private struct FastScrollImageLoadSuppressionModifier: ViewModifier {
    @State private var phase: ScrollPhase = .idle
    @State private var scopeID = UUID()

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, newPhase in
                phase = newPhase
            }
            .task(id: gateTaskIdentity) {
                await updateGate()
            }
            .onDisappear {
                let scopeID = scopeID
                Task {
                    await RemoteImageLoadSuppressionGate.shared.setSuppressed(false, for: scopeID)
                }
            }
    }

    private var suppressesNetworkLoads: Bool {
        FastScrollImageLoadSuppressionPolicy.suppressesNetworkLoads(phase: phase)
    }

    private var gateTaskIdentity: Int {
        return suppressesNetworkLoads ? 1 : 2
    }

    private func updateGate() async {
        if suppressesNetworkLoads {
            guard !Task.isCancelled else { return }
            await RemoteImageLoadSuppressionGate.shared.setSuppressed(true, for: scopeID)
            return
        }

        do {
            try await Task.sleep(nanoseconds: FastScrollImageLoadSuppression.resumeDelayNanoseconds)
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        await RemoteImageLoadSuppressionGate.shared.setSuppressed(false, for: scopeID)
    }
}

extension View {
    func defersRemoteImageLoadsDuringFastScroll() -> some View {
        modifier(FastScrollImageLoadSuppressionModifier())
    }
}
