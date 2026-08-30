import Foundation

/// 收藏管理（红心）：网易云登录后同步到网易云云端；QQ 本地持久化，
/// 登录 QQ 时尽力同步到 QQ 云端（music.srfDissong），失败不影响本地收藏。
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    /// QQ 红心收藏（本地持久化，供音乐库展示）
    @Published private(set) var qqFavoriteSongs: [Song] = []
    /// 网易云红心收藏（本地缓存 + 云端同步）
    @Published private(set) var neteaseFavoriteSongs: [Song] = []

    private let defaults = UserDefaults.standard
    private let neteaseKey = "beans.fav.netease.v1"
    private let qqKey = "beans.fav.qq.v1"

    private init() {
        qqFavoriteSongs = Self.loadSongs(qqKey)
        neteaseFavoriteSongs = Self.loadSongs(neteaseKey)
    }

    /// 该歌曲是否已收藏
    func isLiked(_ song: Song?) -> Bool {
        guard let song else { return false }
        switch song.source {
        case .netease:
            return neteaseFavoriteSongs.contains { $0.id == song.id }
        case .qq:
            guard let mid = song.qqMid else { return false }
            return qqFavoriteSongs.contains { $0.qqMid == mid }
        case .kugou:
            return false
        }
    }

    /// 切换收藏状态；返回是否成功（云端同步失败时网易云会回滚）
    @discardableResult
    func toggle(_ song: Song) async -> Bool {
        switch song.source {
        case .netease:
            let liked = !isLiked(song)
            updateNetease(song, liked: liked)
            do {
                let ok = try await NetEaseAPI.shared.like(id: song.id, liked: liked)
                if !ok {
                    updateNetease(song, liked: !liked)
                    return false
                }
                return true
            } catch {
                updateNetease(song, liked: !liked)
                return false
            }
        case .qq:
            guard let mid = song.qqMid else { return false }
            let liked = !isLiked(song)
            updateQQ(song, liked: liked)
            if QQMusicAuth.shared.isLoggedIn {
                let ok = (try? await QQMusicAPI.shared.like(songmid: mid, liked: liked)) ?? false
                if !ok {
                    // QQ 云端同步失败时保留本地收藏，仅提示，不影响使用
                    return false
                }
            }
            return true
        case .kugou:
            return false
        }
    }

    /// 移除 QQ 收藏（音乐库侧滑删除）
    func removeQQFavorite(_ song: Song) {
        updateQQ(song, liked: false)
    }

    /// 登录 QQ / 微信后从 QQ 音乐云端同步“我的喜欢”。
    /// 只有云端明确返回歌曲时才覆盖本地，避免接口空响应误清空收藏。
    @MainActor
    func syncQQFromCloud() async {
        guard QQMusicAuth.shared.isLoggedIn else { return }
        guard let songs = try? await QQMusicAPI.shared.favoriteSongs(limit: 300), !songs.isEmpty else { return }
        qqFavoriteSongs = songs
        saveSongs(qqFavoriteSongs, key: qqKey)
    }

    private func updateNetease(_ song: Song, liked: Bool) {
        if liked {
            neteaseFavoriteSongs.removeAll { $0.id == song.id }
            neteaseFavoriteSongs.insert(song, at: 0)
        } else {
            neteaseFavoriteSongs.removeAll { $0.id == song.id }
        }
        saveSongs(neteaseFavoriteSongs, key: neteaseKey)
    }

    private func updateQQ(_ song: Song, liked: Bool) {
        if liked {
            qqFavoriteSongs.removeAll { $0.qqMid != nil && $0.qqMid == song.qqMid }
            qqFavoriteSongs.insert(song, at: 0)
        } else {
            qqFavoriteSongs.removeAll { $0.qqMid != nil && $0.qqMid == song.qqMid }
        }
        saveSongs(qqFavoriteSongs, key: qqKey)
    }

    private static func loadSongs(_ key: String) -> [Song] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([Song].self, from: data) else { return [] }
        return saved
    }

    private func saveSongs(_ songs: [Song], key: String) {
        if let data = try? JSONEncoder().encode(songs) {
            defaults.set(data, forKey: key)
        }
    }

    /// 退出网易云登录时清空本地网易云收藏缓存（保留 QQ 收藏）
    func resetNetease() {
        neteaseFavoriteSongs = []
        defaults.removeObject(forKey: neteaseKey)
    }
}
