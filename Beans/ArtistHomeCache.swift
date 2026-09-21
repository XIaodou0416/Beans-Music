import Foundation

/// 歌手主页缓存：先显示上次成功内容，再在缓存过期后静默刷新。
final class ArtistHomeCache {
    static let shared = ArtistHomeCache()

    struct Entry: Codable {
        let artist: Artist?
        let songs: [Song]
        let albums: [Album]
        let savedAt: Date
    }

    private let defaults = UserDefaults.standard
    private let storageKey = "beans.artistHomeCache.v1"
    private let lock = NSLock()
    private var entries: [String: Entry]

    /// 歌手主页缓存 30 分钟有效；过期内容仍可立即展示。
    let ttl: TimeInterval = 30 * 60

    private init() {
        entries = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    func cached(for key: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]
    }

    func isFresh(_ entry: Entry, now: Date = Date()) -> Bool {
        now.timeIntervalSince(entry.savedAt) < ttl
    }

    func save(artist: Artist?, songs: [Song], albums: [Album], for key: String) {
        guard !songs.isEmpty || !albums.isEmpty else { return }
        lock.lock()
        entries[key] = Entry(artist: artist, songs: songs, albums: albums, savedAt: Date())
        let snapshot = entries
        lock.unlock()

        DispatchQueue.global(qos: .utility).async { [defaults, storageKey] in
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            defaults.set(data, forKey: storageKey)
        }
    }
}
