import Foundation

extension VideoDetailViewModel {
    nonisolated static func tearDownRelatedTasks(_ state: inout VideoDetailRelatedTaskState) {
        state.loadingTask?.cancel()
        state.loadingTask = nil
        state.loadingGeneration += 1
        state.refreshTask?.cancel()
        state.refreshTask = nil
        state.refreshGeneration += 1
        state.preloadTask?.cancel()
        state.preloadTask = nil
        state.preloadGeneration += 1
        state.artworkPrefetchTask?.cancel()
        state.artworkPrefetchTask = nil
        state.artworkPrefetchGeneration += 1
    }

    nonisolated static func tearDownUploaderInteractionLoad(_ state: inout VideoDetailUploaderInteractionLoadState) {
        state.task?.cancel()
        state.task = nil
        state.identity = nil
        state.generation += 1
    }

    nonisolated static func tearDownSponsorBlock(_ state: inout VideoDetailSponsorBlockState) {
        state.task?.cancel()
        state.task = nil
        state.generation += 1
    }

    nonisolated static func tearDownDanmakuTasks(_ state: inout VideoDetailDanmakuLoadingState) {
        state.fullLoadTask?.cancel()
        state.fullLoadTask = nil
        state.startupLoadTask?.cancel()
        state.startupLoadTask = nil
        state.startupLoadToken = nil
        state.segmentTasks.values.forEach { $0.cancel() }
        state.segmentTasks.removeAll()
        state.generation += 1
        state.loadingSegments.removeAll()
    }
}
