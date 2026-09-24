import SwiftUI

struct CommentsSectionPreviewFooter: View {
    @ObservedObject var store: VideoDetailCommentsRenderStore
    let showAllComments: (() -> Void)?

    var body: some View {
        if store.state.isLoading {
            InlineLoadingStateView(title: "加载评论")
        } else {
            Button {
                showAllComments?()
            } label: {
                Label("查看全部评论", systemImage: "bubble.left.and.bubble.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .commentPlayerGlassRoundedRectangle()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
    }
}
