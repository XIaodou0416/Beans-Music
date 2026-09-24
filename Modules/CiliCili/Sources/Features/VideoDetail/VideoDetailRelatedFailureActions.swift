import Foundation

extension VideoDetailViewModel {
    func handleRelatedLoadTimeout(bvid: String) async {
        guard !Task.isCancelled, detail.bvid == bvid else { return }
        if !related.isEmpty {
            relatedState = .loaded
            relatedElapsedMilliseconds = elapsedMilliseconds(since: relatedLoadStartTime)
            return
        }
        if await applyRelatedFallbackIfAvailable(reason: "相关推荐加载超时", bvid: bvid) {
            guard detail.bvid == bvid else { return }
            relatedElapsedMilliseconds = elapsedMilliseconds(since: relatedLoadStartTime)
            return
        }
        guard detail.bvid == bvid else { return }
        lastRelatedLoadTimedOut = true
        relatedElapsedMilliseconds = elapsedMilliseconds(since: relatedLoadStartTime)
        relatedState = .failed("相关推荐加载超时")
    }

    func handleRelatedLoadFailure(_ error: Error, bvid: String) async {
        guard !Task.isCancelled, detail.bvid == bvid else { return }
        if !related.isEmpty {
            relatedState = .loaded
            relatedElapsedMilliseconds = elapsedMilliseconds(since: relatedLoadStartTime)
            return
        }
        if await applyRelatedFallbackIfAvailable(reason: error.localizedDescription, bvid: bvid) {
            guard detail.bvid == bvid else { return }
            relatedElapsedMilliseconds = elapsedMilliseconds(since: relatedLoadStartTime)
            return
        }
        guard detail.bvid == bvid else { return }
        relatedElapsedMilliseconds = elapsedMilliseconds(since: relatedLoadStartTime)
        relatedState = .failed(error.localizedDescription)
    }
}
