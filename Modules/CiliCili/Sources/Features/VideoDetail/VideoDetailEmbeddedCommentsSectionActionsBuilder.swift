import Foundation

@MainActor
struct VideoDetailEmbeddedCommentsSectionActionsBuilder {
    let viewModel: VideoDetailViewModel
    let onReply: (Comment) -> Void
    let onComposeReply: ((Comment) -> Void)?

    var actions: VideoDetailCommentsSectionActions {
        VideoDetailCommentsSectionActions(
            beginInitialCommentsLoad: { [weak viewModel] in
                viewModel?.beginInitialCommentsLoadIfNeeded()
            },
            selectCommentSort: { [weak viewModel] sort in
                guard let viewModel else { return }
                await viewModel.selectCommentSort(sort)
            },
            retryComments: { [weak viewModel] in
                guard let viewModel else { return }
                await viewModel.retryComments()
            },
            loadMoreComments: { [weak viewModel] in
                guard let viewModel else { return }
                await viewModel.loadMoreComments()
            },
            showReplies: { comment in
                onReply(comment)
            },
            replyToComment: onComposeReply,
            showAllComments: nil
        )
    }
}
