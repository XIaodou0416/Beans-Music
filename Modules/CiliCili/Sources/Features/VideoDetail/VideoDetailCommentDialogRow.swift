import SwiftUI

struct CommentDialogRow: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    @Environment(\.videoCommentReplyComposerAction) private var replyToComment
    let item: VideoDetailCommentDialogDisplayItem
    let isFocused: Bool

    private var reply: Comment { item.reply }
    private var display: VideoDetailCommentDisplayModel { item.display }

    init(item: VideoDetailCommentDialogDisplayItem, isFocused: Bool) {
        self.item = item
        self.isFocused = isFocused
    }

    var body: some View {
        DynamicCommentFullRowReplyTarget(
            action: replyAction,
            accessibilityLabel: "回复 \(display.authorName) 的评论"
        ) {
            HStack(alignment: .top, spacing: 10) {
                CommentAvatar(
                    urlString: display.avatarURLString,
                    owner: display.authorOwner,
                    size: 36
                )

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            CommentAuthorIdentity(name: display.authorName, owner: display.authorOwner)
                                .foregroundStyle(.primary)

                            Spacer(minLength: 0)

                            if !display.timeText.isEmpty {
                                Text(display.timeText)
                                    .appTypography(.metadata, fallback: .caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(minHeight: 36, alignment: .topLeading)

                        Spacer(minLength: 8)
                        CommentLikeButton(comment: reply)
                    }

                    BiliEmoteText(
                        content: reply.content,
                        font: .subheadline,
                        textColor: .primary,
                        emoteSize: 22,
                        typographyRole: .commentBody,
                        onNonLinkTap: replyAction
                    )
                    .padding(.top, 4)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                    if !display.pictures.isEmpty {
                        DynamicCommentImageGrid(images: display.pictures)
                            .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
        }
        .padding(.vertical, 10)
        .background(isFocused ? appTintColor.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .commentCopyContextMenu(text: reply.content?.message, title: "复制回复")
    }

    private var replyAction: (() -> Void)? {
        replyToComment.map { action in { action(reply) } }
    }
}
