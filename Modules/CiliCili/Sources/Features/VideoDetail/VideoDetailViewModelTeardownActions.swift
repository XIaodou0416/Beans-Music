import Foundation
import Combine

extension VideoDetailViewModel {
    nonisolated static func tearDownBeforeDeinit(
        coreTaskState: inout VideoDetailCoreTaskState,
        playbackWarmupTaskState: inout VideoDetailPlaybackWarmupTaskState,
        playbackRecoveryState: inout VideoDetailPlaybackRecoveryState,
        playbackTransitionState: inout VideoDetailPlaybackTransitionState,
        renderStoreSyncState: inout VideoDetailRenderStoreSyncState,
        playbackStartupWaitState: inout VideoDetailPlaybackStartupWaitState,
        relatedTaskState: inout VideoDetailRelatedTaskState,
        uploaderInteractionLoadState: inout VideoDetailUploaderInteractionLoadState,
        sponsorBlockState: inout VideoDetailSponsorBlockState,
        danmakuLoadingState: inout VideoDetailDanmakuLoadingState
    ) {
        tearDownCoreTasks(&coreTaskState)
        tearDownPlaybackWarmupTasks(&playbackWarmupTaskState)
        tearDownPlaybackRecoveryTasks(&playbackRecoveryState)
        tearDownPlaybackTransition(&playbackTransitionState)
        tearDownRenderStoreSync(&renderStoreSyncState)
        releasePlaybackStartupWaiters(&playbackStartupWaitState)
        tearDownRelatedTasks(&relatedTaskState)
        tearDownUploaderInteractionLoad(&uploaderInteractionLoadState)
        tearDownSponsorBlock(&sponsorBlockState)
        tearDownDanmakuTasks(&danmakuLoadingState)
    }
}
