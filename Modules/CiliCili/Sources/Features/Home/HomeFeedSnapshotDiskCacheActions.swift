import Foundation

extension HomeFeedSnapshotCache {
    static func loadDiskSnapshot(
        mode: HomeFeedMode,
        guestModeEnabled: Bool,
        recommendSource: HomeRecommendFeedSourcePreference,
        accountIdentityKey: String
    ) -> HomeFeedSnapshot? {
        let url = snapshotURL(
            mode: mode,
            guestModeEnabled: guestModeEnabled,
            recommendSource: recommendSource,
            accountIdentityKey: accountIdentityKey
        )
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(HomeFeedSnapshot.self, from: data)
        else { return nil }
        guard Date().timeIntervalSince(snapshot.savedAt) < maxAge else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return snapshot
    }

    static func save(
        snapshot: HomeFeedSnapshot,
        mode: HomeFeedMode,
        guestModeEnabled: Bool,
        recommendSource: HomeRecommendFeedSourcePreference,
        accountIdentityKey: String
    ) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(
            to: snapshotURL(
                mode: mode,
                guestModeEnabled: guestModeEnabled,
                recommendSource: recommendSource,
                accountIdentityKey: accountIdentityKey
            ),
            options: [.atomic]
        )
        pruneExpiredSnapshots()
    }
}
