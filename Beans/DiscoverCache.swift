import Foundation

/// 主页数据内存缓存：避免每次切回主页 Tab 都重新请求接口。
/// 排行榜 / 歌单广场缓存 1 小时，每日推荐缓存 6 小时；
/// 点右上角刷新或下拉刷新会强制重新加载。
final class DiscoverCache {
    static let shared = DiscoverCache()

    /// 单个平台的主页完整数据快照
    struct Snapshot {
        var dailySongs: [Song] = []
        var topLists: [TopList] = []
        var personalized: [Playlist] = []
        var qqTopLists: [QQTopInfo] = []
        var kugouTopLists: [KugouTopInfo] = []
        var qqNewSongs: [Song] = []
        var qqGuessSongs: [Song] = []
        var qqRadarSongs: [Song] = []
        var qqRecommendationPlaylists: [Playlist] = []
        var qqRadarPage = 1
        var qqRadarHasMore = false
        var qqRecommendationError: String?
        var savedAt: Date = .distantPast

        var isEmpty: Bool {
            dailySongs.isEmpty && topLists.isEmpty && personalized.isEmpty
                && qqTopLists.isEmpty && kugouTopLists.isEmpty
                && qqNewSongs.isEmpty && qqGuessSongs.isEmpty && qqRadarSongs.isEmpty
                && qqRecommendationPlaylists.isEmpty
        }
    }

    /// 排行榜 / 歌单广场缓存时长（秒）
    let listTTL: TimeInterval = 3600
    /// 每日推荐缓存时长（秒，推荐内容按天更新）
    let dailyTTL: TimeInterval = 6 * 3600

    private var store: [String: Snapshot] = [:]

    private init() {}

    func cached(for source: SearchProvider) -> Snapshot? {
        store[source.rawValue]
    }

    func save(_ snapshot: Snapshot, for source: SearchProvider) {
        store[source.rawValue] = snapshot
    }

    /// 缓存是否仍然新鲜：QQ 推荐模块使用服务约定的 60 秒，其余沿用旧策略。
    func isFresh(_ snapshot: Snapshot) -> Bool {
        let age = Date().timeIntervalSince(snapshot.savedAt)
        if !snapshot.qqNewSongs.isEmpty || !snapshot.qqGuessSongs.isEmpty || !snapshot.qqRadarSongs.isEmpty || !snapshot.qqRecommendationPlaylists.isEmpty {
            return age < 60
        }
        let ttl = snapshot.dailySongs.isEmpty ? listTTL : dailyTTL
        return age < ttl
    }
}
