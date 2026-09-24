import Foundation

extension VideoDetailViewModel {
    func resetCommentStateAfterCancellation(isInitialPage: Bool, wasLoadingMore: Bool) {
        if comments.isEmpty, isInitialPage, !didCompleteInitialCommentLoad {
            commentState = .idle
        } else {
            commentState = .loaded
            if wasLoadingMore {
                commentsEnd = true
            }
        }
        commentLoadMoreState = .idle
    }
}
