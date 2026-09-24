import Foundation
import Combine
import UIKit

@MainActor
final class AppDependencies: ObservableObject {
    let sessionStore: SessionStore
    let libraryStore: LibraryStore
    let homeRecommendDiagnosticsStore: HomeRecommendDiagnosticsStore
    let api: BiliAPIClient
    let accountMessageService: AccountMessageService
    let sponsorBlockService: SponsorBlockService
    private let networkMetricsRecorder: BiliNetworkMetricsRecorder
    private var sessionCancellables = Set<AnyCancellable>()
    private var hasScheduledStartupWork = false
    private var hasCompletedStartupMaintenance = false
    private var startupWarmupTask: Task<Void, Never>?
    private var startupMaintenanceTask: Task<Void, Never>?
    private let playbackNetworkRefreshCoordinator = PlaybackNetworkRefreshCoordinator()

    init() {
        let sessionStore = SessionStore()
        let libraryStore = LibraryStore()
        let homeRecommendDiagnosticsStore = HomeRecommendDiagnosticsStore.shared
        let networkMetricsRecorder = BiliNetworkMetricsRecorder()
        self.sessionStore = sessionStore
        self.libraryStore = libraryStore
        self.homeRecommendDiagnosticsStore = homeRecommendDiagnosticsStore
        self.networkMetricsRecorder = networkMetricsRecorder
        StageOneBaselineMetricsStore.shared.beginLaunch()
        let api = BiliAPIClient(
            session: BiliURLSessionFactory.makeAPISession(delegate: networkMetricsRecorder),
            sessionStore: sessionStore,
            libraryStore: libraryStore,
            homeRecommendDiagnosticsStore: homeRecommendDiagnosticsStore
        )
        self.api = api
        self.accountMessageService = AccountMessageService(sessionStore: sessionStore, api: api)
        self.sponsorBlockService = SponsorBlockService()
        sessionStore.$playbackCredentialVersion
            .dropFirst()
            .sink { [weak self] _ in
                Task {
                    await PlayURLCache.shared.invalidateForLoginStateChange()
                    await VideoPreloadCenter.shared.clearPlayURLCache()
                    await self?.api.resetPlaybackAuthorizationState()
                    await self?.api.resetHomeRecommendState()
                    self?.homeRecommendDiagnosticsStore.reset()
                    HomeRecommendFeedbackCenter.shared.reset()
                    HomeFeedSnapshotCache.clearAll()
                }
            }
            .store(in: &sessionCancellables)
        Publishers.CombineLatest(
            sessionStore.$playbackAccountCredentialVersion,
            libraryStore.$multiAccountExperimentEnabled
        )
            .removeDuplicates { lhs, rhs in
                lhs.0 == rhs.0 && lhs.1 == rhs.1
            }
            .dropFirst()
            .sink { [weak self] _ in
                Task {
                    await PlayURLCache.shared.invalidateForLoginStateChange()
                    await VideoPreloadCenter.shared.clearPlayURLCache()
                    await self?.api.resetPlaybackAuthorizationState()
                }
            }
            .store(in: &sessionCancellables)
        libraryStore.$playbackStreamSourcePreference
            .removeDuplicates()
            .dropFirst()
            .sink { _ in
                Task {
                    await PlayURLCache.shared.clearMemoryCache()
                    await VideoPreloadCenter.shared.clearPlayURLCache()
                }
            }
            .store(in: &sessionCancellables)
        NotificationCenter.default.publisher(for: .biliPlaybackNetworkClassDidChange)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handlePlaybackNetworkClassChange()
                }
            }
            .store(in: &sessionCancellables)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleAppDidBecomeActive()
                }
            }
            .store(in: &sessionCancellables)
    }

    deinit {
        startupWarmupTask?.cancel()
        startupMaintenanceTask?.cancel()
    }

    func refreshPlaybackCDNProbeIfNeeded() {
        PlaybackCDNProbeCoordinator.shared.refreshIfNeeded(libraryStore: libraryStore)
    }

    func refreshPlaybackCDNProbeOnAppActivationIfNeeded() {
        PlaybackCDNProbeCoordinator.shared.refreshOnAppActivationIfNeeded(libraryStore: libraryStore)
    }

    func scheduleStartupWorkIfNeeded() {
        guard !hasScheduledStartupWork else { return }
        hasScheduledStartupWork = true
        StageOneBaselineMetricsStore.shared.markStartupWarmupStarted()

        let api = api
        let dynamicFeedIdentityKey = sessionStore.accountCacheIdentityKey(
            for: .dynamicFeed,
            multiAccountEnabled: libraryStore.multiAccountExperimentEnabled
        )
        let shouldPrewarmDynamicFeed = sessionStore.isLoggedIn
        startupWarmupTask = Task(priority: .utility) {
            async let startupResources: Void = api.prewarmStartupResources()
            if shouldPrewarmDynamicFeed {
                await DynamicFeedWarmCache.shared.prewarm(
                    api: api,
                    identityKey: dynamicFeedIdentityKey
                )
            }
            _ = await startupResources
            StageOneBaselineMetricsStore.shared.markStartupWarmupFinished()
        }

        startupMaintenanceTask = Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return }
            await RemoteImageCache.shared.applyAdaptiveBudget()
            await ResourceCacheCenter.enforceConfiguredLimit()
            guard !Task.isCancelled else { return }
            self.refreshPlaybackCDNProbeOnAppActivationIfNeeded()
            self.hasCompletedStartupMaintenance = true
        }
    }

    private func handleAppDidBecomeActive() {
        guard hasCompletedStartupMaintenance else {
            scheduleStartupWorkIfNeeded()
            return
        }
        refreshPlaybackCDNProbeOnAppActivationIfNeeded()
    }

    private func handlePlaybackNetworkClassChange() {
        playbackNetworkRefreshCoordinator.submit { [weak self] in
            self?.refreshForPlaybackNetworkClassChange()
        }
    }

    private func refreshForPlaybackNetworkClassChange() {
        StageOneBaselineMetricsStore.shared.recordNetworkRefreshBatch()
        libraryStore.syncPlaybackCDNProbeSnapshotForCurrentContext()
        Task(priority: .utility) { [libraryStore] in
            await RemoteImageCache.shared.refreshNetworkSessionForPathChange()
            BiliPlaybackNetworkSessionPool.shared.refreshForNetworkPathChange()
            PlaybackRangeStreamingSessionCoordinator.refreshForNetworkPathChange()
            PlaybackCDNProbeCoordinator.shared.refreshIfNeeded(libraryStore: libraryStore)
        }
    }

}

@MainActor
final class PlaybackNetworkRefreshCoordinator {
    private let stabilizationDelay: Duration
    private let debouncer = TaskDebouncer()

    init(stabilizationDelay: Duration = .seconds(1)) {
        self.stabilizationDelay = stabilizationDelay
    }

    func submit(refresh: @escaping @MainActor () -> Void) {
        debouncer.schedule(delay: stabilizationDelay) {
            refresh()
        }
    }
}
