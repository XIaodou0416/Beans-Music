import SwiftUI

@MainActor
final class HomeFeedCardActions {
    func openVideo(
        _ video: VideoItem,
        onVideoSelect: ((VideoItem) -> Void)?,
        detailOpenActions: HomeFeedDetailOpenActions,
        appendDetailPath: @escaping (VideoItem) -> Void
    ) {
        detailOpenActions.openDetail(
            for: video,
            onVideoSelect: onVideoSelect,
            appendDetailPath: appendDetailPath
        )
    }

    func beginPressedPreload(
        for video: VideoItem,
        context: HomeFeedPreloadContext,
        preloadActions: HomeFeedPreloadActions
    ) {
        preloadActions.beginPressedPreloadIfNeeded(
            for: video,
            context: context
        )
    }

    func loadMoreIfNeeded(
        current video: VideoItem,
        viewModel: HomeViewModel
    ) async {
        await viewModel.loadMoreIfNeeded(current: video)
    }
}
