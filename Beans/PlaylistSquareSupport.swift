import Foundation

/// 歌单广场分类。remoteID 由对应平台接口提供，全部分类使用 nil。
struct PlaylistSquareCategory: Identifiable, Hashable {
    let id: String
    let name: String
    let remoteID: Int?

    static let all = PlaylistSquareCategory(id: "all", name: "全部", remoteID: nil)
}

struct PlaylistSquarePage {
    let playlists: [Playlist]
    let hasMore: Bool
    let nextOffset: Int
}

/// 歌单广场缓存：按平台、分类和网易云登录态隔离，避免切换页面重复刷新。
final class PlaylistSquareCache {
    static let shared = PlaylistSquareCache()

    struct Entry: Codable {
        let savedAt: Date
        let playlists: [Playlist]
        let hasMore: Bool
        let nextOffset: Int
    }

    // 分类请求和平台隔离规则变化后，不能继续读取旧版可能混入的分类缓存。
    private let prefix = "beans.playlistSquare.cache.v5."
    private let ttl: TimeInterval = 30 * 60

    private init() {}

    func entry(provider: SearchProvider, category: PlaylistSquareCategory, loggedIn: Bool) -> Entry? {
        let key = cacheKey(provider: provider, category: category, loggedIn: loggedIn)
        guard let data = UserDefaults.standard.data(forKey: key),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else {
            return nil
        }
        return entry
    }

    func isFresh(_ entry: Entry) -> Bool {
        Date().timeIntervalSince(entry.savedAt) < ttl
    }

    func save(
        _ playlists: [Playlist],
        provider: SearchProvider,
        category: PlaylistSquareCategory,
        loggedIn: Bool,
        hasMore: Bool = false,
        nextOffset: Int = 0
    ) {
        let entry = Entry(savedAt: Date(), playlists: playlists, hasMore: hasMore, nextOffset: nextOffset)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey(provider: provider, category: category, loggedIn: loggedIn))
    }

    private func cacheKey(provider: SearchProvider, category: PlaylistSquareCategory, loggedIn: Bool) -> String {
        let safeID = category.id.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        return "\(prefix)\(provider.rawValue).\(loggedIn ? "login" : "guest").\(safeID)"
    }
}
