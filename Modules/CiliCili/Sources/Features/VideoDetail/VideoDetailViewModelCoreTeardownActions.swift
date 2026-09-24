import Foundation

extension VideoDetailViewModel {
    nonisolated static func tearDownCoreTasks(_ state: inout VideoDetailCoreTaskState) {
        state.backgroundTasks.values.forEach { $0.cancel() }
        state.backgroundTasks.removeAll()
        state.pageLoadingTask?.cancel()
        state.pageLoadingTask = nil
        state.pageLoadingToken = nil
        state.detailLoadingTask?.cancel()
        state.detailLoadingTask = nil
        state.detailLoadingToken = nil
        state.playVariantSwitchTask?.cancel()
        state.playVariantSwitchTask = nil
        state.commentsLoadingTask?.cancel()
        state.commentsLoadingTask = nil
        state.commentsLoadingToken = nil
        state.startupPlayURLRequestLease?.invalidate()
        state.startupPlayURLTask?.cancel()
        state.startupPlayURLTask = nil
        state.startupPlayURLTaskKey = nil
        state.startupPlayURLRequestLease = nil
        state.startupPlayURLGeneration += 1
        state.cloudHistoryResumeTask?.cancel()
        state.cloudHistoryResumeTask = nil
        state.cloudHistoryResumeTaskAid = nil
    }

    nonisolated static func tearDownRenderStoreSync(_ state: inout VideoDetailRenderStoreSyncState) {
        state.task?.cancel()
        state.task = nil
        state.pending = []
        state.generation += 1
    }

    nonisolated static func releasePlaybackStartupWaiters(_ state: inout VideoDetailPlaybackStartupWaitState) {
        let startupWaiters = state.waiters
        state.waiters.removeAll()
        state.release = nil
        startupWaiters.values.forEach { $0.continuation.resume(returning: nil) }
    }
}
