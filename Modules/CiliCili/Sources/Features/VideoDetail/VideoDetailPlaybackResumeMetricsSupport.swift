import Foundation
import OSLog

extension VideoDetailViewModel {
    private static var slowPlayURLFeedbackThresholdMilliseconds: Int { 1_500 }
    private static var slowPrepareFeedbackThresholdMilliseconds: Int { 1_800 }
    private static var poorPrepareCDNAvoidanceThresholdMilliseconds: Int { 2_400 }
    private static var slowFirstFrameFeedbackThresholdMilliseconds: Int { 2_600 }
    private static var poorFirstFrameCDNAvoidanceThresholdMilliseconds: Int { 3_400 }
    private static var startupCDNAvoidanceDuration: TimeInterval { 15 * 60 }

    func recordStartupPlaybackMetrics(
        variant: PlayVariant,
        resumeCandidate: PlaybackResumeCandidate,
        playerViewModel: PlayerStateViewModel,
        firstFrameElapsedMilliseconds: Int
    ) {
        let detailElapsed = elapsedMilliseconds(since: detailLoadStartTime)
        let playURLElapsed = playURLElapsedMilliseconds ?? elapsedMilliseconds(since: playURLLoadStartTime)
        let prepareElapsed = playerViewModel.prepareElapsedMilliseconds
        let playbackElapsed = playerViewModel.firstFrameElapsedMilliseconds ?? firstFrameElapsedMilliseconds
        let cdnPreference = libraryStore.effectivePlaybackCDNPreference
        let environment = PlaybackEnvironment.current
        let resumeText = resumeCandidate.time > 0.25
            ? String(format: "%.2fs", resumeCandidate.time)
            : "none"
        let summary = [
            "detail=\(formattedMilliseconds(detailElapsed))",
            "playurl=\(formattedMilliseconds(playURLElapsed))",
            "prepare=\(formattedMilliseconds(prepareElapsed))",
            "firstFrame=\(formatMilliseconds(playbackElapsed))",
            "resume=\(resumeText)",
            "cid=\(selectedCID ?? 0)",
            "source=\(lastPlayURLSource ?? "-")",
            "q=\(variant.quality)",
            "targetQ=\(targetPlaybackPreferredQuality ?? 0)",
            "cdn=\(cdnPreference.rawValue)",
            "network=\(environment.networkClass.performanceSampleKey)"
        ].joined(separator: " ")
        PlayerMetricsLog.signpostEvent(
            "VideoDetailStartupBreakdown",
            message: summary
        )
        PlayerMetricsLog.logger.info(
            "startupBreakdown bvid=\(self.detail.bvid, privacy: .public) \(summary, privacy: .public)"
        )
        PlayerMetricsLog.record(
            .startupBreakdown,
            metricsID: detail.bvid,
            title: detail.title,
            message: summary
        )
        recordStartupPlaybackQualityFeedback(
            variant: variant,
            playURLElapsedMilliseconds: playURLElapsed,
            prepareElapsedMilliseconds: prepareElapsed,
            firstFrameElapsedMilliseconds: playbackElapsed,
            bufferingCount: playerViewModel.bufferingCount
        )
    }

    private func recordStartupPlaybackQualityFeedback(
        variant: PlayVariant,
        playURLElapsedMilliseconds: Int?,
        prepareElapsedMilliseconds: Int?,
        firstFrameElapsedMilliseconds: Int,
        bufferingCount: Int
    ) {
        let decision = startupPlaybackFeedbackDecision(
            playURLElapsedMilliseconds: playURLElapsedMilliseconds,
            prepareElapsedMilliseconds: prepareElapsedMilliseconds,
            firstFrameElapsedMilliseconds: firstFrameElapsedMilliseconds,
            bufferingCount: bufferingCount
        )
        recordStartupPlaybackURLFeedback(
            for: variant,
            decision: decision,
            prepareElapsedMilliseconds: prepareElapsedMilliseconds,
            firstFrameElapsedMilliseconds: firstFrameElapsedMilliseconds
        )

        let cdnPreference = libraryStore.effectivePlaybackCDNPreference
        PlayerMetricsLog.record(
            .network,
            metricsID: detail.bvid,
            title: detail.title,
            message: [
                "qualityFeedback",
                "status=\(decision.status)",
                "reason=\(decision.reason)",
                "action=\(decision.shouldAvoidCDN ? "avoidCDN" : "observe")",
                "q=\(variant.quality)",
                "cdn=\(diagnosticToken(cdnPreference.rawValue))",
                "videoHost=\(diagnosticToken(variant.videoURL?.host ?? "-"))",
                "audioHost=\(diagnosticToken(variant.audioURL?.host ?? "-"))",
                "playurl=\(playURLElapsedMilliseconds.map { "\($0)ms" } ?? "-")",
                "prepare=\(prepareElapsedMilliseconds.map { "\($0)ms" } ?? "-")",
                "firstFrame=\(firstFrameElapsedMilliseconds)ms",
                "buffering=\(bufferingCount)"
            ].joined(separator: " ")
        )

        guard decision.shouldAvoidCDN,
              libraryStore.isPlaybackAutoOptimizationEnabled,
              libraryStore.playbackCDNPreference == .automatic
        else { return }
        temporarilyAvoidCurrentAutomaticPlaybackCDN(
            reason: "startupQuality \(decision.reason)",
            duration: Self.startupCDNAvoidanceDuration
        )
        PlaybackCDNProbeCoordinator.shared.refreshForPlaybackPressure(libraryStore: libraryStore)
    }

