import Foundation

@MainActor
struct VideoDetailEmbeddedCommentsSectionRenderPack {
    let store: VideoDetailCommentsRenderStore
    let actions: VideoDetailCommentsSectionActions

    init(
        viewModel: VideoDetailViewModel,
        onReply: @escaping (Comment) -> Void,
        onComposeReply: ((Comment) -> Void)?
    ) {
        store = viewModel.commentsRenderStore
        actions = VideoDetailEmbeddedCommentsSectionActionsBuilder(
            viewModel: viewModel,
            onReply: onReply,
            onComposeReply: onComposeReply
        )
        .actions
    }
}
