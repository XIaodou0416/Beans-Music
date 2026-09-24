import SwiftUI

private struct VideoCommentReplyComposerActionKey: EnvironmentKey {
    static let defaultValue: ((Comment) -> Void)? = nil
}

extension EnvironmentValues {
    var videoCommentReplyComposerAction: ((Comment) -> Void)? {
        get { self[VideoCommentReplyComposerActionKey.self] }
        set { self[VideoCommentReplyComposerActionKey.self] = newValue }
    }
}

struct CommentRowLayout<Avatar: View, Header: View, BodyContent: View, Media: View, Reply: View>: View {
    let avatar: Avatar
    let header: Header
    let bodyContent: BodyContent
    let media: Media
    let reply: Reply
    let fullRowReplyAction: (() -> Void)?
    let fullRowReplyAccessibilityLabel: String

    init(
        fullRowReplyAction: (() -> Void)? = nil,
        fullRowReplyAccessibilityLabel: String = "回复评论",
        @ViewBuilder avatar: () -> Avatar,
        @ViewBuilder header: () -> Header,
        @ViewBuilder bodyContent: () -> BodyContent,
        @ViewBuilder media: () -> Media,
        @ViewBuilder reply: () -> Reply
    ) {
        self.avatar = avatar()
        self.header = header()
        self.bodyContent = bodyContent()
        self.media = media()
        self.reply = reply()
        self.fullRowReplyAction = fullRowReplyAction
        self.fullRowReplyAccessibilityLabel = fullRowReplyAccessibilityLabel
    }

    var body: some View {
        DynamicCommentFullRowReplyTarget(
            action: fullRowReplyAction,
            accessibilityLabel: fullRowReplyAccessibilityLabel
        ) {
            HStack(alignment: .top, spacing: 10) {
                avatar

                VStack(alignment: .leading, spacing: 0) {
                    header
                    bodyContent.padding(.top, 4)
                    media.padding(.top, 8)
                    reply.padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
            .padding(.vertical, 10)
        }
    }
}

struct DynamicCommentFullRowReplyTarget<Content: View>: View {
    let action: (() -> Void)?
    let accessibilityLabel: String
    @ViewBuilder let content: () -> Content

    init(
        action: (() -> Void)?,
        accessibilityLabel: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.action = action
        self.accessibilityLabel = accessibilityLabel
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let action {
                Button(action: action) {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint("轻点以回复")
                .accessibilityIdentifier("dynamic.comment.reply.fullRow")
            }

            content()
                .zIndex(1)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: action == nil ? nil : 44,
            alignment: .topLeading
        )
        .dynamicCommentHitArea(.reply)
    }
}