    private func startupPlaybackFeedbackDecision(
        playURLElapsedMilliseconds: Int?,
        prepareElapsedMilliseconds: Int?,
        firstFrameElapsedMilliseconds: Int,
        bufferingCount: Int
    ) -> StartupPlaybackQualityFeedbackDecision {
        let playURL = playURLElapsedMilliseconds ?? 0
        let prepare = prepareElapsedMilliseconds ?? 0
        let hasStartupBuffering = bufferingCount > 0

        if prepare >= Self.poorPrepareCDNAvoidanceThresholdMilliseconds {
            return StartupPlaybackQualityFeedbackDecision(
                status: "poor",
                reason: "slowPrepare",
                shouldAvoidCDN: true,
                urlFeedbackStallPenalty: 1
            )
        }
        if firstFrameElapsedMilliseconds >= Self.poorFirstFrameCDNAvoidanceThresholdMilliseconds,
           hasStartupBuffering || prepare >= Self.slowPrepareFeedbackThresholdMilliseconds {
            return StartupPlaybackQualityFeedbackDecision(
                status: "poor",
                reason: "slowFirstFrame",
                shouldAvoidCDN: true,
                urlFeedbackStallPenalty: 1
            )
        }
        if playURL >= Self.slowPlayURLFeedbackThresholdMilliseconds {
            return StartupPlaybackQualityFeedbackDecision(
                status: "slow",
                reason: "slowPlayURL",
                shouldAvoidCDN: false,
                urlFeedbackStallPenalty: 0
            )
        }
        if firstFrameElapsedMilliseconds >= Self.slowFirstFrameFeedbackThresholdMilliseconds
            || prepare >= Self.slowPrepareFeedbackThresholdMilliseconds
            || hasStartupBuffering {
            return StartupPlaybackQualityFeedbackDecision(
                status: "slow",
                reason: hasStartupBuffering ? "startupBuffering" : "startupLatency",
                shouldAvoidCDN: false,
                urlFeedbackStallPenalty: 0
            )
        }
        return StartupPlaybackQualityFeedbackDecision(
            status: "healthy",
            reason: "startupOK",
            shouldAvoidCDN: false,
            urlFeedbackStallPenalty: 0
        )
    }

    private func recordStartupPlaybackURLFeedback(
        for variant: PlayVariant,
        decision: StartupPlaybackQualityFeedbackDecision,
        prepareElapsedMilliseconds: Int?,
        firstFrameElapsedMilliseconds: Int
    ) {
        guard let videoURL = variant.videoURL else { return }
        let transferMilliseconds = max(
            prepareElapsedMilliseconds ?? 0,
            min(firstFrameElapsedMilliseconds, 8_000)
        )
        guard transferMilliseconds > 0 else { return }

        let observedKilobitsPerSecond = max((variant.bandwidth ?? variant.videoStream?.bandwidth ?? 0) / 1_000, 0)
        guard observedKilobitsPerSecond > 0 || decision.urlFeedbackStallPenalty > 0 else { return }
        PlaybackURLPreferenceStore.shared.recordPlaybackFeedback(
            url: videoURL,
            observedKilobitsPerSecond: observedKilobitsPerSecond,
            transferMilliseconds: transferMilliseconds,
            bytes: 0,
            stallCount: decision.urlFeedbackStallPenalty
        )
    }
}

private struct StartupPlaybackQualityFeedbackDecision {
    let status: String
    let reason: String
    let shouldAvoidCDN: Bool
    let urlFeedbackStallPenalty: Int
}
