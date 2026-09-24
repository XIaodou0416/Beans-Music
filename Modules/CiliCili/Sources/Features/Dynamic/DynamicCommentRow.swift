import SwiftUI

struct DynamicCommentRow: View {
    let item: DynamicCommentRowItem
    let showReplies: () -> Void
    let replyToComment: (() -> Void)?

    private var comment: Comment {
        item.comment
    }

    private var display: DynamicCommentRowDisplayModel {
        item.display
    }

    init(
        item: DynamicCommentRowItem,
        showReplies: @escaping () -> Void,
        replyToComment: (() -> Void)? = nil
    ) {
        self.item = item
        self.showReplies = showReplies
        self.replyToComment = replyToComment
    }

    var body: some View {
        sharedCommentLayout
    }

    private var contentReplyAction: () -> Void {
        {
            if let replyToComment {
                replyToComment()
            } else {
                showReplies()
            }
        }
    }

    private var sharedCommentLayout: some View {
        CommentRowLayout(
            fullRowReplyAction: contentReplyAction,
            fullRowReplyAccessibilityLabel: "回复 \(display.authorName) 的评论"
        ) {
            DynamicCommentAvatar(
                urlString: display.avatarURLString,
                owner: display.authorOwner,
                size: 38
            )
        } header: {
            DynamicCommentRowHeader(
                comment: comment,
                display: display
            )
        } bodyContent: {
            DynamicCommentText(
                content: comment.content,
                font: .subheadline,
                textColor: .primary,
                emoteSize: 21,
                lineSpacing: 1,
                typographyRole: .commentBody,
                onNonLinkTap: contentReplyAction
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        } media: {
            DynamicCommentImageGrid(images: display.pictures)
        } reply: {
            if display.visibleReplyCount > 0 {
                Button(action: showReplies) {
                    CommentReplyPreviewContainer(
                        replyCount: display.visibleReplyCount,
                        showsPreview: !display.replyPreviews.isEmpty
                    ) {
                        ForEach(display.replyPreviews) { reply in
                            DynamicReplyPreviewRow(reply: reply)
                        }
                    }
                }
                .buttonStyle(.plain)
                .dynamicCommentHitArea(.control)
            }
        }
    }
}
