import Foundation
import QuartzCore

extension VideoDetailViewModel {
    func prepareRelatedNetworkLoad() {
        relatedState = .loading
        lastRelatedLoadTimedOut = false
        relatedLoadStartTime = CACurrentMediaTime()
        relatedElapsedMilliseconds = nil
    }

    func applyRelatedNetworkLoadResult(_ videos: [VideoItem]) {
        applyLoadedRelatedVideos(videos)
        if !related.isEmpty, relatedState.isLoading {
            relatedState = .loaded
        }
        relatedElapsedMilliseconds = elapsedMilliseconds(since: relatedLoadStartTime)
    }
}
