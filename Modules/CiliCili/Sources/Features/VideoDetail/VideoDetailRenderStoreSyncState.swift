import Foundation

struct VideoDetailRenderStoreSyncState {
    var task: Task<Void, Never>?
    var pending: VideoDetailRenderStoreSyncMask = []
    var generation = 0
}

extension VideoDetailViewModel {
    var renderStoreSyncTask: Task<Void, Never>? {
        get { renderStoreSyncState.task }
        set { renderStoreSyncState.task = newValue }
    }

    var pendingRenderStoreSyncs: VideoDetailRenderStoreSyncMask {
        get { renderStoreSyncState.pending }
        set { renderStoreSyncState.pending = newValue }
    }

    var renderStoreSyncGeneration: Int {
        get { renderStoreSyncState.generation }
        set { renderStoreSyncState.generation = newValue }
    }
}
