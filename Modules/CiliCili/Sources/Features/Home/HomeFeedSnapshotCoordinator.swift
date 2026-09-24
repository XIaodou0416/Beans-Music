import Foundation

@MainActor
struct HomeFeedSnapshotCoordinator {
    let libraryStore: LibraryStore
    let sessionStore: SessionStore

    func load(mode: HomeFeedMode) -> HomeFeedSnapshotRestore? {
        HomeFeedSnapshotCache.load(
            mode: mode,
            guestModeEnabled: libraryStore.guestModeEnabled,
            recommendSource: libraryStore.homeRecommendFeedSourcePreference,
            accountIdentityKey: sessionStore.recommendCacheIdentityKey(
                guestModeEnabled: libraryStore.guestModeEnabled
            )
        )
    }

    func save(videos: [VideoItem], mode: HomeFeedMode, lastSeenMarkerIndex: Int? = nil) {
        HomeFeedSnapshotCache.save(
            videos: videos,
            mode: mode,
            guestModeEnabled: libraryStore.guestModeEnabled,
            recommendSource: libraryStore.homeRecommendFeedSourcePreference,
            accountIdentityKey: sessionStore.recommendCacheIdentityKey(
                guestModeEnabled: libraryStore.guestModeEnabled
            ),
            lastSeenMarkerIndex: lastSeenMarkerIndex
        )
    }
}
