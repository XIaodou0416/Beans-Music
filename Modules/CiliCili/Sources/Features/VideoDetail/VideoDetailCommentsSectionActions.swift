struct VideoDetailCommentsSectionActions {
    let beginInitialCommentsLoad: () -> Void
    let selectCommentSort: (CommentSort) async -> Void
    let retryComments: () async -> Void
    let loadMoreComments: () async -> Void
    let showReplies: (Comment) -> Void
    let replyToComment: ((Comment) -> Void)?
    let showAllComments: (() -> Void)?

    @MainActor
    func selectCommentSortAction(_ sort: CommentSort) {
        Task { await selectCommentSort(sort) }
    }

    @MainActor
    func retryCommentsAction() {
        Task { await retryComments() }
    }

    @MainActor
    func loadMoreCommentsAction() {
        Task { await loadMoreComments() }
    }
}
