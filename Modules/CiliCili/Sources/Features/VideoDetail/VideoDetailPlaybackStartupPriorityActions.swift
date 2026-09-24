import Foundation

extension VideoDetailViewModel {
    func prioritizeCurrentPlaybackForStartup() async {
        let preferredQuality = adaptiveStartupPreferredQuality
        let targetPreferredQuality = targetPlaybackPreferredQuality
        let cdnPreference = libraryStore.effectivePlaybackCDNPreference
        let adaptationProfile = playbackAdaptationProfile
        let currentDetail = detail

        await VideoPreloadCenter.shared.updatePlaybackPreferences(
            preferredQuality: preferredQuality,
            targetPreferredQuality: targetPreferredQuality,
            cdnPreference: cdnPreference,
            playbackAdaptationProfile: adaptationProfile
        )
        await VideoPreloadCenter.shared.prioritizePlayback(for: currentDetail)
    }
}
