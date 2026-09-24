import Foundation

@MainActor
enum HomeFeedPreloadContextFactory {
    static func make(dependencies: AppDependencies) -> HomeFeedPreloadContext {
        let libraryStore = dependencies.libraryStore
        return HomeFeedPreloadContext(
            api: dependencies.api,
            preferredQuality: libraryStore.effectivePreferredVideoQuality,
            cdnPreference: libraryStore.effectivePlaybackCDNPreference,
            playbackAdaptationProfile: PlayerPerformanceStore.shared.playbackAdaptationProfile(
                isEnabled: libraryStore.isPlaybackAutoOptimizationEnabled
            )
        )
    }
}
