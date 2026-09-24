import SwiftUI

struct VideoDetailEmbeddedCommentsSection: View {
    let viewModel: VideoDetailViewModel
    let renderPack: VideoDetailEmbeddedCommentsSectionRenderPack

    init(
        viewModel: VideoDetailViewModel,
        onReply: @escaping (Comment) -> Void,
        onComposeReply: ((Comment) -> Void)?
    ) {
        self.viewModel = viewModel
        renderPack = VideoDetailEmbeddedCommentsSectionRenderPack(
            viewModel: viewModel,
            onReply: onReply,
            onComposeReply: onComposeReply
        )
    }

    var body: some View {
        CommentsSectionView(
            store: renderPack.store,
            style: .plain,
            maxVisibleComments: nil,
            autoLoads: true,
            actions: renderPack.actions,
            verticalPadding: 0
        )
        .environment(\.commentContentOwnerMID, viewModel.detail.owner?.mid)
    }
}
