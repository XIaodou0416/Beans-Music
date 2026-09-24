import Foundation

@MainActor
struct VideoDetailSummaryCardRenderPack {
    let descriptionStore: VideoDetailDescriptionRenderStore
    let interactionStore: VideoDetailInteractionRenderStore
    let placeholderStore: VideoDetailPlayerPlaceholderRenderStore
    let actions: VideoDetailSummaryCardActions

    init(
        viewModel: VideoDetailViewModel,
        showFavoriteFolders: @escaping () -> Void
    ) {
        descriptionStore = viewModel.descriptionRenderStore
        interactionStore = viewModel.interactionRenderStore
        placeholderStore = viewModel.playbackRenderStore.placeholderStore
        actions = VideoDetailSummaryCardActions(
            viewModel: viewModel,
            showFavoriteFolders: showFavoriteFolders
        )
    }
}
