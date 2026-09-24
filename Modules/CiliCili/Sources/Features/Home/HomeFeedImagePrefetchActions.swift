import Foundation

extension HomeFeedMediaPreloadCoordinator {
    func updateImagePrefetchProfile(_ profile: HomeFeedCoverPrefetchProfile) {
        guard imagePrefetchProfile != profile else { return }
        imagePrefetchProfile = profile
        imageLookaheadTask?.cancel()
        imageLookaheadTask = nil
        imageLookaheadRequest = nil
    }

    func scheduleImagePrefetch(for videos: [VideoItem]) {
        imagePrefetchTask?.cancel()
        resetImageLookaheadIfNeeded(for: videos)
        let environment = PlaybackEnvironment.current
        let layout = libraryStore.homeFeedLayout
        let prefetchLimit = HomeFeedImagePrefetchPolicy.initialPrefetchLimit(
            layout: layout,
            isConservative: environment.shouldPreferConservativePlayback
        )
        let prefetchPlan = HomeFeedImagePrefetchPlan.make(
            for: videos,
            profile: resolvedImagePrefetchProfile(for: layout),
            limit: prefetchLimit
        )

        guard !prefetchPlan.coverSources.isEmpty else { return }
        let coverSourcesToPrefetch = prefetchPlan.coverSources
        let coverTargetPixelSize = prefetchPlan.coverTargetPixelSize
        imagePrefetchTask = Task(priority: .utility) {
            await RemoteImageCache.shared.prefetch(
                coverSourcesToPrefetch,
                targetPixelSize: coverTargetPixelSize,
                maximumConcurrentLoads: HomeFeedImagePrefetchPolicy.maximumConcurrentLoads(
                    isConservative: environment.shouldPreferConservativePlayback
                )
            )
        }
    }

    func scheduleImageLookahead(for videos: [VideoItem], visibleIndex: Int) {
        guard videos.indices.contains(visibleIndex) else { return }
        resetImageLookaheadIfNeeded(for: videos)

        let environment = PlaybackEnvironment.current
        let layout = libraryStore.homeFeedLayout
        let startIndex = HomeFeedImagePrefetchPolicy.lookaheadStartIndex(
            visibleIndex: visibleIndex,
            layout: layout
        )
        guard startIndex < videos.count else { return }

        let profile = resolvedImagePrefetchProfile(for: layout)
        let request = HomeFeedImageLookaheadRequest(
            feedRootBVID: imageLookaheadFeedRootBVID,
            startIndex: startIndex,
            profile: profile
        )
        guard request != imageLookaheadRequest else { return }

        let prefetchPlan = HomeFeedImagePrefetchPlan.make(
            for: videos,
            profile: profile,
            startIndex: startIndex,
            limit: HomeFeedImagePrefetchPolicy.lookaheadLimit(
                layout: layout,
                isConservative: environment.shouldPreferConservativePlayback
            )
        )
        guard !prefetchPlan.coverSources.isEmpty else { return }

        imageLookaheadTask?.cancel()
        imageLookaheadRequest = request
        let coverSources = prefetchPlan.coverSources
        let targetPixelSize = prefetchPlan.coverTargetPixelSize
        let maximumConcurrentLoads = HomeFeedImagePrefetchPolicy.maximumConcurrentLoads(
            isConservative: environment.shouldPreferConservativePlayback
        )
        imageLookaheadTask = Task(priority: .utility) { [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: HomeFeedImagePrefetchPolicy.lookaheadDebounceNanoseconds()
                )
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await RemoteImageCache.shared.prefetch(
                coverSources,
                targetPixelSize: targetPixelSize,
                maximumConcurrentLoads: maximumConcurrentLoads
            )
            guard !Task.isCancelled,
                  let self,
                  self.imageLookaheadRequest == request
            else { return }
            self.imageLookaheadTask = nil
        }
    }

    func resolvedImagePrefetchProfile(for layout: HomeFeedLayout) -> HomeFeedCoverPrefetchProfile {
        imagePrefetchProfile ?? HomeFeedCoverPrefetchProfile.fallback(for: layout)
    }

    private func resetImageLookaheadIfNeeded(for videos: [VideoItem]) {
        let feedRootBVID = videos.first?.bvid ?? ""
        guard feedRootBVID != imageLookaheadFeedRootBVID else { return }
        imageLookaheadTask?.cancel()
        imageLookaheadTask = nil
        imageLookaheadRequest = nil
        imageLookaheadFeedRootBVID = feedRootBVID
    }
}
