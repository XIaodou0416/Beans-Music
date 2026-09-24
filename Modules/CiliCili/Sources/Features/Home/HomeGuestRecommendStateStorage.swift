import Foundation

extension HomeGuestRecommendState {
    static func prunedEntries(now: Date = Date()) -> [ExposureEntry] {
        let loadedEntries = loadEntries()
        let entries = loadedEntries
            .filter { now.timeIntervalSince($0.exposedAt) < maxExposureAge }
        let pruned = Array(entries.suffix(maxExposureCount))
        if pruned.count != loadedEntries.count {
            save(pruned)
        }
        return pruned
    }

    static func loadEntries() -> [ExposureEntry] {
        guard let data = UserDefaults.standard.data(forKey: exposureKey),
              let snapshot = try? JSONDecoder().decode(ExposureSnapshot.self, from: data)
        else { return [] }
        return snapshot.entries
    }

    static func save(_ entries: [ExposureEntry]) {
        let snapshot = ExposureSnapshot(entries: entries)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: exposureKey)
    }
}

nonisolated struct ExposureSnapshot: Codable {
    let entries: [ExposureEntry]
}

nonisolated struct ExposureEntry: Codable {
    let id: String
    let exposedAt: Date
}
