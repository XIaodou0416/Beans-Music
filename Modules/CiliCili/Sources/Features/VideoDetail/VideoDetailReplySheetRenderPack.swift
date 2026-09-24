import Foundation

@MainActor
struct VideoDetailReplySheetRenderPack {
    let store: VideoDetailCommentThreadRenderStore
    let actions: VideoDetailReplySheetActions

    init(
        viewModel: VideoDetailViewModel,
        actions: VideoDetailReplySheetActions
    ) {
        store = viewModel.commentThreadRenderStore
        self.actions = actions
    }
}
