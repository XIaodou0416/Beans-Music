import Foundation

extension VideoDetailViewModel {
    func retryRelated() async {
        cancelRelatedLoadingTask()
        cancelRelatedRefreshTask()
        related = []
        relatedState = .idle
        lastRelatedLoadTimedOut = false
        await loadRelated(forceRefresh: true)
    }

    func loadRelated(forceRefresh: Bool = false) async {
        guard !relatedState.isLoading else { return }
        if detail.isPGCEpisode {
            related = []
            relatedState = .idle
            lastRelatedLoadTimedOut = false
            return
        }
        guard related.isEmpty || forceRefresh else {
            await refreshRelatedInBackgroundIfNeeded()
            return
        }
        let bvid = detail.bvid
        let timeout = adaptiveRelatedLoadTimeoutNanoseconds
        if !forceRefresh, await applyCachedRelatedVideosIfAvailable(bvid: bvid) {
            return
        }

        prepareRelatedNetworkLoad()
        defer {
            if related.isEmpty, relatedState.isLoading {
                relatedState = .idle
            }
        }
        do {
            let videos = try await fetchRelatedWithTimeout(
                bvid: bvid,
                timeout: timeout,
                forceRefresh: true
            )
            guard !Task.isCancelled,
                  !isPlaybackInvalidatedForNavigation,
                  detail.bvid == bvid
            else { return }
            applyRelatedNetworkLoadResult(videos)
        } catch VideoDetailLoadTimeoutError.related {
            await handleRelatedLoadTimeout(bvid: bvid)
        } catch {
            await handleRelatedLoadFailure(error, bvid: bvid)
        }
    }

}
