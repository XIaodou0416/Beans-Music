import Foundation

@MainActor
struct VideoDetailSheetActions {
    let replies: VideoDetailReplySheetActions
    let favoriteFolders: VideoDetailFavoriteFolderSheetActions
    let danmaku: VideoDetailDanmakuSheetActions

    init(viewModel: VideoDetailViewModel) {
        replies = VideoDetailReplySheetActions(viewModel: viewModel)
        favoriteFolders = VideoDetailFavoriteFolderSheetActions(viewModel: viewModel)
        danmaku = VideoDetailDanmakuSheetActions(viewModel: viewModel)
    }
}
