import Foundation

extension VideoDetailViewModel {
    func logStablePlayerCreated(variant: PlayVariant) {
        let cdnPreference = libraryStore.effectivePlaybackCDNPreference
        PlayerMetricsLog.record(
            .playerCreated,
            metricsID: detail.bvid,
            title: detail.title,
            message: "\(variant.title) · CDN \(cdnPreference.title)"
        )
        if let host = variant.videoURL?.host ?? variant.audioURL?.host {
            PlayerMetricsLog.record(
                .network,
                metricsID: detail.bvid,
                title: detail.title,
                message: "host=\(host) cdn=\(cdnPreference.rawValue) quality=\(variant.quality)"
            )
        }
    }
}
