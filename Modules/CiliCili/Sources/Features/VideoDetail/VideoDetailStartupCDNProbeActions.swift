import Foundation

extension VideoDetailViewModel {
    func optimizedStartupVariant(_ variant: PlayVariant?, source: String) async -> PlayVariant? {
        guard let variant, variant.isPlayable else { return variant }
        guard stablePlayerViewModel?.hasPresentedPlayback == true || playbackStartupRelease == .firstFrame else {
            PlayerMetricsLog.record(
                .network,
                metricsID: detail.bvid,
                title: detail.title,
                message: "startupURLProbe deferred source=\(source) q=\(variant.quality)"
            )
            return variant
        }
        let cdnPreference = libraryStore.effectivePlaybackCDNPreference
        let headers = BiliHLSManifestBuilder.httpHeaders(referer: "https://www.bilibili.com/video/\(detail.bvid)")
        let selection = await PlayerMetricsLog.withSignpostedInterval(
            "VideoDetailPostFirstFrameURLProbe",
            message: "bvid=\(detail.bvid) source=\(source) q=\(variant.quality)"
        ) {
            await PlaybackStartupURLProbeService.optimizedVariant(
                for: variant,
                cdnPreference: cdnPreference,
                headers: headers,
                timeout: startupURLProbeBudget
            )
        }
        let optimizedVariant = selection.variant
        let didChangeURL = optimizedVariant.videoURL != variant.videoURL
            || optimizedVariant.audioURL != variant.audioURL
        if didChangeURL || selection.videoElapsedMilliseconds != nil || selection.audioElapsedMilliseconds != nil {
            let videoHost = optimizedVariant.videoURL?.host ?? "-"
            let audioHost = optimizedVariant.audioURL?.host ?? "-"
            PlayerMetricsLog.record(
                .network,
                metricsID: detail.bvid,
                title: detail.title,
                message: "postFirstFrameURLProbe source=\(source) validated=\(selection.startupValidated) video=\(selection.videoElapsedMilliseconds.map { "\($0)ms" } ?? "-") audio=\(selection.audioElapsedMilliseconds.map { "\($0)ms" } ?? "-") host=\(videoHost) audioHost=\(audioHost)"
            )
        }
        return optimizedVariant
    }

    var cdnRecommendationStartupBudget: TimeInterval {
        switch PlaybackEnvironment.current.networkClass {
        case .wifi:
            return 0.28
        case .unknown:
            return 0.22
        case .cellular, .constrained:
            return 0.16
        }
    }

    private var startupURLProbeBudget: TimeInterval {
        let baseBudget: TimeInterval
        switch PlaybackEnvironment.current.networkClass {
        case .wifi:
            baseBudget = 0.32
        case .unknown:
            baseBudget = 0.24
        case .cellular, .constrained:
            baseBudget = 0.18
        }
        guard playbackAdaptationProfile.shouldRefreshPlaybackCDNProbe else {
            return baseBudget
        }
        return min(cdnRecommendationStartupBudget, baseBudget + 0.08)
    }
}
