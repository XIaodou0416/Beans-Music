import Foundation

enum HomeGuestRecommendState {
    static let exposureKey = "cc.bili.home.guestRecommend.exposure.v1"
    private static let cursorKey = "cc.bili.home.guestRecommend.cursor.v1"
    static let maxExposureAge: TimeInterval = 24 * 60 * 60
    static let maxExposureCount = 900

    static func recentExposureIDs(now: Date = Date()) -> Set<String> {
        Set(prunedEntries(now: now).map(\.id))
    }

    static func recordExposure(_ videos: [VideoItem], now: Date = Date()) {
        let ids = videos
            .map(\.id)
            .filter { !$0.isEmpty }
        guard !ids.isEmpty else { return }

        let newIDSet = Set(ids)
        var entries = prunedEntries(now: now)
            .filter { !newIDSet.contains($0.id) }
        entries.append(contentsOf: ids.map { ExposureEntry(id: $0, exposedAt: now) })
        entries = Array(entries.suffix(maxExposureCount))
        save(entries)
    }

    static func nextFreshIndex() -> Int {
        max(0, UserDefaults.standard.object(forKey: cursorKey) as? Int ?? 0)
    }

    static func storeNextFreshIndex(after currentIndex: Int) {
        let nextIndex = max(nextFreshIndex(), currentIndex + 1)
        UserDefaults.standard.set(nextIndex, forKey: cursorKey)
    }
}
