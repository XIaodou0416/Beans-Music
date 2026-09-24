import SwiftUI

struct CommentRepliesLoadedList: View {
    let snapshot: VideoDetailCommentThreadRepliesSnapshot
    let rootComment: Comment
    let loadMoreReplies: (Comment) async -> Void
    let showDialog: (Comment) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(snapshot.replyDisplays) { replyDisplay in
                CommentReplyDetailRow(
                    item: replyDisplay,
                    showDialog: replyDisplay.canShowDialog ? {
                        showDialog(replyDisplay.reply)
                    } : nil
                )
                .padding(.horizontal, 16)

                Divider()
            }

            CommentRepliesFooter(
                snapshot: snapshot,
                rootComment: rootComment,
                loadMoreReplies: loadMoreReplies
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}
