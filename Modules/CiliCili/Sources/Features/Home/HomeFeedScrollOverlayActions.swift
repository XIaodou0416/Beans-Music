import Foundation

@MainActor
struct HomeFeedScrollOverlayActions {
    let viewModel: HomeViewModel
    let refreshActions: HomeFeedRefreshActions

    func retryInitialLoad() {
        refreshActions.retry {
            await viewModel.refresh()
        }
    }
}
