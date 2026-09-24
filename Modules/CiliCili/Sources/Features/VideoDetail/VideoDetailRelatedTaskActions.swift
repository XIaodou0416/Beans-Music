import Foundation

extension VideoDetailViewModel {
    func cancelRelatedLoadingTask(advancesGeneration: Bool = true) {
        relatedLoadingTask?.cancel()
        relatedLoadingTask = nil
        if advancesGeneration {
            advanceRelatedLoadingGeneration()
        }
    }

    func cancelRelatedRefreshTask(advancesGeneration: Bool = true) {
        relatedRefreshTask?.cancel()
        relatedRefreshTask = nil
        if advancesGeneration {
            advanceRelatedRefreshGeneration()
        }
    }

    func cancelRelatedPreloadTask(advancesGeneration: Bool = true) {
        relatedPreloadTask?.cancel()
        relatedPreloadTask = nil
        if advancesGeneration {
            advanceRelatedPreloadGeneration()
        }
    }

    func cancelRelatedArtworkPrefetchTask(advancesGeneration: Bool = true) {
        relatedArtworkPrefetchTask?.cancel()
        relatedArtworkPrefetchTask = nil
        if advancesGeneration {
            advanceRelatedArtworkPrefetchGeneration()
        }
    }

    @discardableResult
    func advanceRelatedLoadingGeneration() -> Int {
        relatedLoadingGeneration += 1
        return relatedLoadingGeneration
    }

    @discardableResult
    func advanceRelatedRefreshGeneration() -> Int {
        relatedRefreshGeneration += 1
        return relatedRefreshGeneration
    }

    @discardableResult
    func advanceRelatedPreloadGeneration() -> Int {
        relatedPreloadGeneration += 1
        return relatedPreloadGeneration
    }

    @discardableResult
    func advanceRelatedArtworkPrefetchGeneration() -> Int {
        relatedArtworkPrefetchGeneration += 1
        return relatedArtworkPrefetchGeneration
    }

    func clearRelatedLoadingTaskIfCurrent(generation: Int) {
        guard relatedLoadingGeneration == generation else { return }
        relatedLoadingTask = nil
    }

    func clearRelatedRefreshTaskIfCurrent(generation: Int) {
        guard relatedRefreshGeneration == generation else { return }
        relatedRefreshTask = nil
    }

    func clearRelatedPreloadTaskIfCurrent(generation: Int) {
        guard relatedPreloadGeneration == generation else { return }
        relatedPreloadTask = nil
    }

    func clearRelatedArtworkPrefetchTaskIfCurrent(generation: Int) {
        guard relatedArtworkPrefetchGeneration == generation else { return }
        relatedArtworkPrefetchTask = nil
    }
}
