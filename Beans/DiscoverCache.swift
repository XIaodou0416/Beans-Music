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
        var savedAt: Date = .distantPast

        var isEmpty: Bool {
            dailySongs.isEmpty && topLists.isEmpty && personalized.isEmpty
                && qqTopLists.isEmpty && kugouTopLists.isEmpty
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

    /// 缓存是否仍然新鲜：每日推荐单独放宽到 6 小时，其余按 1 小时
    func isFresh(_ snapshot: Snapshot) -> Bool {
        let age = Date().timeIntervalSince(snapshot.savedAt)
        let ttl = snapshot.dailySongs.isEmpty ? listTTL : dailyTTL
        return age < ttl
    }
}
