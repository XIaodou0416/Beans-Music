import Foundation

extension VideoDetailViewModel {
    func syncFavoriteFolderRenderStore() {
        favoriteFolderRenderStore.update(
            VideoDetailFavoriteFolderRenderSnapshot(viewModel: self)
        )
    }

    func syncDanmakuSettingsRenderStore() {
        danmakuSettingsRenderStore.update(
            VideoDetailDanmakuSettingsRenderSnapshot(viewModel: self)
        )
    }

    func syncNetworkDiagnosticsRenderStore() {
        networkDiagnosticsRenderStore.update(
            VideoDetailNetworkDiagnosticsRenderSnapshot(viewModel: self)
        )
    }

    func syncDescriptionRenderStore() {
        descriptionRenderStore.update(
            VideoDetailDescriptionRenderSnapshot(viewModel: self)
        )
    }

    func syncPlayerIdentityRenderStore() {
        playerIdentityRenderStore.update(
            VideoDetailPlayerIdentityRenderSnapshot(
                playerViewModel: stablePlayerViewModel,
                transitionSnapshot: playbackTransitionSnapshot,
                transitionFallbackCoverURL: playbackTransitionFallbackCoverURL,
                transitionPlayerOpacity: playbackTransitionOpacity
            )
        )
    }
}
