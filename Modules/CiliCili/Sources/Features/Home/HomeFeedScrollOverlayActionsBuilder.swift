import Foundation

@MainActor
struct HomeFeedScrollOverlayActionsBuilder {
    let viewModel: HomeViewModel
    let refreshActions: HomeFeedRefreshActions

    var actions: HomeFeedScrollOverlayActions {
        HomeFeedScrollOverlayActions(
            viewModel: viewModel,
            refreshActions: refreshActions
        )
    }
}
