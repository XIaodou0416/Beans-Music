import Foundation

/// 专辑详情页的“该歌手的其他专辑”缓存。
/// 进入页面时先展示上次成功结果，再在网络可用时静默更新，避免重复打开反复空白刷新。
final class RelatedAlbumsCache {
    static let shared = RelatedAlbumsCache()

    struct Entry: Codable {
        let albums: [Album]
        let savedAt: Date
    }

    private let defaults = UserDefaults.standard
    private let storageKey = "beans.relatedAlbumsCache.v1"
    private let lock = NSLock()
    private let persistenceQueue = DispatchQueue(
        label: "Beans.RelatedAlbumsCache.persistence",
        qos: .utility
    )
    private var entries: [String: Entry]

    /// 缓存 30 分钟有效；过期内容仍可先展示，随后静默刷新。
    let ttl: TimeInterval = 30 * 60

    private init() {
        entries = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    func cachedAlbums(for key: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]
    }

    /// 已缓存的“该歌手的其他专辑”，供启动预加载和缓存管理复用。
    func allCachedAlbums() -> [Album] {
        lock.lock()
        defer { lock.unlock() }
        return entries.values.flatMap(\.albums)
    }

    func clearAll() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
        defaults.removeObject(forKey: storageKey)
    }

    func save(_ albums: [Album], for key: String) {
        guard !albums.isEmpty else { return }
        lock.lock()
        entries[key] = Entry(albums: albums, savedAt: Date())
        let snapshot = entries
        lock.unlock()

        persistenceQueue.async { [defaults, storageKey] in
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            defaults.set(data, forKey: storageKey)
        }
    }

    func isFresh(_ entry: Entry, now: Date = Date()) -> Bool {
        now.timeIntervalSince(entry.savedAt) < ttl
    }
}
