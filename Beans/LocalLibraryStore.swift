import Foundation

/// 本地歌单（保存在设备本机，不依赖任何平台账号）
struct LocalPlaylist: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var songs: [Song] = []
    var createdAt = Date()

    enum CodingKeys: String, CodingKey { case id, name, songs, createdAt }

    init(id: UUID = UUID(), name: String, songs: [Song] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.songs = songs
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "未命名歌单"
        songs = try c.decodeIfPresent([Song].self, forKey: .songs) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
    }
}

/// 本地音乐库：本地歌单的创建 / 删除 / 收藏歌曲，UserDefaults JSON 持久化（覆盖安装不丢失）
final class LocalLibraryStore: ObservableObject {
    static let shared = LocalLibraryStore()

    @Published var playlists: [LocalPlaylist] {
        didSet { save() }
    }

    private let defaults = UserDefaults.standard
    private let key = "beans.localLibrary.playlists"

    private init() {
        if let data = defaults.data(forKey: key),
           let list = try? JSONDecoder().decode([LocalPlaylist].self, from: data) {
            playlists = list
        } else {
            playlists = []
        }
    }

    @discardableResult
    func createPlaylist(name: String) -> LocalPlaylist {
        let playlist = LocalPlaylist(name: name)
        playlists.append(playlist)
        return playlist
    }

    func deletePlaylist(id: UUID) {
        playlists.removeAll { $0.id == id }
    }

    func renamePlaylist(id: UUID, name: String) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[idx].name = name
    }

    /// 添加歌曲到本地歌单（按 identityKey 去重）
    func addSong(_ song: Song, to id: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        guard !playlists[idx].songs.contains(where: { $0.identityKey == song.identityKey }) else { return }
        playlists[idx].songs.append(song)
    }

    @discardableResult
    func syncSongs(_ songs: [Song], intoPlaylistNamed name: String = "三平台喜欢") -> Int {
        let target: LocalPlaylist
        if let existing = playlists.first(where: { $0.name == name }) {
            target = existing
        } else {
            target = createPlaylist(name: name)
        }
        let before = playlists.first(where: { $0.id == target.id })?.songs.count ?? 0
        for song in songs { addSong(song, to: target.id) }
        return (playlists.first(where: { $0.id == target.id })?.songs.count ?? before) - before
    }

    func removeSong(playlistID: UUID, songIdentity: String) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[idx].songs.removeAll { $0.identityKey == songIdentity }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(playlists) {
            defaults.set(data, forKey: key)
        }
    }
}
