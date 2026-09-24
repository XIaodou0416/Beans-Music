import Foundation
import OSLog

enum HomeFeedSnapshotCache {
    static let maxAge: TimeInterval = 8 * 60 * 60
    static let directoryURL = URL.cachesDirectory.appending(
        path: "HomeFeedSnapshots",
        directoryHint: .isDirectory
    )
    private static let logger = Logger(subsystem: "cc.bili", category: "HomeRecommend")

    static func load(
        mode: HomeFeedMode,
        guestModeEnabled: Bool,
        recommendSource: HomeRecommendFeedSourcePreference,
        accountIdentityKey: String
    ) -> HomeFeedSnapshotRestore? {
        if let snapshot = loadDiskSnapshot(
            mode: mode,
            guestModeEnabled: guestModeEnabled,
            recommendSource: recommendSource,
            accountIdentityKey: accountIdentityKey
        ) {
            logger.info(
                "snapshot hit=1 storage=disk mode=\(mode.rawValue, privacy: .public) source=\(recommendSource.rawValue, privacy: .public) guest=\(guestModeEnabled, privacy: .public) identity=\(accountIdentityKey, privacy: .public) count=\(snapshot.videos.count, privacy: .public) ageSeconds=\(Int(Date().timeIntervalSince(snapshot.savedAt)), privacy: .public)"
            )
            return HomeFeedSnapshotRestore(
                videos: snapshot.videos.map(\.videoItem),
                lastSeenMarkerIndex: snapshot.lastSeenMarkerIndex
            )
        }
        guard mode != .recommend else {
            logger.info(
                "snapshot hit=0 mode=\(mode.rawValue, privacy: .public) source=\(recommendSource.rawValue, privacy: .public) guest=\(guestModeEnabled, privacy: .public) identity=\(accountIdentityKey, privacy: .public)"
            )
            return nil
        }
        guard let data = UserDefaults.standard.data(forKey: legacyKey(mode: mode, guestModeEnabled: guestModeEnabled)),
              let snapshot = try? JSONDecoder().decode(HomeFeedSnapshot.self, from: data),
              Date().timeIntervalSince(snapshot.savedAt) < maxAge
        else {
            logger.info(
                "snapshot hit=0 mode=\(mode.rawValue, privacy: .public) source=\(recommendSource.rawValue, privacy: .public) guest=\(guestModeEnabled, privacy: .public) identity=\(accountIdentityKey, privacy: .public)"
            )
            return nil
        }
        logger.info(
            "snapshot hit=1 storage=legacy mode=\(mode.rawValue, privacy: .public) source=\(recommendSource.rawValue, privacy: .public) guest=\(guestModeEnabled, privacy: .public) identity=\(accountIdentityKey, privacy: .public) count=\(snapshot.videos.count, privacy: .public) ageSeconds=\(Int(Date().timeIntervalSince(snapshot.savedAt)), privacy: .public)"
        )
        save(
            snapshot: snapshot,
            mode: mode,
            guestModeEnabled: guestModeEnabled,
            recommendSource: recommendSource,
            accountIdentityKey: accountIdentityKey
        )
        UserDefaults.standard.removeObject(forKey: legacyKey(mode: mode, guestModeEnabled: guestModeEnabled))
        return HomeFeedSnapshotRestore(
            videos: snapshot.videos.map(\.videoItem),
            lastSeenMarkerIndex: snapshot.lastSeenMarkerIndex
        )
    }

    static func save(
        videos: [VideoItem],
        mode: HomeFeedMode,
        guestModeEnabled: Bool,
        recommendSource: HomeRecommendFeedSourcePreference,
        accountIdentityKey: String,
        lastSeenMarkerIndex: Int?
    ) {
        let cachedVideos = Array(videos.prefix(48))
        let snapshot = HomeFeedSnapshot(
            savedAt: Date(),
            lastSeenMarkerIndex: normalizedLastSeenMarkerIndex(
                lastSeenMarkerIndex,
                count: cachedVideos.count
            ),
            videos: cachedVideos.map(HomeFeedCachedVideo.init(video:))
        )
        save(
            snapshot: snapshot,
            mode: mode,
            guestModeEnabled: guestModeEnabled,
            recommendSource: recommendSource,
            accountIdentityKey: accountIdentityKey
        )
    }

    private static func normalizedLastSeenMarkerIndex(_ index: Int?, count: Int) -> Int? {
        guard let index, index > 0, index < count else { return nil }
        return index
    }

}
