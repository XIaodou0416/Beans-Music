import Foundation

struct VideoDetailUploaderInteractionLoadState {
    var task: Task<Void, Never>?
    var identity: String?
    var generation = 0
}

extension VideoDetailViewModel {
    var uploaderInteractionTask: Task<Void, Never>? {
        get { uploaderInteractionLoadState.task }
        set { uploaderInteractionLoadState.task = newValue }
    }

    var uploaderInteractionLoadIdentity: String? {
        get { uploaderInteractionLoadState.identity }
        set { uploaderInteractionLoadState.identity = newValue }
    }

    var uploaderInteractionLoadGeneration: Int {
        get { uploaderInteractionLoadState.generation }
        set { uploaderInteractionLoadState.generation = newValue }
    }
}
