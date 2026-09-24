import SwiftUI

@MainActor
struct VideoDetailReplySheetHost: View {
    let rootComment: Comment
    @ObservedObject var viewModel: VideoDetailViewModel
    let initialReplyID: Int?
    let renderPack: VideoDetailReplySheetRenderPack

    init(
        rootComment: Comment,
        viewModel: VideoDetailViewModel,
        initialReplyID: Int? = nil,
        actions: VideoDetailReplySheetActions,
        submitReply: @escaping (
            DynamicCommentComposerTarget,
            String,
            [DynamicCommentImage]?
        ) async throws -> Void
    ) {
        self.rootComment = rootComment
        self.viewModel = viewModel
        self.initialReplyID = initialReplyID
        renderPack = VideoDetailReplySheetRenderPack(
            viewModel: viewModel,
            actions: actions
        )
        self.submitReply = submitReply
    }

    let submitReply: (DynamicCommentComposerTarget, String, [DynamicCommentImage]?) async throws -> Void

    var body: some View {
        CommentRepliesSheet(
            rootComment: rootComment,
            store: renderPack.store,
            initialReplyID: initialReplyID,
            loadReplies: renderPack.actions.loadReplies,
            reloadReplies: renderPack.actions.reloadReplies,
            loadMoreReplies: renderPack.actions.loadMoreReplies,
            loadDialog: renderPack.actions.loadDialog,
            reloadDialog: renderPack.actions.reloadDialog,
            submitReply: submitReply
        )
    }
}
