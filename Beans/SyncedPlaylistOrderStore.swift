import Foundation

/// 保存云端歌单的显示顺序。接口刷新后会保留用户自己的排列，新增歌单自动追加到末尾。
final class SyncedPlaylistOrderStore {
    static let shared = SyncedPlaylistOrderStore()

    private let defaults = UserDefaults.standard
    private let key = "beans.syncedPlaylistOrder.v1"
    private var orders: [String: [Int]]

    private init() {
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([String: [Int]].self, from: data) {
            orders = saved
        } else {
            orders = [:]
        }
    }

    func ordered(_ playlists: [Playlist], source: SongSource) -> [Playlist] {
        let sourceKey = source.rawValue
        let savedIDs = orders[sourceKey] ?? []
        let byID = Dictionary(uniqueKeysWithValues: playlists.map { ($0.id, $0) })
        var result: [Playlist] = []
        var used = Set<Int>()

        for id in savedIDs {
            if let playlist = byID[id], used.insert(id).inserted {
                result.append(playlist)
            }
        }
        for playlist in playlists where used.insert(playlist.id).inserted {
            result.append(playlist)
        }
        return result
    }

    func save(_ playlists: [Playlist], source: SongSource) {
        orders[source.rawValue] = playlists.map(\.id)
        guard let data = try? JSONEncoder().encode(orders) else { return }
        defaults.set(data, forKey: key)
    }

    func reset(source: SongSource) {
        orders.removeValue(forKey: source.rawValue)
        guard let data = try? JSONEncoder().encode(orders) else { return }
        defaults.set(data, forKey: key)
    }
}
