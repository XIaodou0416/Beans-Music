import Foundation

extension VideoDetailViewModel {
    func prepareNetworkPreferencesForPlayURLLoading() {
        let preferredQuality = adaptiveStartupPreferredQuality
        let targetPreferredQuality = targetPlaybackPreferredQuality
        let cdnPreference = libraryStore.effectivePlaybackCDNPreference
        let playbackAdaptationProfile = playbackAdaptationProfile
        trackBackgroundTask(
            Task(priority: .utility) {
                await VideoPreloadCenter.shared.updatePlaybackPreferences(
                    preferredQuality: preferredQuality,
                    targetPreferredQuality: targetPreferredQuality,
                    cdnPreference: cdnPreference,
                    playbackAdaptationProfile: playbackAdaptationProfile
                )
            }
        )
    }
}
