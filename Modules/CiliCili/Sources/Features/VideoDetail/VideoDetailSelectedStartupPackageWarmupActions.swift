import Foundation

extension VideoDetailViewModel {
    func scheduleSelectedStartupPackageWarmupBeforeFirstFrame(
        _ variant: PlayVariant?,
        targetVariant: PlayVariant?,
        cid: Int?,
        page: Int?
    ) async {
        guard !isPlaybackInvalidatedForNavigation,
            let cid,
            let variant,
            variant.isPlayable,
            !variant.isProgressiveFastStart
        else { return }

        let bvid = detail.bvid
        let variantID = variant.id
        let durationHint = detail.duration.map(TimeInterval.init)
        let cdnPreference = libraryStore.effectivePlaybackCDNPreference
        let result = await VideoPreloadCenter.shared.prebuildStartupPackageAndWait(
            variant: variant,
            targetVariant: targetVariant,
            bvid: bvid,
            cid: cid,
            page: page,
            durationHint: durationHint,
            cdnPreference: cdnPreference,
            timeout: 0
        )
        if let trace = await VideoPreloadCenter.shared.takeRelatedStartupPackageWarmupTrace(for: bvid) {
            PlayerMetricsLog.record(
                .manifestStage,
                metricsID: bvid,
                title: detail.title,
                message: RelatedPlaybackStartupPackageWarmupPolicy.diagnosticMessage(
                    event: "consumed",
                    targetBVID: bvid,
                    result: trace.disposition.rawValue,
                    packageState: result.rawValue,
                    leadMilliseconds: trace.leadMilliseconds()
                )
            )
        }
        guard !Task.isCancelled,
            !isPlaybackInvalidatedForNavigation,
            detail.bvid == bvid,
            selectedCID == cid,
            selectedPlayVariant?.id == variantID
        else { return }
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: bvid,
            title: detail.title,
            message: "startupWarmEarly=\(result.rawValue) q\(variant.quality)"
        )
    }

    func scheduleSelectedStartupPackageWarmupAfterFirstFrame(_ variant: PlayVariant?, cid: Int?, page: Int?) {
        guard !isPlaybackInvalidatedForNavigation,
            let cid,
            let variant,
            variant.isPlayable,
            !variant.isProgressiveFastStart
        else { return }
        let bvid = detail.bvid
        let variantID = variant.id
        trackBackgroundTask(
            Task(priority: .utility) { [weak self, variant] in
                guard let self else { return }
                let didPresentPlayback = await self.waitForFirstFrameOrFailure()
                guard didPresentPlayback,
                    !Task.isCancelled,
                    !self.isPlaybackInvalidatedForNavigation,
                    self.detail.bvid == bvid,
                    self.selectedCID == cid,
                    self.selectedPlayVariant?.id == variantID
                else { return }
                await VideoPreloadCenter.shared.warmVariant(
                    variant,
                    bvid: bvid,
                    cid: cid,
                    page: page,
                    delay: 0.2
                )
            }
        )
    }
}
