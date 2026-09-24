import SwiftUI

@MainActor
final class HomeNativeRefreshActionStore {
    var action: RefreshAction?
}

@MainActor
final class HomeFeedModeActions {
    private var switchTask: Task<Void, Never>?

    func switchMode(
        _ mode: HomeFeedMode,
        viewModel: HomeViewModel,
        scrollActions: HomeFeedScrollActions,
        nativeRefreshActionStore: HomeNativeRefreshActionStore
    ) {
        guard viewModel.mode != mode else { return }
        switchTask?.cancel()
        scrollActions.requestScrollToTop()
        let nativeRefreshAction = nativeRefreshActionStore.action
        switchTask = Task { @MainActor in
            await viewModel.switchMode(mode, using: nativeRefreshAction)
        }
    }

    deinit {
        switchTask?.cancel()
    }
}
