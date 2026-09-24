import Foundation

extension VideoDetailViewModel {
    func loadPgcRelated(forceRefresh: Bool = false) async {
        guard related.isEmpty || forceRefresh else { return }
        guard let seasonID = detail.pgcSeasonID else {
            relatedState = .failed("暂无相关推荐")
            return
        }

        let sourceDetail = detail
        let sourceBVID = detail.bvid
        let sourceEpisodeID = detail.pgcEpisodeID
        prepareRelatedNetworkLoad()

        do {
            let season = try await api.fetchPgcSeasonInfo(seasonID: seasonID, epID: sourceEpisodeID)
            guard !Task.isCancelled,
                  !isPlaybackInvalidatedForNavigation,
                  detail.bvid == sourceBVID,
                  detail.pgcSeasonID == seasonID,
                  detail.pgcEpisodeID == sourceEpisodeID
            else { return }

            let videos = season.relatedEpisodeVideoItems(
                excluding: sourceDetail,
                limit: Self.relatedRecommendationsLimit
            )
            applyRelatedNetworkLoadResult(videos)
        } catch {
            guard !Task.isCancelled,
                  !isPlaybackInvalidatedForNavigation,
                  detail.bvid == sourceBVID,
                  detail.pgcSeasonID == seasonID,
                  detail.pgcEpisodeID == sourceEpisodeID
            else { return }

            relatedElapsedMilliseconds = elapsedMilliseconds(since: relatedLoadStartTime)
            relatedState = .failed(error.localizedDescription)
        }
    }
}
