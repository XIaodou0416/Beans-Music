import Foundation

extension VideoDetailViewModel {
    func recordHLSRenditionPrebuildQueued(_ candidates: [PlayVariant]) {
        let candidateSummary = Self.hlsQualitySummary(candidates.map(\.quality))
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: detail.bvid,
            title: detail.title,
            message: "prebuildQueued=\(candidateSummary)"
        )
    }

    func recordHLSRenditionPrebuildResult(candidate: PlayVariant, didWarm: Bool) {
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: detail.bvid,
            title: detail.title,
            message: "prebuild q\(candidate.quality)=\(didWarm ? "ready" : "skip")"
        )
    }
}
