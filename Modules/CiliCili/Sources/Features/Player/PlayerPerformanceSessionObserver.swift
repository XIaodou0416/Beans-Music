import Combine
import Foundation

@MainActor
final class PlayerPerformanceSessionObserver: ObservableObject {
    @Published private(set) var session: PlayerPerformanceSession?
    @Published private(set) var playbackAdaptationProfile: PlayerPlaybackAdaptationProfile

    private let store: PlayerPerformanceStore
    private let refreshDelayNanoseconds: UInt64
    private var metricsID: String?
    private var isAutoOptimizationEnabled: Bool
    private var pendingRefreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(
        metricsID: String?,
        isAutoOptimizationEnabled: Bool = true,
        refreshDelayNanoseconds: UInt64 = 120_000_000
    ) {
        let store = PlayerPerformanceStore.shared
        self.metricsID = metricsID?.isEmpty == false ? metricsID : nil
        self.isAutoOptimizationEnabled = isAutoOptimizationEnabled
        self.refreshDelayNanoseconds = refreshDelayNanoseconds
        self.store = store
        self.playbackAdaptationProfile = store.playbackAdaptationProfile(
            for: self.metricsID,
            isEnabled: isAutoOptimizationEnabled
        )
        refreshNow()

        store.updates
            .filter { [weak self] update in
                guard let metricsID = self?.metricsID else { return true }
                return update.metricsID == nil || update.metricsID == metricsID
            }
            .sink { [weak self] _ in
                self?.scheduleRefresh()
            }
            .store(in: &cancellables)
    }

    func updateContext(
        metricsID: String?,
        isAutoOptimizationEnabled: Bool? = nil
    ) {
        let normalizedMetricsID = metricsID?.isEmpty == false ? metricsID : nil
        let nextAutoOptimization = isAutoOptimizationEnabled ?? self.isAutoOptimizationEnabled
        guard normalizedMetricsID != self.metricsID || nextAutoOptimization != self.isAutoOptimizationEnabled else {
            return
        }

        self.metricsID = normalizedMetricsID
        self.isAutoOptimizationEnabled = nextAutoOptimization
        refreshNow()
    }

    private func scheduleRefresh() {
        guard pendingRefreshTask == nil else { return }
        pendingRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.refreshDelayNanoseconds)
            guard !Task.isCancelled else { return }
            self.pendingRefreshTask = nil
            self.refreshNow()
        }
    }

    private func refreshNow() {
        let nextSession: PlayerPerformanceSession?
        if let metricsID {
            nextSession = store.session(for: metricsID)
        } else {
            nextSession = store.mostRecentSession()
        }
        if session != nextSession {
            session = nextSession
        }

        let nextProfile = store.playbackAdaptationProfile(
            for: metricsID,
            isEnabled: isAutoOptimizationEnabled
        )
        if playbackAdaptationProfile != nextProfile {
            playbackAdaptationProfile = nextProfile
        }
    }

    deinit {
        pendingRefreshTask?.cancel()
    }
}
