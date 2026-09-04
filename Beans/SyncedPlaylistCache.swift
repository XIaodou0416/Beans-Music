import Foundation

/// 持久化缓存云端歌单列表和歌单歌曲。
/// 网络请求失败或切回音乐库时，先展示上次成功结果，再在后台刷新。
final class SyncedPlaylistCache {
    static let shared = SyncedPlaylistCache()

    struct PlaylistEntry: Codable {
        let playlists: [Playlist]
        let savedAt: Date
    }

    struct SongEntry: Codable {
        let songs: [Song]
        let savedAt: Date
    }

    private let defaults = UserDefaults.standard
    private let playlistsKey = "beans.syncedPlaylistCache.playlists.v1"
    private let songsKey = "beans.syncedPlaylistCache.songs.v1"
    private let lock = NSLock()
    private let persistenceQueue = DispatchQueue(label: "Beans.SyncedPlaylistCache.persistence", qos: .utility)
    private var playlistEntries: [String: PlaylistEntry]
    private var songEntries: [String: SongEntry]

    /// 歌单列表缓存 15 分钟，歌曲详情缓存 30 分钟。
    let playlistTTL: TimeInterval = 15 * 60
    let songTTL: TimeInterval = 30 * 60

    private init() {
        playlistEntries = defaults.data(forKey: playlistsKey)
            .flatMap { try? JSONDecoder().decode([String: PlaylistEntry].self, from: $0) } ?? [:]
        songEntries = defaults.data(forKey: songsKey)
            .flatMap { try? JSONDecoder().decode([String: SongEntry].self, from: $0) } ?? [:]
    }

    func cachedPlaylists(source: SongSource, accountID: String) -> PlaylistEntry? {
        lock.lock()
        defer { lock.unlock() }
        return playlistEntries[cacheKey(source: source, accountID: accountID)]
    }

    func savePlaylists(_ playlists: [Playlist], source: SongSource, accountID: String) {
        guard !playlists.isEmpty else { return }
        lock.lock()
        playlistEntries[cacheKey(source: source, accountID: accountID)] = PlaylistEntry(
            playlists: playlists,
            savedAt: Date()
        )
        let snapshot = playlistEntries
        lock.unlock()
        persistAsync(snapshot, key: playlistsKey)
    }

    func cachedSongs(playlist: Playlist, accountID: String) -> SongEntry? {
        lock.lock()
        defer { lock.unlock() }
        return songEntries[cacheKey(source: playlist.source, accountID: "\(accountID)|\(playlist.id)")]
    }

    func saveSongs(_ songs: [Song], playlist: Playlist, accountID: String) {
        guard !songs.isEmpty else { return }
        lock.lock()
        songEntries[cacheKey(source: playlist.source, accountID: "\(accountID)|\(playlist.id)")] = SongEntry(
            songs: songs,
            savedAt: Date()
        )
        let snapshot = songEntries
        lock.unlock()
        persistAsync(snapshot, key: songsKey)
    }

    func isFresh(_ entry: PlaylistEntry, now: Date = Date()) -> Bool {
        now.timeIntervalSince(entry.savedAt) < playlistTTL
    }

    func isFresh(_ entry: SongEntry, now: Date = Date()) -> Bool {
        now.timeIntervalSince(entry.savedAt) < songTTL
    }

    func clear(source: SongSource, accountID: String) {
        lock.lock()
        let playlistKey = cacheKey(source: source, accountID: accountID)
        playlistEntries.removeValue(forKey: playlistKey)
        let songPrefix = cacheKey(source: source, accountID: "\(accountID)|")
        songEntries = songEntries.filter { !$0.key.hasPrefix(songPrefix) }
        let playlistSnapshot = playlistEntries
        let songSnapshot = songEntries
        lock.unlock()
        persistAsync(playlistSnapshot, key: playlistsKey)
        persistAsync(songSnapshot, key: songsKey)
    }

    private func cacheKey(source: SongSource, accountID: String) -> String {
        let normalizedAccount = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(source.rawValue)|\(normalizedAccount.isEmpty ? "default" : normalizedAccount)"
    }

    private func persistAsync<T: Encodable>(_ value: T, key: String) {
        persistenceQueue.async { [defaults] in
            guard let data = try? JSONEncoder().encode(value) else { return }
            defaults.set(data, forKey: key)
        }
    }
}
