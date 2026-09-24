import Foundation

extension VideoDetailViewModel {
    func warmCachedPlayInfoIfAvailable() {
        guard let cid = selectedCID, selectedPlayVariant == nil else { return }
        let bvid = detail.bvid
        let page = selectedPageNumber
        trackBackgroundTask(
            Task(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                if let data = await VideoPreloadCenter.shared.cachedOrPendingPlayURL(
                    for: bvid,
                    cid: cid,
                    page: page,
                    waitsForPending: false,
                    preferredQuality: self.adaptiveStartupPreferredQuality
                ) {
                    if self.shouldSkipWarmCacheForTargetQuality(data) {
                        self.logPlayURLCacheBypass(kind: "WarmCacheTargetMiss", data: data)
                        return
                    }
                    guard self.isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page),
                          self.selectedPlayVariant == nil
                    else { return }
                    await self.applyPlayURLData(
                        data,
                        cid: cid,
                        page: page,
                        source: "detailWarmCache"
                    )
                }
            }
        )
    }

    func applyPlayURLData(
        _ data: PlayURLData,
        cid: Int?,
        page: Int?,
        source: String = "unknown"
    ) async {
        let bvid = detail.bvid
        guard isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page) else { return }
        if let cid,
           await prepareHistoryResumeBeforeApplyingPlayURL(data, cid: cid) {
            await loadPlayURL()
            return
        }
        currentPlayURLData = data
        applyVideoListenAudioVariants(from: data)
        let variants = sortedPlayVariants(playVariants(from: data))
        guard let appliedState = applyPlayableVariantState(variants: variants, source: source) else { return }
        guard isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page) else { return }
        if stablePlayerViewModel == nil {
            guard isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page)
            else {
                return
            }
        }
        await schedulePostPlayURLApplicationWork(
            selectedVariant: appliedState.selectedVariant,
            targetVariant: appliedState.targetVariant,
            cid: cid,
            page: page
        )
    }

    func isPlayablePlayURLData(_ data: PlayURLData) -> Bool {
        playVariants(from: data)
            .contains(where: \.isPlayable)
    }

    private func shouldSkipWarmCacheForTargetQuality(_ data: PlayURLData) -> Bool {
        !hasRequestedPlayableVariant(in: playVariants(from: data))
    }
}
