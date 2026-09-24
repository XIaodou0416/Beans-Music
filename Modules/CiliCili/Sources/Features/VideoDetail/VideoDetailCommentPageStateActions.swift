import Foundation

extension VideoDetailViewModel {
    func beginCommentPageLoad(isLoadingMore: Bool) {
        if isLoadingMore {
            commentLoadMoreState = .loading
        } else {
            commentState = .loading
            commentLoadMoreState = .idle
        }
    }

    func applyLoadedCommentPage(_ page: CommentPage, previousCount: Int, isInitialPage: Bool) {
        let pageComments = comments.isEmpty
            ? (page.topReplies ?? []) + (page.replies ?? [])
            : (page.replies ?? [])
        appendUniqueComments(filteredComments(pageComments))
        commentCursor = page.cursor?.effectiveNext ?? ""
        commentsEnd = page.cursor?.isEnd ?? (comments.count == previousCount && commentCursor.isEmpty)
        if isInitialPage {
            didCompleteInitialCommentLoad = true
        }
        commentState = .loaded
        commentLoadMoreState = .idle
    }
}
