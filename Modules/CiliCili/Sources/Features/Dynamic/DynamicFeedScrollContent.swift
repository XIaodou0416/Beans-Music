import SwiftUI

struct DynamicFeedScrollContent: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let api: BiliAPIClient
    @ObservedObject var viewModel: DynamicViewModel
    let isLoggedIn: Bool
    let contentWidth: CGFloat
    let pullRefreshTriggerDistance: CGFloat
    @State private var pullRefreshDistance: CGFloat = 0
    @State private var pullRefreshActions = HomeFeedRefreshActions()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                DynamicFeedBodyContent(
                    api: api,
                    viewModel: viewModel,
                    isLoggedIn: isLoggedIn,
                    contentWidth: contentWidth
                )
                .frame(width: contentWidth, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
        .rootFloatingTabBarContentPadding()
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollBounceBehavior(.always, axes: .vertical)
        .defersRemoteImageLoadsDuringFastScroll()
        .background(Color(.systemBackground))
        .nativeTopScrollEdgeEffect()
        .customPullRefreshTracking(
            isEnabled: libraryStore.usesCustomPullRefresh,
            onChange: handlePullRefreshChange
        )
        .task(id: isLoggedIn) {
            await viewModel.loadInitial()
        }
        .nativePullRefresh(
            isEnabled: libraryStore.usesNativePullRefresh,
            action: refreshFromNativePull
        )
        .homeFeedPullRefreshLayout(
            pullDistance: pullRefreshDistance,
            triggerDistance: pullRefreshTriggerDistance,
            isRefreshing: viewModel.isRefreshing,
            isEnabled: libraryStore.usesCustomPullRefresh
        )
        .overlay {
            DynamicFeedErrorOverlay(viewModel: viewModel, isLoggedIn: isLoggedIn)
        }
    }

    private func handlePullRefreshChange(
        pullDistance: CGFloat,
        isUserInteracting: Bool
    ) {
        pullRefreshDistance = pullDistance
        guard isLoggedIn, libraryStore.usesCustomPullRefresh else { return }
        pullRefreshActions.handleConfiguredPullRefresh(
            pullDistance: pullDistance,
            triggerDistance: pullRefreshTriggerDistance,
            isUserInteracting: isUserInteracting,
            isRefreshing: viewModel.isRefreshing
        ) {
            await viewModel.refresh()
            return viewModel.state == .loaded
        }
    }

    private func refreshFromNativePull() async {
        guard isLoggedIn else { return }
        await viewModel.refresh()
    }

}

private struct DynamicFeedBodyContent: View {
    let api: BiliAPIClient
    @ObservedObject var viewModel: DynamicViewModel
    let isLoggedIn: Bool
    let contentWidth: CGFloat

    var body: some View {
        LazyVStack(spacing: 0) {
            FollowedLiveStrip(
                items: viewModel.topUploaderStripItems,
                isLoading: isLoggedIn && viewModel.isTopUploaderStripLoading
            )

            if !isLoggedIn {
                DynamicLoginEmptyState()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 110)
            } else if viewModel.items.isEmpty && viewModel.state.isLoading {
                DynamicFeedSkeletonList()
            } else if viewModel.items.isEmpty {
                DynamicFeedEmptyState()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 110)
            } else {
                DynamicFeedItemsList(
                    api: api,
                    viewModel: viewModel,
                    items: viewModel.items,
                    contentWidth: contentWidth
                )

                DynamicFeedFooter(viewModel: viewModel)
                    .padding(.top, 6)
            }
        }
    }
}
