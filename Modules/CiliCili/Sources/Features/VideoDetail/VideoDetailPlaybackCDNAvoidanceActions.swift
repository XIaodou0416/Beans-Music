import Foundation

extension VideoDetailViewModel {
    func temporarilyAvoidCurrentAutomaticPlaybackCDN(
        reason: String,
        duration: TimeInterval = 10 * 60
    ) {
        guard libraryStore.playbackCDNPreference == .automatic else { return }
        let currentPreference = libraryStore.effectivePlaybackCDNPreference
        guard currentPreference != .automatic,
              libraryStore.temporarilyAvoidAutomaticPlaybackCDN(currentPreference, duration: duration)
        else { return }
        PlayerMetricsLog.record(
            .network,
            metricsID: detail.bvid,
            title: detail.title,
            message: [
                "automaticCDNAvoided",
                "cdn=\(currentPreference.rawValue)",
                "duration=\(Int(duration.rounded()))s",
                "reason=\(diagnosticToken(reason))"
            ].joined(separator: " ")
        )
    }
}
