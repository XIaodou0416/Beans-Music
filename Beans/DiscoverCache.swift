import Foundation

/// 主页数据内存缓存：避免每次切回主页 Tab 都重新请求接口。
/// 排行榜 / 歌单广场缓存 1 小时，每日推荐缓存 6 小时；
/// 点右上角刷新会强制重新加载。
final class DiscoverCache {
    static let shared = DiscoverCache()

    /// 单个平台的主页完整数据快照
    struct Snapshot {
        var dailySongs: [Song] = []
        var newAlbums: [Album] = []
        var topArtists: [Artist] = []
        var topLists: [TopList] = []
        var personalized: [Playlist] = []
        var qqTopLists: [QQTopInfo] = []
        var kugouTopLists: [KugouTopInfo] = []
        var savedAt: Date = .distantPast

        var isEmpty: Bool {
            dailySongs.isEmpty && newAlbums.isEmpty && topArtists.isEmpty
                && topLists.isEmpty && personalized.isEmpty
                && qqTopLists.isEmpty && kugouTopLists.isEmpty
        }
    }

    /// 排行榜 / 歌单广场缓存时长（秒）
    let listTTL: TimeInterval = 3600
    /// 每日推荐缓存时长（秒，推荐内容按天更新）
    let dailyTTL: TimeInterval = 6 * 3600
    /// QQ 个性化推荐会随账号听歌行为变化，使用较短缓存避免首页长期展示旧结果。
    let qqRecommendationTTL: TimeInterval = 15 * 60

    private var store: [String: Snapshot] = [:]

    private init() {}

    func cached(for source: SearchProvider) -> Snapshot? {
        store[source.rawValue]
    }

    func save(_ snapshot: Snapshot, for source: SearchProvider) {
        store[source.rawValue] = snapshot
    }

    /// 返回当前进程中已经加载过的主页快照，供启动预加载复用已有封面地址。
    func allSnapshots() -> [Snapshot] {
        Array(store.values)
    }

    /// 缓存是否仍然新鲜：每日推荐单独放宽到 6 小时，其余按 1 小时
    func isFresh(_ snapshot: Snapshot, source: SearchProvider? = nil) -> Bool {
        let age = Date().timeIntervalSince(snapshot.savedAt)
        if source == .qq { return age < qqRecommendationTTL }
        let ttl = snapshot.dailySongs.isEmpty ? listTTL : dailyTTL
        return age < ttl
    }
}
