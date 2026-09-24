import SwiftUI

enum HomePullRefreshPhase: Equatable {
    case idle
    case dragging
    case armed
    case refreshing
    case settling
}

@MainActor
final class HomeFeedRefreshActions {
    private(set) var phase: HomePullRefreshPhase = .idle
    private var latestIsUserInteracting = false
    private var canFinishSettling = false
    private var refreshTask: Task<Void, Never>?

    func retry(refresh: @escaping @MainActor () async -> Void) {
        Task { @MainActor in
            await refresh()
        }
    }

    func handleConfiguredPullRefresh(
        pullDistance: CGFloat,
        triggerDistance: CGFloat,
        isUserInteracting: Bool,
        isRefreshing: Bool,
        refresh: @escaping @MainActor () async -> Bool
    ) {
        latestIsUserInteracting = isUserInteracting
        let threshold = max(1, triggerDistance)

        switch phase {
        case .idle:
            guard isUserInteracting, !isRefreshing else { return }
            if pullDistance >= threshold {
                phase = .armed
                Haptics.medium()
            } else {
                phase = .dragging
            }

        case .dragging:
            guard isUserInteracting else {
                phase = .idle
                return
            }
            guard pullDistance >= threshold, !isRefreshing else { return }
            phase = .armed
            Haptics.medium()

        case .armed:
            if isUserInteracting {
                if pullDistance < threshold {
                    phase = .dragging
                }
                return
            }
            guard !isRefreshing else {
                phase = .idle
                return
            }
            beginRefresh(refresh)

        case .refreshing:
            return

        case .settling:
            guard canFinishSettling, !isUserInteracting else { return }
            phase = .idle
        }
    }

    private func beginRefresh(_ refresh: @escaping @MainActor () async -> Bool) {
        phase = .refreshing
        canFinishSettling = false
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            let succeeded = await refresh()
            guard let self, !Task.isCancelled else { return }
            if succeeded {
                Haptics.success()
            }
            phase = .settling
            try? await Task.sleep(for: .milliseconds(360))
            guard !Task.isCancelled else { return }
            canFinishSettling = true
            refreshTask = nil
            guard !latestIsUserInteracting else { return }
            phase = .idle
        }
    }
}
