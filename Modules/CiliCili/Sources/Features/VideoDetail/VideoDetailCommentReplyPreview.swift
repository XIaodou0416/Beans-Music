import SwiftUI

struct ReplyPreviewRow: View {
    let reply: Comment

    var body: some View {
        BiliEmoteText(
            content: reply.content,
            font: .caption,
            textColor: .primary,
            emoteSize: 18,
            leadingName: reply.member?.uname ?? "Unknown",
            leadingNameColor: .secondary,
            showsLinkButtons: false,
            typographyRole: .metadata
        )
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .commentCopyContextMenu(text: reply.content?.message, title: "复制回复")
    }
}
