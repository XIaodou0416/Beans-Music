import Foundation
import QuartzCore

extension VideoDetailViewModel {
    private static var coldStartPackageWarmupPlayerCreationWait: TimeInterval { 0.08 }
    private static var cachedPlayURLStartupPackageWarmupPlayerCreationWait: TimeInterval { 0.16 }
    private static var historyResumeWarmupPlayerCreationWait: TimeInterval {
        let normalBudget = PlaybackEnvironment.current.shouldPreferConservativePlayback ? 0.18 : 0.12
        return ResourceLoadingExperiment.resumeWarmupWait(normalBudget: normalBudget)
    }

    func schedulePostPlayURLApplicationWork(
        selectedVariant: PlayVariant?,
        targetVariant: PlayVariant?,
        cid: Int?,
        page: Int?
    ) async {
        guard !isPlaybackInvalidatedForNavigation else { return }
        let resumeTime = consumePendingPlaybackHistoryResumeTime(for: cid)
        await scheduleSelectedStartupPackageWarmupBeforeFirstFrame(
            selectedVariant,
            targetVariant: targetVariant,
            cid: cid,
            page: page
        )
        let historyResumeWarmupTask = historyResumeWarmupTaskBeforePlayerCreation(
            selectedVariant,
            cid: cid,
            page: page,
            resumeTime: resumeTime
        )
        scheduleSelectedStartupPackageWarmupAfterFirstFrame(selectedVariant, cid: cid, page: page)
        await waitForStartupPackageWarmupBeforePlayerCreationIfNeeded(
            selectedVariant,
            targetVariant: targetVariant,
            cid: cid,
            page: page
        )
        await waitForHistoryResumeWarmupBeforePlayerCreationIfNeeded(
            historyResumeWarmupTask,
            selectedVariant: selectedVariant,
            cid: cid,
            resumeTime: resumeTime
        )
        updateStablePlayerViewModelIfNeeded(resumeTimeOverride: resumeTime)
        playURLState = .loaded
        warmSelectedVariantAfterFirstFrameIfNeeded(selectedVariant, cid: cid, page: page)
        scheduleAutomaticCDNRecommendationAfterFirstFrameIfNeeded(
            variant: selectedVariant,
            cid: cid,
            page: page
        )
        rankPlaybackCDNCandidatesAfterFirstFrameIfNeeded(selectedVariant, cid: cid)
        scheduleHLSRenditionPrebuildAfterFirstFrameIfNeeded(
            startupVariant: selectedVariant,
            targetVariant: targetVariant,
            cid: cid,
            page: page
        )
    }

    private func historyResumeWarmupTaskBeforePlayerCreation(
        _ selectedVariant: PlayVariant?,
        cid: Int?,
        page: Int?,
        resumeTime: TimeInterval?
    ) -> Task<Bool, Never>? {
        guard stablePlayerViewModel == nil,
            !isPlaybackInvalidatedForNavigation,
            let cid,
            let selectedVariant,
            selectedVariant.isPlayable,
            !selectedVariant.isProgressiveFastStart,
            let resumeTime,
            resumeTime > 0.25
        else { return nil }

        let bvid = detail.bvid
        return Task(priority: .userInitiated) { [selectedVariant] in
            await VideoPreloadCenter.shared.warmVariantAroundSeek(
                selectedVariant,
                bvid: bvid,
                cid: cid,
                page: page,
                playbackTime: resumeTime,
                timeout: Self.historyResumeWarmupPlayerCreationWait
            )
        }
    }

    private func waitForHistoryResumeWarmupBeforePlayerCreationIfNeeded(
        _ task: Task<Bool, Never>?,
        selectedVariant: PlayVariant?,
        cid: Int?,
        resumeTime: TimeInterval?
    ) async {
        guard let task,
            let selectedVariant,
            let cid,
            let resumeTime
        else { return }

        let bvid = detail.bvid
        let selectedVariantID = selectedVariant.id
        let startedAt = CACurrentMediaTime()
        let didWarm = await task.value
        let elapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: startedAt)
        guard !Task.isCancelled,
            !isPlaybackInvalidatedForNavigation,
            detail.bvid == bvid,
            selectedCID == cid,
            selectedPlayVariant?.id == selectedVariantID
        else { return }

        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: bvid,
            title: detail.title,
            message: [
                "historyResumeWarm=\(didWarm ? "hit" : "timeout")",
                "target=\(String(format: "%.2fs", resumeTime))",
                "\(Int(elapsedMilliseconds.rounded()))ms",
                "budget=\(Int((Self.historyResumeWarmupPlayerCreationWait * 1000).rounded()))ms",
                "q\(selectedVariant.quality)",
            ].joined(separator: " ")
        )
        guard ResourceLoadingExperiment.isFeatureEnabled(.resumePacketWarmup) else { return }
        ResourceLoadingDiagnostics.shared.record(
            didWarm ? .resumeWarmupHit : .resumeWarmupTimeout,
            durationMilliseconds: Int(elapsedMilliseconds.rounded()),
            details: [
                "budget": "\(Int((Self.historyResumeWarmupPlayerCreationWait * 1_000).rounded()))ms",
                "quality": "q\(selectedVariant.quality)",
            ]
        )
    }

    private func waitForStartupPackageWarmupBeforePlayerCreationIfNeeded(
        _ selectedVariant: PlayVariant?,
        targetVariant: PlayVariant?,
        cid: Int?,
        page: Int?
    ) async {
        guard stablePlayerViewModel == nil,
            !isPlaybackInvalidatedForNavigation,
            let cid,
            let selectedVariant,
            selectedVariant.isPlayable
        else { return }

        let bvid = detail.bvid
        let selectedVariantID = selectedVariant.id
        let startedAt = CACurrentMediaTime()
        let timeout = startupPackageWarmupPlayerCreationWaitForCurrentLoad()
        let result = await VideoPreloadCenter.shared.prebuildStartupPackageAndWait(
            variant: selectedVariant,
            targetVariant: targetVariant,
            bvid: bvid,
            cid: cid,
            page: page,
            durationHint: detail.duration.map(TimeInterval.init),
            cdnPreference: libraryStore.effectivePlaybackCDNPreference,
            timeout: timeout
        )
        let elapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: startedAt)
        guard !isPlaybackInvalidatedForNavigation,
            detail.bvid == bvid,
            selectedCID == cid,
            selectedPlayVariant?.id == selectedVariantID
        else { return }
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: bvid,
            message: [
                "startupWarmWait=\(result.rawValue)",
                "mode=immediateCreate",
                "\(Int(elapsedMilliseconds.rounded()))ms",
                "budget=\(Int((timeout * 1000).rounded()))ms",
                "codec=\(selectedVariant.codec?.replacingOccurrences(of: " ", with: "_") ?? "-")",
            ].joined(separator: " ")
        )
    }

    private func startupPackageWarmupPlayerCreationWaitForCurrentLoad() -> TimeInterval {
        let normalBudget: TimeInterval
        if lastPlayURLSource?.localizedCaseInsensitiveContains("cache") == true {
            normalBudget = Self.cachedPlayURLStartupPackageWarmupPlayerCreationWait
        } else {
            normalBudget = Self.coldStartPackageWarmupPlayerCreationWait
        }
        return AVPlayerStartupPathOptimizationExperiment.playerCreationWarmupWait(
            normalBudget: normalBudget
        )
    }
}
