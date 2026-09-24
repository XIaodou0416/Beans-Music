import Foundation

extension VideoDetailCommentsRenderSnapshot {
    var shouldShowEmptyCommentsState: Bool {
        guard didCompleteInitialLoad,
              comments.isEmpty,
              state == .loaded
        else { return false }
        if let replyCount = detail?.stat?.reply {
            return replyCount == 0 && !hasMoreComments
        }
        return !hasMoreComments
    }

    var shouldShowCommentReloadPrompt: Bool {
        didCompleteInitialLoad
            && comments.isEmpty
            && state == .loaded
            && !shouldShowEmptyCommentsState
    }
}
