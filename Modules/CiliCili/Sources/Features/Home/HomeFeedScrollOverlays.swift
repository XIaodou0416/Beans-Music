import SwiftUI

private struct HomeFeedScrollOverlayModifier: ViewModifier {
    @EnvironmentObject private var libraryStore: LibraryStore
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var runtimeSettings: HomeRuntimeSettingsStore
    let viewportState: HomeFeedViewportState
    let actions: HomeFeedScrollOverlayActions

    func body(content: Content) -> some View {
        content
            .overlay {
                HomeFeedFailureOverlay(
                    state: viewModel.state,
                    isEmpty: viewModel.videos.isEmpty,
                    retry: actions.retryInitialLoad
                )
            }
            .homeFeedPullRefreshLayout(
                pullDistance: viewportState.currentPullRefreshDistance,
                triggerDistance: CGFloat(runtimeSettings.homeRefreshTriggerDistance),
                isRefreshing: viewModel.isUserRefreshing,
                isEnabled: libraryStore.usesCustomPullRefresh
            )
    }
}

extension View {
    func homeFeedScrollOverlays(
        viewModel: HomeViewModel,
        runtimeSettings: HomeRuntimeSettingsStore,
        viewportState: HomeFeedViewportState,
        refreshActions: HomeFeedRefreshActions
    ) -> some View {
        modifier(
            HomeFeedScrollOverlayModifier(
                viewModel: viewModel,
                runtimeSettings: runtimeSettings,
                viewportState: viewportState,
                actions: HomeFeedScrollOverlayActionsBuilder(
                    viewModel: viewModel,
                    refreshActions: refreshActions
                )
                .actions
            )
        )
    }
}
