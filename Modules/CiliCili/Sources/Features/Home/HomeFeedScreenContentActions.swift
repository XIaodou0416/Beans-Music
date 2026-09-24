import SwiftUI

extension HomeFeedScreenContent {
    var renderPack: HomeFeedScreenRenderPack {
        let preloadContext = preloadContext
        return HomeFeedScreenRenderPack(
            preloadContext: preloadContext,
            contentActions: makeContentActions(preloadContext: preloadContext)
        )
    }

    private func makeContentActions(preloadContext: HomeFeedPreloadContext) -> HomeFeedContentActions {
        HomeFeedScreenContentActionsBuilder(
            viewModel: viewModel,
            detailPath: $detailPath,
            launchConfiguration: launchConfiguration,
            preloadContext: preloadContext,
            actionStore: actionStore
        )
        .actions
    }
}
