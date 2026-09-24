import SwiftUI

@MainActor
struct HomeFeedScreenContentActionsBuilder {
    let viewModel: HomeViewModel
    let detailPath: Binding<NavigationPath>
    let launchConfiguration: HomeFeedLaunchConfiguration
    let preloadContext: HomeFeedPreloadContext
    let actionStore: HomeFeedScreenActionStore

    var actions: HomeFeedContentActions {
        HomeFeedContentActions(
            onVideoSelect: launchConfiguration.onVideoSelect,
            onVideoTap: openVideo,
            onVideoPress: beginPressedPreload,
            onCardAppear: recordExposure,
            onCardDisappear: recordCardDisappearance,
            onLoadMore: loadMoreIfNeeded,
            onRefreshFromLastSeenMarker: refreshFromLastSeenMarker
        )
    }

    private func openVideo(_ video: VideoItem) {
        beginPressedPreload(video)
        viewModel.recordRecommendClick(video)
        actionStore.card.openVideo(
            video,
            onVideoSelect: launchConfiguration.onVideoSelect,
            detailOpenActions: actionStore.detailOpen,
            appendDetailPath: appendDetailPath
        )
    }

    private func beginPressedPreload(_ video: VideoItem) {
        actionStore.card.beginPressedPreload(
            for: video,
            context: preloadContext,
            preloadActions: actionStore.preload
        )
    }

    private func recordExposure(_ video: VideoItem, index: Int) {
        viewModel.recordRecommendExposure(video, index: index)
        viewModel.scheduleImageLookahead(visibleIndex: index)
        actionStore.preload.recordVisibleCard(
            video,
            index: index,
            context: preloadContext
        )
    }

    private func recordCardDisappearance(_ video: VideoItem) {
        actionStore.preload.recordCardDisappearance(video)
    }

    private func loadMoreIfNeeded(_ video: VideoItem) async {
        await actionStore.card.loadMoreIfNeeded(
            current: video,
            viewModel: viewModel
        )
    }

    private func refreshFromLastSeenMarker() async {
        actionStore.scroll.requestProgrammaticRefresh()
    }

    private func appendDetailPath(_ video: VideoItem) {
        detailPath.wrappedValue.append(video)
    }
}
