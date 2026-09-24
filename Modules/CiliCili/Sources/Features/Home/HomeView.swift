import SwiftUI

struct HomeView: View {
    let launchConfiguration: HomeFeedLaunchConfiguration
    let actionStore: HomeFeedScreenActionStore
    let showsNavigationChrome: Bool
    let accountMessageViewModel: AccountMessageCenterViewModel?
    let onOpenAccountMessages: () -> Void
    @ObservedObject private var viewModel: HomeViewModel
    @Binding var detailPath: NavigationPath

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
        HomeFeedScreenContent(
            viewModel: viewModel,
            detailPath: $detailPath,
            actionStore: actionStore,
            showsNavigationChrome: showsNavigationChrome,
            launchConfiguration: launchConfiguration,
            accountMessageViewModel: accountMessageViewModel,
            onOpenAccountMessages: onOpenAccountMessages
        )
    }
}
