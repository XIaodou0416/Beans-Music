import Foundation

extension VideoDetailViewModel {
    func cancelCommentsLoadingTask(advancesGeneration: Bool = true) {
        commentsLoadingTask?.cancel()
        commentsLoadingTask = nil
        commentsLoadingToken = nil
        if advancesGeneration {
            advanceCommentPageLoadGeneration()
        }
    }

    func clearCommentThreadLoads() {
        replyThreadLoadTokens.removeAll()
        dialogThreadLoadTokens.removeAll()
    }

    func clearCommentThreadCaches(preservingRootID: Int? = nil) {
        if let preservingRootID {
            let preservedReplies = replyThreads[preservingRootID]
            let preservedState = replyThreadStates[preservingRootID]
            let preservedPage = replyThreadPages[preservingRootID]
            let preservedHasMore = replyThreadHasMore[preservingRootID]
            replyThreads = preservedReplies.map { [preservingRootID: $0] } ?? [:]
            replyThreadStates = preservedState.map { [preservingRootID: $0] } ?? [:]
            replyThreadPages = preservedPage.map { [preservingRootID: $0] } ?? [:]
            replyThreadHasMore = preservedHasMore.map { [preservingRootID: $0] } ?? [:]
        } else {
            replyThreads = [:]
            replyThreadStates = [:]
            replyThreadPages = [:]
            replyThreadHasMore = [:]
            commentThreadState.deepLinkAnchor = nil
        }
        dialogThreads = [:]
        dialogThreadStates = [:]
    }

    func resetCommentThreadStateForNewComments() {
        clearCommentThreadLoads()
        guard let anchor = commentThreadState.deepLinkAnchor,
              anchor.contextKey == commentTarget?.contextKey
        else {
            clearCommentThreadCaches()
            return
        }
        clearCommentThreadCaches(preservingRootID: anchor.rootID)
    }

    func clearDeepLinkCommentThreadAnchor() {
        commentThreadState.deepLinkAnchor = nil
    }

    @discardableResult
    func beginReplyThreadLoad(for commentID: Int) -> UUID {
        let token = UUID()
        replyThreadLoadTokens[commentID] = token
        return token
    }

    func isCurrentReplyThreadLoad(
        commentID: Int,
        token: UUID,
        target: VideoDetailCommentTarget
    ) -> Bool {
        replyThreadLoadTokens[commentID] == token
            && (comments.contains { $0.id == commentID }
                || replyThreadStates[commentID] != nil)
            && isCurrentCommentTarget(target)
    }

    func clearReplyThreadLoadIfCurrent(commentID: Int, token: UUID) {
        guard replyThreadLoadTokens[commentID] == token else { return }
        replyThreadLoadTokens[commentID] = nil
    }

    @discardableResult
    func beginDialogThreadLoad(for key: String) -> UUID {
        let token = UUID()
        dialogThreadLoadTokens[key] = token
        return token
    }

    func isCurrentDialogThreadLoad(
        key: String,
        rootID: Int,
        token: UUID,
        target: VideoDetailCommentTarget
    ) -> Bool {
        dialogThreadLoadTokens[key] == token
            && (comments.contains { $0.id == rootID }
                || replyThreadStates[rootID] != nil)
            && isCurrentCommentTarget(target)
    }

    func clearDialogThreadLoadIfCurrent(key: String, token: UUID) {
        guard dialogThreadLoadTokens[key] == token else { return }
        dialogThreadLoadTokens[key] = nil
    }
}
