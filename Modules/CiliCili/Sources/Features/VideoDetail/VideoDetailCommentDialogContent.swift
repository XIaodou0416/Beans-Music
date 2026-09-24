import SwiftUI

struct CommentDialogContent: View {
    let rootComment: Comment
    let focusReply: Comment
    @ObservedObject var store: VideoDetailCommentThreadRenderStore
    let reloadDialog: (Comment, Comment) async -> Void

    var body: some View {
        let snapshot = store.dialogSnapshot(for: rootComment, reply: focusReply)

        CommentDialogStateContent(
            snapshot: snapshot,
            focusReplyID: focusReply.id,
            reloadDialog: {
                await reloadDialog(rootComment, focusReply)
            }
        )
    }
}
