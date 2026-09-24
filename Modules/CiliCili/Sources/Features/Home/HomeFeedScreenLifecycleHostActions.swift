import SwiftUI

@MainActor
struct HomeFeedScreenLifecycleHostActions {
    let viewModel: HomeViewModel
    let runtimeSettings: HomeRuntimeSettingsStore
    let libraryStore: LibraryStore
    let detailPath: Binding<NavigationPath>
    let configuration: HomeFeedScreenLifecycleConfiguration

    func start() async {
        await configuration.lifecycleActions.start(
            viewModel: viewModel,
            runtimeSettings: runtimeSettings,
            libraryStore: libraryStore,
            autoOpenDetail: configuration.launchConfiguration.autoOpenDetail,
            detailPathIsEmpty: detailPath.wrappedValue.isEmpty,
            startVideo: configuration.launchConfiguration.startVideo,
            onVideoSelect: configuration.launchConfiguration.onVideoSelect,
            detailOpenActions: configuration.detailOpenActions,
            appendDetailPath: appendDetailPath
        )
    }

    func handleVideosChanged() {
        configuration.lifecycleActions.handleVideosChanged(
            autoOpenDetail: configuration.launchConfiguration.autoOpenDetail,
            detailPathIsEmpty: detailPath.wrappedValue.isEmpty,
            startVideo: configuration.launchConfiguration.startVideo,
            videos: viewModel.videos,
            onVideoSelect: configuration.launchConfiguration.onVideoSelect,
            detailOpenActions: configuration.detailOpenActions,
            appendDetailPath: appendDetailPath
        )
    }

    private func appendDetailPath(_ video: VideoItem) {
        detailPath.wrappedValue.append(video)
    }
}
