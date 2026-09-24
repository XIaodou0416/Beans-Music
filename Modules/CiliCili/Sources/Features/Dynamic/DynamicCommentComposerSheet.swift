import SwiftUI

struct DynamicCommentComposerTarget: Identifiable, Equatable, Sendable {
    let rootID: Int?
    let parentID: Int?
    let authorName: String?

    static let dynamic = DynamicCommentComposerTarget(
        rootID: nil,
        parentID: nil,
        authorName: nil
    )

    static func reply(root: Comment, parent: Comment) -> DynamicCommentComposerTarget {
        DynamicCommentComposerTarget(
            rootID: root.rpid,
            parentID: parent.rpid,
            authorName: parent.member?.uname
        )
    }

    var id: String {
        guard let rootID, let parentID else { return "dynamic" }
        return "reply:\(rootID):\(parentID)"
    }

    var title: String {
        authorName == nil ? "发表评论" : "回复评论"
    }

    var prompt: String {
        guard let authorName, !authorName.isEmpty else { return "友善发言，理性讨论" }
        return "回复 @\(authorName)"
    }
}

struct DynamicInlineCommentEmotePicker: View {
    let emotes: [BiliInlineEmote]
    var bottomSafeAreaInset: CGFloat = 0
    let onSelect: (String) -> Void
    var onDelete: (() -> Void)? = nil

    private let columns = Array(repeating: GridItem(.flexible(minimum: 40), spacing: 4), count: 7)

    private var panelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 24,
            bottomLeadingRadius: bottomSafeAreaInset > 0 ? 0 : 24,
            bottomTrailingRadius: bottomSafeAreaInset > 0 ? 0 : 24,
            topTrailingRadius: 24,
            style: .continuous
        )
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                if emotes.isEmpty {
                    ContentUnavailableView("暂无可用表情", systemImage: "face.smiling")
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(emotes, id: \.token) { emote in
                                Button {
                                    onSelect(emote.token)
                                } label: {
                                    CachedRemoteImage(url: emote.displayURL.flatMap(URL.init(string:)), targetPixelSize: 96) { image in
                                        image.resizable().scaledToFit()
                                    } placeholder: {
                                        Image(systemName: "face.smiling")
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 36, height: 36)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(emote.token)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, onDelete == nil ? 8 : 56)
                        .padding(.bottom, 8 + bottomSafeAreaInset)
                    }
                }
            }

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "delete.left")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .padding(.top, 12)
                .padding(.trailing, 26)
                .accessibilityLabel("删除")
                .accessibilityHint("删除光标前的文字或表情")
                .accessibilityIdentifier("dynamic.comment.emotePicker.delete")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(panelShape)
        .background {
            Color.clear
                .biliGlassEffect(
                    interactive: true,
                    in: panelShape
                )
        }
        .accessibilityIdentifier("dynamic.comment.emotePicker")
    }
}
