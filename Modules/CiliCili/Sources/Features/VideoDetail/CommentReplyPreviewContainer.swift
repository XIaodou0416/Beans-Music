import SwiftUI

struct CommentReplyPreviewContainer<Content: View>: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let replyCount: Int
    let showsPreview: Bool
    let content: Content

    init(replyCount: Int, showsPreview: Bool, @ViewBuilder content: () -> Content) {
        self.replyCount = replyCount
        self.showsPreview = showsPreview
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsPreview {
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
            }

            CommentInlineActionLabel(
                title: "\(replyCount) 条回复",
                systemImage: "bubble.left.and.bubble.right"
            )
            .foregroundStyle(appTintColor)
        }
        .padding(.horizontal, 0)
        .padding(.vertical, showsPreview ? 5 : 0)
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

struct CommentInlineActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(height: 26, alignment: .leading)
    }
}
