import SwiftUI

@MainActor
struct VideoDetailRelatedPreloadActions {
    @Binding var preloadedVideoIDs: Set<String>
    let api: BiliAPIClient
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot

    func beginPreloadIfNeeded(_ video: VideoItem) async {
        guard !video.bvid.isEmpty,
              !preloadedVideoIDs.contains(video.bvid),
              preloadedVideoIDs.count < 1,
              !PlaybackEnvironment.current.shouldPreferConservativePlayback
        else { return }

        let playbackAdaptationProfile = PlayerPerformanceStore.shared.playbackAdaptationProfile(
            isEnabled: runtimeSettings.playbackAutoOptimizationEnabled
        )
        guard playbackAdaptationProfile.backgroundPreloadLimit > 1 else { return }

        preloadedVideoIDs.insert(video.bvid)
        do {
            try await Task.sleep(nanoseconds: 120_000_000)
        } catch {
            preloadedVideoIDs.remove(video.bvid)
            return
        }
        guard !Task.isCancelled else {
            preloadedVideoIDs.remove(video.bvid)
            return
        }
        await VideoPreloadCenter.shared.preloadPlayInfo(
            video,
            api: api,
            preferredQuality: runtimeSettings.preferredVideoQuality,
            cdnPreference: runtimeSettings.effectivePlaybackCDNPreference,
            priority: .utility,
            warmsMedia: false,
            mediaWarmupMode: .routePlanOnly,
            mediaWarmupDelay: 0,
            playbackAdaptationProfile: playbackAdaptationProfile
        )
    }
}
