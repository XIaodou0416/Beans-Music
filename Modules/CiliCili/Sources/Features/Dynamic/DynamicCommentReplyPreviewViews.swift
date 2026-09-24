import SwiftUI

struct DynamicReplyPreviewRow: View {
    let reply: Comment

    var body: some View {
        DynamicCommentText(
            content: reply.content,
            font: .caption,
            textColor: .primary,
            emoteSize: 18,
            leadingName: reply.member?.uname ?? "Unknown",
            leadingNameColor: .secondary,
            typographyRole: .metadata
        )
        .lineLimit(2)
    }
}

struct DynamicCommentReplyPreviewContainer<Content: View>: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 11)
        .background(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(appTintColor.opacity(0.42))
                .frame(width: 3)
                .padding(.vertical, 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}
