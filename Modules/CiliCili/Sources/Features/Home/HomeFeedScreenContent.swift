import SwiftUI

struct HomeFeedScreenContent: View {
    @EnvironmentObject var dependencies: AppDependencies
    @StateObject var runtimeSettings = HomeRuntimeSettingsStore()
    @ObservedObject var viewModel: HomeViewModel
    @Binding var detailPath: NavigationPath
    let actionStore: HomeFeedScreenActionStore
    let showsNavigationChrome: Bool
    let launchConfiguration: HomeFeedLaunchConfiguration
    let accountMessageViewModel: AccountMessageCenterViewModel?
    let onOpenAccountMessages: () -> Void
    @State var viewportState = HomeFeedViewportState()

    init(
        viewModel: HomeViewModel,
        detailPath: Binding<NavigationPath>,
        actionStore: HomeFeedScreenActionStore,
        showsNavigationChrome: Bool,
        launchConfiguration: HomeFeedLaunchConfiguration,
        accountMessageViewModel: AccountMessageCenterViewModel?,
        onOpenAccountMessages: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        _detailPath = detailPath
        self.actionStore = actionStore
        self.showsNavigationChrome = showsNavigationChrome
        self.launchConfiguration = launchConfiguration
        self.accountMessageViewModel = accountMessageViewModel
        self.onOpenAccountMessages = onOpenAccountMessages
    }

    var body: some View {
        let renderPack = renderPack

        let content = HomeFeedScreenBody(
            viewModel: viewModel,
            runtimeSettings: runtimeSettings,
            libraryStore: dependencies.libraryStore,
            viewportState: $viewportState,
            detailPath: $detailPath,
            contentActions: renderPack.contentActions,
            actionStore: actionStore,
            launchConfiguration: launchConfiguration
        )
        Group {
            if showsNavigationChrome {
                content
                    .homeFeedNavigationChrome(
                        viewModel: viewModel,
                        modeActions: actionStore.mode,
                        scrollActions: actionStore.scroll,
                        nativeRefreshActionStore: actionStore.nativeRefresh,
                        accountMessageViewModel: accountMessageViewModel,
                        onOpenAccountMessages: onOpenAccountMessages
                    )
            } else {
                content
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            StageOneBaselineMetricsStore.shared.markHomeFirstInteractive()
        }
    }
}
