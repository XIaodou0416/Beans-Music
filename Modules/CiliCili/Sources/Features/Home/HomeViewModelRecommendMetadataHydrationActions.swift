import Foundation

extension HomeViewModel {
    func cancelRecommendMetadataHydrationTasks() {
        recommendMetadataHydrationTasks.values.forEach { $0.cancel() }
        recommendMetadataHydrationTasks.removeAll()
    }

    func scheduleRecommendMetadataHydration(
        for candidates: [VideoItem],
        revision: Int,
        reason: String
    ) {
        guard mode == .recommend,
              pageCoordinator.usesNativeAppRecommendSource(for: mode)
        else { return }

        let missingVideos = candidates.filter(Self.needsRecommendMetadataHydration)
        guard !missingVideos.isEmpty else { return }

        let taskKey = [
            String(revision),
            reason,
            missingVideos.prefix(4).map(\.id).joined(separator: ","),
            String(missingVideos.count)
        ].joined(separator: "|")
        let api = pageCoordinator.api

        recommendMetadataHydrationTasks[taskKey]?.cancel()
        recommendMetadataHydrationTasks[taskKey] = Task(priority: .utility) { [weak self, api, missingVideos, revision, taskKey] in
            let hydratedVideos = await api.hydrateRecommendMetadataIfNeeded(missingVideos)
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                self?.finishRecommendMetadataHydration(
                    hydratedVideos,
                    revision: revision,
                    taskKey: taskKey
                )
            }
        }
    }

    private static func needsRecommendMetadataHydration(_ video: VideoItem) -> Bool {
        video.aid != nil && (video.pubdate == nil || video.owner?.face == nil)
    }

    private func finishRecommendMetadataHydration(
        _ hydratedVideos: [VideoItem],
        revision: Int,
        taskKey: String
    ) {
        defer {
            recommendMetadataHydrationTasks[taskKey] = nil
        }
        guard revision == requestRevision,
              mode == .recommend,
              pageCoordinator.usesNativeAppRecommendSource(for: mode),
              !hydratedVideos.isEmpty
        else { return }

        let hydratedByID = Dictionary(uniqueKeysWithValues: hydratedVideos.map { ($0.id, $0) })
        let hydratedByAID = Dictionary(
            hydratedVideos.compactMap { video -> (Int, VideoItem)? in
                guard let aid = video.aid else { return nil }
                return (aid, video)
            },
            uniquingKeysWith: { first, _ in first }
        )
        var didChange = false
        var changedVideos = [VideoItem]()
        let mergedVideos = videos.map { video -> VideoItem in
            let hydrated = hydratedByID[video.id] ?? video.aid.flatMap { hydratedByAID[$0] }
            guard let hydrated else { return video }
            let merged = video.mergingFilledValues(from: hydrated)
            if merged != video {
                didChange = true
                changedVideos.append(merged)
            }
            return merged
        }

        guard didChange else { return }
        updateFeed(mergedVideos)
        snapshotCoordinator.save(
            videos: videos,
            mode: mode,
            lastSeenMarkerIndex: lastSeenMarkerIndex
        )
        mediaPreloadCoordinator.scheduleImagePrefetch(for: Array(changedVideos.prefix(8)))
    }
}
