struct HomeFeedPreloadContext {
    let api: BiliAPIClient
    let preferredQuality: Int?
    let cdnPreference: PlaybackCDNPreference
    let playbackAdaptationProfile: PlayerPlaybackAdaptationProfile
}
