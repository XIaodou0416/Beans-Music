import SwiftUI

struct CommentRepliesContentStateView: View {
    let state: CommentRepliesContentState
    let snapshot: VideoDetailCommentThreadRepliesSnapshot
    let rootComment: Comment
    let loadMoreReplies: (Comment) async -> Void
    let showDialog: (Comment) -> Void
    let actions: CommentRepliesContentStateActions

    init(
        state: CommentRepliesContentState,
        snapshot: VideoDetailCommentThreadRepliesSnapshot,
        rootComment: Comment,
        reloadReplies: @escaping (Comment) async -> Void,
        loadMoreReplies: @escaping (Comment) async -> Void,
        showDialog: @escaping (Comment) -> Void
    ) {
        self.state = state
        self.snapshot = snapshot
        self.rootComment = rootComment
        self.loadMoreReplies = loadMoreReplies
        self.showDialog = showDialog
        actions = CommentRepliesContentStateActions(
            rootComment: rootComment,
            reloadReplies: reloadReplies
        )
    }

    var body: some View {
        switch state {
        case .loading:
            CommentLoadingSkeletonList(count: 3)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        case .failed(let message):
            CommentErrorView(message: message, retry: actions.reloadRepliesAction)
            .padding(16)
        case .empty:
            EmptyStateView(
                title: "暂无回复",
                systemImage: "bubble.left.and.bubble.right",
                message: "这条评论还没有可展示的回复。"
            )
            .padding(16)
        case .loaded:
            CommentRepliesLoadedList(
                snapshot: snapshot,
                rootComment: rootComment,
                loadMoreReplies: loadMoreReplies,
                showDialog: showDialog
            )
        }
    }
}
