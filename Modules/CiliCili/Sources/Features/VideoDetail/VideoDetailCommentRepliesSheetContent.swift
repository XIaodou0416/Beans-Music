import SwiftUI

struct CommentRepliesContent: View {
    let rootComment: Comment
    @ObservedObject var store: VideoDetailCommentThreadRenderStore
    let reloadReplies: (Comment) async -> Void
    let loadMoreReplies: (Comment) async -> Void
    let showDialog: (Comment) -> Void

    var body: some View {
        let snapshot = store.repliesSnapshot(for: rootComment)

        CommentRepliesContentStateView(
            state: CommentRepliesContentState(snapshot: snapshot),
            snapshot: snapshot,
            rootComment: rootComment,
            reloadReplies: reloadReplies,
            loadMoreReplies: loadMoreReplies,
            showDialog: showDialog
        )
    }
}
