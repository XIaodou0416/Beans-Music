import SwiftUI

struct CommentRepliesSheetContentHost: View {
    let rootComment: Comment
    let store: VideoDetailCommentThreadRenderStore
    let reloadReplies: (Comment) async -> Void
    let loadMoreReplies: (Comment) async -> Void
    let showDialog: (Comment) -> Void
    let actions: CommentRepliesSheetContentHostActions

    init(
        rootComment: Comment,
        store: VideoDetailCommentThreadRenderStore,
        reloadReplies: @escaping (Comment) async -> Void,
        loadMoreReplies: @escaping (Comment) async -> Void,
        showDialog: @escaping (Comment) -> Void,
        loadReplies: @escaping (Comment) async -> Void
    ) {
        self.rootComment = rootComment
        self.store = store
        self.reloadReplies = reloadReplies
        self.loadMoreReplies = loadMoreReplies
        self.showDialog = showDialog
        actions = CommentRepliesSheetContentHostActionsBuilder(
            rootComment: rootComment,
            loadReplies: loadReplies
        )
        .actions
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CommentReplyRootView(comment: rootComment)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                Divider()

                CommentRepliesContent(
                    rootComment: rootComment,
                    store: store,
                    reloadReplies: reloadReplies,
                    loadMoreReplies: loadMoreReplies,
                    showDialog: showDialog
                )
            }
        }
        .defersRemoteImageLoadsDuringFastScroll()
        .hiddenInlineNavigationTitle()
        .nativeTopScrollEdgeEffect()
        .commentSheetLoadLifecycle(load: actions.load)
    }
}
