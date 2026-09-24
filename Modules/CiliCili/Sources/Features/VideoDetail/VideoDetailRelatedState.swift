import Foundation

struct VideoDetailRelatedState {
    var related: [VideoItem] = []
    var loadingState: LoadingState = .idle
    var lastLoadTimedOut = false
}

extension VideoDetailViewModel {
    var related: [VideoItem] {
        get { relatedStateStorage.related }
        set {
            relatedStateStorage.related = newValue
            relatedRenderStore.updateRelated(newValue)
        }
    }

    var relatedState: LoadingState {
        get { relatedStateStorage.loadingState }
        set {
            relatedStateStorage.loadingState = newValue
            relatedRenderStore.updateState(newValue)
        }
    }

    var lastRelatedLoadTimedOut: Bool {
        get { relatedStateStorage.lastLoadTimedOut }
        set {
            relatedStateStorage.lastLoadTimedOut = newValue
            relatedRenderStore.updateTimedOut(newValue)
        }
    }
}
