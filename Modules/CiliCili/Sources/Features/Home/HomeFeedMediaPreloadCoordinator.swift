import Foundation

struct HomeFeedImageLookaheadRequest: Equatable {
    let feedRootBVID: String
    let startIndex: Int
    let profile: HomeFeedCoverPrefetchProfile
}

@MainActor
final class HomeFeedMediaPreloadCoordinator {
    let api: BiliAPIClient
    let libraryStore: LibraryStore
    var imagePrefetchTask: Task<Void, Never>?
    var imageLookaheadTask: Task<Void, Never>?
    var playbackPreloadTask: Task<Void, Never>?
    var imagePrefetchProfile: HomeFeedCoverPrefetchProfile?
    var imageLookaheadRequest: HomeFeedImageLookaheadRequest?
    var imageLookaheadFeedRootBVID = ""

    init(api: BiliAPIClient, libraryStore: LibraryStore) {
        self.api = api
        self.libraryStore = libraryStore
    }

    deinit {
        imagePrefetchTask?.cancel()
        imageLookaheadTask?.cancel()
        playbackPreloadTask?.cancel()
    }
}
