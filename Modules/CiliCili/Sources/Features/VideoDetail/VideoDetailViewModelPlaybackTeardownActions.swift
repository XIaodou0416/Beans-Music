import Foundation

extension VideoDetailViewModel {
    nonisolated static func tearDownPlaybackWarmupTasks(_ state: inout VideoDetailPlaybackWarmupTaskState) {
        state.hlsRenditionPrebuildTask?.cancel()
        state.hlsRenditionPrebuildTask = nil
        state.hlsRenditionPrebuildGeneration += 1
        state.seekWarmupTasks.values.forEach { $0.cancel() }
        state.seekWarmupTasks.removeAll()
        state.seekWarmupTokens.removeAll()
        state.seekWarmupTaskOrder.removeAll()
        state.recentSeekWarmupKeys.removeAll()
        state.recentSeekWarmupKeyOrder.removeAll()
    }

    nonisolated static func tearDownPlaybackRecoveryTasks(_ state: inout VideoDetailPlaybackRecoveryState) {
        state.playbackRecoveryReloadTask?.cancel()
        state.playbackRecoveryReloadTask = nil
        state.playbackRecoveryReloadGeneration += 1
        state.bufferingCDNRefreshTask?.cancel()
        state.bufferingCDNRefreshTask = nil
        state.bufferingCDNRefreshGeneration += 1
    }

    nonisolated static func tearDownPlaybackTransition(_ state: inout VideoDetailPlaybackTransitionState) {
        state.releaseTask?.cancel()
        state.releaseTask = nil
        state.releaseGeneration += 1
        state.playerViewModel = nil
        state.snapshot = nil
        state.fallbackCoverURL = nil
        state.opacity = 0
        Task { @MainActor in
            VideoDetailRotationWindowMask.remove()
        }
    }
}
