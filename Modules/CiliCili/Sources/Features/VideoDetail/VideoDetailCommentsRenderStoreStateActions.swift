import Combine
import Foundation

@MainActor
extension VideoDetailCommentsRenderStore {
    func updateState(_ state: LoadingState) {
        updateSnapshot { $0.state = state }
    }

    func updateLoadMoreState(_ loadMoreState: LoadingState) {
        updateSnapshot { $0.loadMoreState = loadMoreState }
    }

    func updateSelectedSort(_ selectedSort: CommentSort) {
        updateSnapshot { $0.selectedSort = selectedSort }
    }

    func updateDidCompleteInitialLoad(_ didCompleteInitialLoad: Bool) {
        updateSnapshot { $0.didCompleteInitialLoad = didCompleteInitialLoad }
    }

    func updateHasMoreComments(_ hasMoreComments: Bool) {
        updateSnapshot { $0.hasMoreComments = hasMoreComments }
    }
}
