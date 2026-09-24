import Foundation

struct VideoDetailRelatedTaskState {
    var loadingTask: Task<Void, Never>?
    var refreshTask: Task<Void, Never>?
    var preloadTask: Task<Void, Never>?
    var artworkPrefetchTask: Task<Void, Never>?
    var loadingGeneration = 0
    var refreshGeneration = 0
    var preloadGeneration = 0
    var artworkPrefetchGeneration = 0
}

extension VideoDetailViewModel {
    var relatedLoadingTask: Task<Void, Never>? {
        get { relatedTaskState.loadingTask }
        set { relatedTaskState.loadingTask = newValue }
    }

    var relatedRefreshTask: Task<Void, Never>? {
        get { relatedTaskState.refreshTask }
        set { relatedTaskState.refreshTask = newValue }
    }

    var relatedPreloadTask: Task<Void, Never>? {
        get { relatedTaskState.preloadTask }
        set { relatedTaskState.preloadTask = newValue }
    }

    var relatedArtworkPrefetchTask: Task<Void, Never>? {
        get { relatedTaskState.artworkPrefetchTask }
        set { relatedTaskState.artworkPrefetchTask = newValue }
    }

    var relatedLoadingGeneration: Int {
        get { relatedTaskState.loadingGeneration }
        set { relatedTaskState.loadingGeneration = newValue }
    }

    var relatedRefreshGeneration: Int {
        get { relatedTaskState.refreshGeneration }
        set { relatedTaskState.refreshGeneration = newValue }
    }

    var relatedPreloadGeneration: Int {
        get { relatedTaskState.preloadGeneration }
        set { relatedTaskState.preloadGeneration = newValue }
    }

    var relatedArtworkPrefetchGeneration: Int {
        get { relatedTaskState.artworkPrefetchGeneration }
        set { relatedTaskState.artworkPrefetchGeneration = newValue }
    }
}
