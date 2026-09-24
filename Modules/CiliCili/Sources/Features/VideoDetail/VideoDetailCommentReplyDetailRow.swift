import SwiftUI

struct CommentReplyDetailRow: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    @Environment(\.videoCommentReplyComposerAction) private var replyToComment
    let item: VideoDetailCommentReplyDisplayItem
    let showDialog: (() -> Void)?

    private var reply: Comment { item.reply }
    private var display: VideoDetailCommentDisplayModel { item.display }

    init(item: VideoDetailCommentReplyDisplayItem, showDialog: (() -> Void)?) {
        self.item = item
        self.showDialog = showDialog
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
                    .frame(minHeight: 36, alignment: .top)

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
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)

                if !display.pictures.isEmpty {
                    CommentImageButton(
                        images: display.pictures,
                        transitionScope: reply.id.description
                    )
                    .padding(.top, 8)
                }

                if let showDialog {
                    Button(action: showDialog) {
                        CommentInlineActionLabel(
                            title: "查看对话",
                            systemImage: "text.bubble"
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(appTintColor)
                    .padding(.top, 8)
                }
                }
            }
        }
        .padding(.vertical, 10)
        .commentCopyContextMenu(text: reply.content?.message, title: "复制回复")
    }

    private var replyAction: (() -> Void)? {
        replyToComment.map { action in { action(reply) } }
    }
}
