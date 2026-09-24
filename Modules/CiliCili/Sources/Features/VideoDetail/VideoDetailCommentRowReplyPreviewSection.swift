import SwiftUI

struct CommentRowReplyPreviewSection: View {
    let display: VideoDetailCommentDisplayModel
    let isEnabled: Bool
    let showReplies: () -> Void

    var body: some View {
        if display.visibleReplyCount > 0 {
            Button(action: showReplies) {
                CommentReplyPreviewContainer(
                    replyCount: display.visibleReplyCount,
                    showsPreview: !display.replyPreviews.isEmpty
                ) {
                    ForEach(display.replyPreviews) { reply in
                        ReplyPreviewRow(reply: reply)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
        }
    }
}
