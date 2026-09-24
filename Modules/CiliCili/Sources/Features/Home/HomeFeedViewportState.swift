import SwiftUI

struct HomeFeedViewportState {
    private(set) var feedContainerWidth: CGFloat = 0
    private(set) var viewportHeight: CGFloat = 0
    var currentPullRefreshDistance: CGFloat = 0

    mutating func updateFeedContainerWidth(_ width: CGFloat) {
        let roundedWidth = width.rounded(.down)
        guard abs(roundedWidth - feedContainerWidth) > 0.5 else { return }
        feedContainerWidth = roundedWidth
    }

    mutating func updateViewportHeight(_ height: CGFloat) -> CGFloat? {
        let roundedHeight = height.rounded(.down)
        guard roundedHeight > 0, abs(roundedHeight - viewportHeight) > 0.5 else {
            return nil
        }
        viewportHeight = roundedHeight
        return roundedHeight
    }

    func layoutMetrics(for mode: HomeFeedLayout) -> HomeFeedLayoutMetrics {
        HomeFeedLayoutMetrics(
            mode: mode,
            containerWidth: feedContainerWidth
        )
    }
}
