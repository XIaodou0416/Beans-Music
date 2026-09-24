import Foundation

@MainActor
final class HomeFeedPageCoordinator {
    let api: BiliAPIClient
    let libraryStore: LibraryStore
    var freshIndex = 0
    var popularPage = 1

    init(api: BiliAPIClient, libraryStore: LibraryStore) {
        self.api = api
        self.libraryStore = libraryStore
    }

    func usesGuestRecommendDiversity(for mode: HomeFeedMode) -> Bool {
        mode == .recommend && libraryStore.guestModeEnabled
    }

    func usesNativeAppRecommendSource(for mode: HomeFeedMode) -> Bool {
        mode == .recommend && libraryStore.homeRecommendFeedSourcePreference == .app
    }

    func filterFeedRecommendations(_ videos: [VideoItem]) -> [VideoItem] {
        VideoRecommendationFilter.filtered(
            videos,
            configuration: libraryStore.videoRecommendationFilterConfiguration,
            context: .feed
        )
    }
}
