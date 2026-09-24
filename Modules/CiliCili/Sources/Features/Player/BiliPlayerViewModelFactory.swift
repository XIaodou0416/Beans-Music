import Foundation

enum BiliPlayerViewModelFactory {
    @MainActor
    static func makeDirectURLViewModel(
        videoURL: URL,
        title: String,
        referer: String,
        duration: TimeInterval?
    ) -> PlayerStateViewModel {
        PlayerStateViewModel(
            videoURL: videoURL,
            audioURL: nil,
            videoStream: nil,
            audioStream: nil,
            title: title,
            referer: referer,
            durationHint: duration,
            metricsID: nil,
            engine: DefaultPlayerRenderingEngine.make()
        )
    }

    @MainActor
    static func makePlayVariantViewModel(
        playVariant: PlayVariant,
        title: String,
        referer: String,
        duration: TimeInterval?,
        resumeTime: TimeInterval?,
        historyVideo: VideoItem?,
        cdnPreference: PlaybackCDNPreference
    ) -> PlayerStateViewModel {
        PlayerStateViewModel(
            videoURL: playVariant.videoURL,
            audioURL: playVariant.audioURL,
            videoStream: playVariant.videoStream,
            audioStream: playVariant.audioStream,
            title: title,
            authorName: historyVideo?.owner?.name,
            referer: referer,
            durationHint: duration,
            resumeTime: resumeTime ?? 0,
            dynamicRange: playVariant.dynamicRange,
            cdnPreference: cdnPreference,
            metricsID: historyVideo?.bvid,
            artworkURL: artworkURL(from: historyVideo?.pic)
        )
    }

    private static func artworkURL(from urlString: String?) -> URL? {
        guard let normalized = urlString?.normalizedBiliURL() else { return nil }
        return URL(string: normalized.biliImageThumbnailURL(maxSide: 720))
            ?? URL(string: normalized)
    }
}
