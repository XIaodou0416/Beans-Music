import Foundation

extension VideoDetailViewModel {
    func shouldSkipEmptyCommentPage(
        previousCount: Int,
        previousCursor: String,
        remainingEmptyPageSkips: Int
    ) -> Bool {
        let didAppendComments = comments.count > previousCount
        return !didAppendComments
            && !commentsEnd
            && remainingEmptyPageSkips > 0
            && !commentCursor.isEmpty
            && commentCursor != previousCursor
    }

    func finishCommentPageLoadWithoutSkip(isLoadingMore: Bool, previousCount: Int) {
        let didAppendComments = comments.count > previousCount
        if isLoadingMore, !didAppendComments {
            commentsEnd = true
        }
    }

    func continueCommentPageLoadAfterEmptySkip(isLoadingMore: Bool) {
        if isLoadingMore {
            commentLoadMoreState = .loading
        } else {
            commentState = .loading
        }
    }
}
