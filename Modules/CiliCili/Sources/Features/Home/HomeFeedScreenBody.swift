import SwiftUI

struct HomeFeedScreenBody: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var runtimeSettings: HomeRuntimeSettingsStore
    @ObservedObject var libraryStore: LibraryStore
    @Binding var viewportState: HomeFeedViewportState
    @Binding var detailPath: NavigationPath
    let contentActions: HomeFeedContentActions
    let actionStore: HomeFeedScreenActionStore
    let launchConfiguration: HomeFeedLaunchConfiguration

    var body: some View {
        let layout = effectiveLayout
        let layoutMetrics = viewportState.layoutMetrics(for: layout)
        let imagePrefetchProfile = HomeFeedCoverPrefetchProfile.make(
            layout: layout,
            metrics: layoutMetrics,
            displayScale: displayScale
        )

        HomeFeedScrollView(
            viewModel: viewModel,
            runtimeSettings: runtimeSettings,
            viewportState: $viewportState,
            scrollActions: actionStore.scroll,
            nativeRefreshActionStore: actionStore.nativeRefresh,
            refreshActions: actionStore.refresh,
            layout: layout
        ) {
            HomeFeedContentSection(
                metrics: layoutMetrics,
                cells: viewModel.videoCells,
                lastSeenMarkerIndex: viewModel.lastSeenMarkerIndex,
                isLoadingMore: viewModel.state.isLoading && !viewModel.isRefreshing && !viewModel.isUserRefreshing,
                actions: contentActions
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: imagePrefetchProfile.cacheIdentity) {
            viewModel.updateImagePrefetchProfile(imagePrefetchProfile)
        }
        .background(layout.homeFeedBackground)
        .homeFeedScreenLifecycle(
            viewModel: viewModel,
            runtimeSettings: runtimeSettings,
            libraryStore: libraryStore,
            detailPath: $detailPath,
            configuration: lifecycleConfiguration
        )
    }

    private var effectiveLayout: HomeFeedLayout {
        guard dynamicTypeSize.isAccessibilitySize else {
            return runtimeSettings.homeFeedLayout
        }

        switch runtimeSettings.homeFeedLayout {
        case .doubleColumn, .borderedDoubleColumn:
            return .singleColumn
        case .singleColumn, .borderedSingleColumn:
            return runtimeSettings.homeFeedLayout
        }
    }

    private var lifecycleConfiguration: HomeFeedScreenLifecycleConfiguration {
        HomeFeedScreenLifecycleConfiguration(
            launchConfiguration: launchConfiguration,
            lifecycleActions: actionStore.lifecycle,
            detailOpenActions: actionStore.detailOpen
        )
    }
}
