import SwiftUI

@MainActor
final class HomeFeedLifecycleActions {
    func start(
        viewModel: HomeViewModel,
        runtimeSettings: HomeRuntimeSettingsStore,
        libraryStore: LibraryStore,
        autoOpenDetail: Bool,
        detailPathIsEmpty: Bool,
        startVideo: VideoItem?,
        onVideoSelect: ((VideoItem) -> Void)?,
        detailOpenActions: HomeFeedDetailOpenActions,
        appendDetailPath: (VideoItem) -> Void
    ) async {
        runtimeSettings.bind(libraryStore)
        await viewModel.loadInitial()
        detailOpenActions.openFirstDetailIfNeeded(
            autoOpenDetail: autoOpenDetail,
            detailPathIsEmpty: detailPathIsEmpty,
            startVideo: startVideo,
            videos: viewModel.videos,
            onVideoSelect: onVideoSelect,
            appendDetailPath: appendDetailPath
        )
    }

    func handleVideosChanged(
        autoOpenDetail: Bool,
        detailPathIsEmpty: Bool,
        startVideo: VideoItem?,
        videos: [VideoItem],
        onVideoSelect: ((VideoItem) -> Void)?,
        detailOpenActions: HomeFeedDetailOpenActions,
        appendDetailPath: @escaping (VideoItem) -> Void
    ) {
        detailOpenActions.openFirstDetailIfNeeded(
            autoOpenDetail: autoOpenDetail,
            detailPathIsEmpty: detailPathIsEmpty,
            startVideo: startVideo,
            videos: videos,
            onVideoSelect: onVideoSelect,
            appendDetailPath: appendDetailPath
        )
    }
}
