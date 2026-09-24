import Combine
import SwiftUI

@MainActor
final class HomeFeedScrollActions: ObservableObject {
    @Published private(set) var topScrollRequestID = 0
    @Published private(set) var programmaticRefreshRequestID = 0

    func requestScrollToTop() {
        topScrollRequestID &+= 1
    }

    func requestProgrammaticRefresh() {
        programmaticRefreshRequestID &+= 1
    }

    func updateFeedContainerWidth(
        _ width: CGFloat,
        state: HomeFeedViewportState
    ) -> HomeFeedViewportState {
        var updatedState = state
        updatedState.updateFeedContainerWidth(width)
        return updatedState
    }

    func updateViewportHeight(
        _ height: CGFloat,
        state: HomeFeedViewportState
    ) -> HomeFeedViewportState {
        var updatedState = state
        _ = updatedState.updateViewportHeight(height)
        return updatedState
    }

}
