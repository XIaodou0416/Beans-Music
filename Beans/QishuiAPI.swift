import Foundation
import Security
import Combine

enum QishuiAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(String)
    case notLoggedIn

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "汽水音乐接口地址无效"
        case .invalidResponse: return "汽水音乐返回了无法识别的数据"
        case .server(let message): return message
        case .notLoggedIn: return "请先登录汽水音乐"
        }
    }
}

struct QishuiQRCode: Equatable {
    let token: String
    let image: String
    let expiresAt: TimeInterval
    let copywriting: String
}

struct QishuiAccount: Equatable {
    let id: String
    let nickname: String
    let avatarURL: URL?
    let isVIP: Bool
}

struct QishuiPlaylistDetails {
    let playlist: Playlist?
    let songs: [Song]
}

enum QishuiResourceURL {
    static func first(in value: Any?) -> URL? {
        first(in: value, depth: 0)
    }

    static func playlistCover(in playlist: [String: Any]) -> URL? {
        let raw = playlist["raw"] as? [String: Any] ?? playlist
        let keys = ["url_cover", "cover_url", "coverURL", "urlCover", "cover_uri", "cover", "pic_url", "picUrl"]
        for key in keys {
            if let url = first(in: raw[key]) { return url }
        }
        for key in keys {
            if let url = first(in: playlist[key]) { return url }
        }
        return nil
    }

    private static func first(in value: Any?, depth: Int) -> URL? {
        guard depth < 8 else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = trimmed.hasPrefix("//") ? "https:\(trimmed)" : trimmed
            guard let url = URL(string: candidate),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  url.host != nil else { return nil }
            return normalizedImageURL(url)
        }
        if let values = value as? [Any] {
            return values.lazy.compactMap { first(in: $0, depth: depth + 1) }.first
        }
        guard let object = value as? [String: Any] else { return nil }

        if let uri = object["uri"] as? String,
           let base = first(in: object["urls"] ?? object["url_list"], depth: depth + 1),
           let completed = complete(uri: uri, using: base) {
            return completed
        }

        let preferredKeys = [
            "url", "urls", "url_list", "cover_url", "cover_urls", "url_cover",
            "origin_url", "origin_url_list", "uri", "cover", "artwork"
        ]
        for key in preferredKeys {
            if let url = first(in: object[key], depth: depth + 1) { return url }
        }
        for nested in object.values {
            if let url = first(in: nested, depth: depth + 1) { return url }
        }
        return nil
    }

    private static func complete(uri: String, using base: URL) -> URL? {
        let value = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let direct = URL(string: value),
           ["http", "https"].contains(direct.scheme?.lowercased() ?? ""),
           direct.host != nil {
            return normalizedImageURL(direct)
        }
        if base.absoluteString.contains(value) { return base }
        guard value.contains("/") || base.path.hasSuffix("/") else { return nil }
        guard let url = URL(string: value, relativeTo: base)?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return nil }
        return normalizedImageURL(url)
    }

    private static func normalizedImageURL(_ url: URL) -> URL {
        guard url.host?.lowercased().hasSuffix("douyinpic.com") == true,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let range = components.percentEncodedPath.range(of: "/img/") else {
            return url
        }
        components.percentEncodedPath.replaceSubrange(range, with: "/obj/")
        return components.url ?? url
    }
}

struct QishuiSearchPageState {
    let hasMore: Bool
    let nextOffset: Int

    static func resolve(_ response: [String: Any], currentOffset: Int, receivedCount: Int) -> Self {
        let upstream = response["upstream"] as? [String: Any] ?? [:]
        let upstreamData = upstream["data"] as? [String: Any] ?? [:]
        let pagination = response["pagination"] as? [String: Any]
            ?? upstream["pagination"] as? [String: Any]
            ?? upstreamData["pagination"] as? [String: Any]
            ?? [:]
        let sources = [response, upstream, upstreamData, pagination]
        let moreValue = firstValue(in: sources, keys: ["has_more", "hasMore", "has_next", "hasNext"])
        let explicitMore = boolean(moreValue)
        let cursorValue = firstValue(in: sources, keys: ["next_offset", "nextOffset", "next_cursor", "nextCursor", "cursor"])
        let parsedCursor = integer(cursorValue)
        let nextOffset = parsedCursor.flatMap { $0 > currentOffset ? $0 : nil }
            ?? currentOffset + max(receivedCount, 1)
        return Self(
            hasMore: explicitMore ?? (parsedCursor.map { $0 > currentOffset } ?? false),
            nextOffset: nextOffset
        )
    }

    private static func firstValue(in sources: [[String: Any]], keys: [String]) -> Any? {
        for source in sources {
            for key in keys {
                if let value = source[key] { return value }
            }
        }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func boolean(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            switch value.lowercased() {
            case "1", "true", "yes": return true
            case "0", "false", "no": return false
            default: return nil
            }
        }
        return nil
    }
}

/// 汽水音乐统一网关客户端。
///
/// 汽水曲目和歌单 ID 使用字符串保存，避免把 19 位 ID 截断成 Int。客户端
/// 只把稳定的展示用 Int 写入现有模型，真正请求始终使用 qishuiID。
final class QishuiAPI: ObservableObject {
    static let shared = QishuiAPI()

    private static let sessionKeychainService = "com.beans.app.qishui"
    private static let sessionKeychainAccount = "sessionid"
    private static let baseURLKey = "beans.qishui.apiBaseURL"
    private static let defaultBaseURL = "http://189.24.78.193/qishui"

    @Published private(set) var isLoggedIn = false

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
        isLoggedIn = !(readSessionID() ?? "").isEmpty
    }

    var sessionID: String? {
        readSessionID()
    }

    func clearSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.sessionKeychainService,
            kSecAttrAccount as String: Self.sessionKeychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
        isLoggedIn = false
    }

    // MARK: - Search

    func searchSongs(keyword: String, limit: Int = 30) async throws -> [Song] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let targetCount = min(max(limit, 1), 200)
        var songs: [Song] = []
        var seenSongs = Set<String>()
        var offset = 0
        var visitedOffsets = Set<Int>()

        for _ in 0..<10 where songs.count < targetCount {
            guard visitedOffsets.insert(offset).inserted else { break }
            let pageSize = min(50, targetCount - songs.count)
            let query = [
                "keywords": trimmed,
                "count": String(pageSize),
                "cursor": String(offset),
                "offset": String(offset),
            ]
            let mixed = try await requestObject("/search/mixed", query: query)
            var pageSongs = trackDictionaries(mixed["tracks"] ?? mixed["data"] ?? mixed).compactMap(makeSong)
            var pageResponse = mixed
            if pageSongs.isEmpty {
                let direct = try await requestObject("/search", query: query)
                pageSongs = trackDictionaries(direct["tracks"] ?? direct["data"] ?? direct).compactMap(makeSong)
                pageResponse = direct
            }
            guard !pageSongs.isEmpty else { break }
            let receivedCount = pageSongs.count
            for song in pageSongs where seenSongs.insert(song.identityKey).inserted {
                songs.append(song)
                if songs.count >= targetCount { break }
            }
            let pageState = QishuiSearchPageState.resolve(
                pageResponse,
                currentOffset: offset,
                receivedCount: receivedCount
            )
            guard pageState.hasMore, pageState.nextOffset > offset else { break }
            offset = pageState.nextOffset
        }
        return deduplicated(songs).prefix(targetCount).map { $0 }
    }

    func searchPlaylists(keyword: String, limit: Int = 30) async throws -> [Playlist] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let data = try await requestObject("/search/playlist", query: [
            "keywords": trimmed,
            "count": String(min(max(limit, 1), 50)),
        ])
        return playlistDictionaries(data["playlists"] ?? data["data"] ?? data)
            .compactMap(makePlaylist)
            .prefix(limit)
            .map { $0 }
    }

    func searchArtists(keyword: String, limit: Int = 40) async throws -> [Artist] {
        let songs = try await searchSongs(keyword: keyword, limit: max(limit * 2, 40))
        var result: [Artist] = []
        var seen = Set<String>()
        for song in songs {
            let artistNames = splitArtists(song.artists)
            for name in artistNames {
                let key = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                result.append(Artist(
                    id: "qishui-artist-\(Self.stableID(key))",
                    name: name,
                    coverURL: song.coverURL,
                    source: .qishui
                ))
                if result.count >= limit { return result }
            }
        }
        return result
    }

    func searchAlbums(keyword: String, limit: Int = 40) async throws -> [Album] {
        let songs = try await searchSongs(keyword: keyword, limit: max(limit * 3, 80))
        return albums(from: songs, limit: limit)
    }

    // MARK: - Discovery and collections

    func recommendedPlaylists(limit: Int = 18) async throws -> [Playlist] {
        let data = try await requestObject("/recommend/playlist", query: [
            "count": String(min(max(limit, 1), 50)),
        ])
        return playlistDictionaries(data["playlists"] ?? data["data"] ?? data)
            .compactMap(makePlaylist)
            .prefix(limit)
            .map { $0 }
    }

    func playlistDetails(id: String, count: Int = 1000) async throws -> QishuiPlaylistDetails {
        let targetCount = min(max(count, 1), 1000)
        let pageSize = min(targetCount, 100)
        var cursor = ""
        var sessionID = ""
        var visitedCursors = Set<String>()
        var playlist: Playlist?
        var songs: [Song] = []
        var seenSongs = Set<String>()

        for _ in 0..<20 where songs.count < targetCount {
            var query = ["playlist_id": id, "count": String(pageSize)]
            if !cursor.isEmpty { query["cursor"] = cursor }
            if !sessionID.isEmpty { query["session_id"] = sessionID }
            let data = try await requestObject("/playlist/detail", query: query)
            if sessionID.isEmpty {
                sessionID = firstString(data, keys: ["session_id", "sessionId"]) ?? ""
            }
            if playlist == nil {
                playlist = dictionary(data["playlist"]).flatMap(makePlaylist)
            }
            let resources = data["media_resources"] ?? data["tracks"] ?? data["songs"] ?? []
            let pageSongs = trackDictionaries(resources).compactMap(makeSong)
            guard !pageSongs.isEmpty else { break }
            for song in pageSongs where seenSongs.insert(song.identityKey).inserted {
                songs.append(song)
                if songs.count >= targetCount { break }
            }
            let nextCursor = firstString(data, keys: ["next_cursor", "nextCursor", "cursor"]) ?? ""
            guard !nextCursor.isEmpty,
                  nextCursor != cursor,
                  visitedCursors.insert(nextCursor).inserted else { break }
            cursor = nextCursor
        }
        return QishuiPlaylistDetails(playlist: playlist, songs: Array(songs.prefix(targetCount)))
    }

    func playlistSongs(id: String, count: Int = 1000) async throws -> [Song] {
        try await playlistDetails(id: id, count: count).songs
    }

    func artistSongs(name: String, limit: Int = 300) async throws -> [Song] {
        let songs = try await searchSongs(keyword: name, limit: max(limit, 100))
        let expected = normalizedArtist(name)
        let matching = songs.filter { song in
            splitArtists(song.artists).contains { normalizedArtist($0).contains(expected) || expected.contains(normalizedArtist($0)) }
        }
        return Array((matching.isEmpty ? songs : matching).prefix(limit))
    }

    func artistAlbums(name: String, limit: Int = 60) async throws -> [Album] {
        albums(from: try await artistSongs(name: name, limit: max(limit * 4, 160)), limit: limit)
    }

    func albumSongs(album: Album, limit: Int = 300) async throws -> [Song] {
        let query = [album.artistName, album.name]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let songs = try await searchSongs(keyword: query.isEmpty ? album.name : query, limit: limit)
        let expected = normalizedAlbum(album.name)
        let matching = songs.filter { normalizedAlbum($0.album) == expected }
        return Array((matching.isEmpty ? songs : matching).prefix(limit))
    }

    // MARK: - Playback, lyrics and comments

    func playbackURL(for song: Song) async throws -> URL? {
        guard let identifier = song.qishuiID, !identifier.isEmpty else { return nil }
        let detail = try await requestObject("/song/detail", query: ["track_id": identifier])
        if let url = firstURL(in: detail, keys: ["audio_url", "play_url", "main_url", "backup_url"]) {
            return url
        }
        let info = try await requestObject("/audio/info", query: ["track_id": identifier])
        return firstURL(in: info, keys: ["audio_url", "play_url", "main_url", "backup_url"])
    }

    func lyric(for song: Song) async throws -> String? {
        guard let identifier = song.qishuiID, !identifier.isEmpty else { return nil }
        let data = try await requestObject("/lyric", query: ["track_id": identifier])
        if let lyric = firstString(data, keys: ["lyric", "lyrics", "content", "lrc"]), !lyric.isEmpty {
            return lyric
        }
        return nil
    }

    func comments(for song: Song, limit: Int = 30) async throws -> NetEaseAPI.SongCommentPage {
        guard let identifier = song.qishuiID, !identifier.isEmpty else {
            return NetEaseAPI.SongCommentPage(total: 0, hot: [], comments: [])
        }
        let data = try await requestObject("/comment", query: [
            "track_id": identifier,
            "count": String(min(max(limit, 1), 50)),
        ])
        let comments = dictionaryArray(data["comments"] ?? data["data"] ?? data).compactMap { raw -> SongComment? in
            let idText = firstString(raw, keys: ["id", "comment_id", "commentId"]) ?? UUID().uuidString
            let nickname = firstString(raw, keys: ["user_name", "nickname", "userName"]) ?? "汽水用户"
            let content = firstString(raw, keys: ["content", "text", "comment_text"]) ?? ""
            guard !content.isEmpty else { return nil }
            let avatar = firstString(raw, keys: ["user_avatar", "avatar_url", "avatarUrl"]).flatMap(URL.init(string:))
            let timestamp = number(raw["timestamp"] ?? raw["create_time"] ?? raw["time"])
            let seconds = timestamp > 10_000_000_000 ? timestamp / 1_000 : timestamp
            return SongComment(
                id: Self.stableID(idText),
                content: content,
                nickname: nickname,
                avatarURL: avatar,
                time: Date(timeIntervalSince1970: seconds > 0 ? seconds : Date().timeIntervalSince1970),
                likedCount: Int(number(raw["like_count"] ?? raw["likeCount"])),
                isHot: false
            )
        }
        return NetEaseAPI.SongCommentPage(total: comments.count, hot: [], comments: comments)
    }

    // MARK: - Login and account playlists

    func requestQRCode() async throws -> QishuiQRCode {
        let data = try await requestObject("/auth/qrcode")
        let token = firstString(data, keys: ["token"]) ?? ""
        let image = firstString(data, keys: ["qrcode", "qr_code", "image"]) ?? ""
        guard !token.isEmpty, !image.isEmpty else { throw QishuiAPIError.invalidResponse }
        return QishuiQRCode(
            token: token,
            image: image,
            expiresAt: number(data["expire_time"]),
            copywriting: firstString(data, keys: ["copywriting", "message"]) ?? "请使用抖音 App 扫码确认"
        )
    }

    func pollQRCode(token: String) async throws -> Bool {
        let data = try await requestObject("/auth/qrcode/status", method: "POST", body: ["token": token])
        let session = dictionary(data["auth"])?["sessionid"] as? String
            ?? firstString(data, keys: ["sessionid", "session_id"])
        if let session, !session.isEmpty {
            saveSessionID(session)
            return true
        }
        let status = firstString(data, keys: ["status", "state"])?.lowercased() ?? ""
        return ["success", "confirmed", "ok", "1"].contains(status)
    }

    func account() async throws -> QishuiAccount {
        guard let session = readSessionID(), !session.isEmpty else { throw QishuiAPIError.notLoggedIn }
        let data = try await requestObject("/auth/me", method: "POST", body: ["sessionid": session])
        let source = dictionary(data["profile"] ?? data["user"] ?? data) ?? data
        return QishuiAccount(
            id: firstString(source, keys: ["id", "user_id"]) ?? "",
            nickname: firstString(source, keys: ["nickname", "name"]) ?? "汽水音乐用户",
            avatarURL: firstString(source, keys: ["avatar_url", "avatarUrl", "avatar"]).flatMap(URL.init(string:)),
            isVIP: bool(source["is_vip"] ?? source["vip"])
        )
    }

    func accountPlaylists() async throws -> [Playlist] {
        guard let session = readSessionID(), !session.isEmpty else { throw QishuiAPIError.notLoggedIn }
        let data = try await requestObject("/me/playlists", method: "POST", body: ["sessionid": session])
        return playlistDictionaries(data["playlists"] ?? data["data"] ?? data).compactMap(makePlaylist)
    }

    func accountCollection() async throws -> [Playlist] {
        guard let session = readSessionID(), !session.isEmpty else { throw QishuiAPIError.notLoggedIn }
        let data = try await requestObject("/me/collection/mixed", method: "POST", body: ["sessionid": session])
        let collections = dictionaryArray(data["mixed_collections"] ?? data["collections"] ?? data["data"])
        return collections.compactMap { dictionary($0["playlist"] ?? $0).flatMap(makePlaylist) }
    }

    // MARK: - HTTP

    private func requestObject(
        _ path: String,
        method: String = "GET",
        query: [String: String] = [:],
        body: [String: Any]? = nil
    ) async throws -> [String: Any] {
        let value = try await requestValue(path, method: method, query: query, body: body)
        if let object = value as? [String: Any] { return object }
        throw QishuiAPIError.invalidResponse
    }

    private func requestValue(
        _ path: String,
        method: String = "GET",
        query: [String: String] = [:],
        body: [String: Any]? = nil
    ) async throws -> Any {
        guard let baseURL = URL(string: UserDefaults.standard.string(forKey: Self.baseURLKey) ?? Self.defaultBaseURL),
              var components = URLComponents(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), resolvingAgainstBaseURL: false)
        else { throw QishuiAPIError.invalidURL }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw QishuiAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Beans-Music/\(UpdateChecker.currentVersion)", forHTTPHeaderField: "User-Agent")
        if let session = readSessionID(), !session.isEmpty {
            request.setValue("sessionid=\(session)", forHTTPHeaderField: "Cookie")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw QishuiAPIError.server("汽水音乐服务器请求失败")
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QishuiAPIError.invalidResponse
        }
        let code = Int(number(root["code"]))
        if code != 0 {
            throw QishuiAPIError.server(firstString(root, keys: ["message", "msg"]) ?? "汽水音乐接口返回失败")
        }
        return root["data"] ?? [:]
    }

    // MARK: - Mapping helpers

    private func makeSong(_ raw: [String: Any]) -> Song? {
        let entity = dictionary(raw["entity"])
        let wrapper = dictionary(entity?["track_wrapper"] ?? raw["track_wrapper"])
        let track = dictionary(entity?["track"])
            ?? dictionary(raw["track"])
            ?? dictionary(wrapper?["track"])
            ?? raw
        guard let identifier = firstString(track, keys: ["id", "track_id"]), !identifier.isEmpty else { return nil }
        let album = dictionary(track["album"])
        let artistValues = dictionaryArray(track["artists"])
        let artistText = artistValues.compactMap { firstString($0, keys: ["name", "simple_display_name"]) }.joined(separator: " / ")
        let albumName = firstString(album, keys: ["name"]) ?? firstString(track, keys: ["album_name", "albumName"]) ?? ""
        let cover = QishuiResourceURL.first(in: album?["cover_url"])
            ?? QishuiResourceURL.first(in: album?["coverURL"])
            ?? QishuiResourceURL.first(in: album?["url_cover"])
            ?? QishuiResourceURL.first(in: track["cover_url"])
            ?? QishuiResourceURL.first(in: track["coverURL"])
            ?? QishuiResourceURL.first(in: track["url_cover"])
            ?? QishuiResourceURL.first(in: track["cover_uri"])
        let rawDuration = number(track["duration"] ?? track["duration_ms"] ?? track["interval"])
        let duration = rawDuration > 1000 ? rawDuration / 1000 : rawDuration
        let stats = dictionary(track["stats"]) ?? [:]
        let fee = bool(stats["is_vip"] ?? stats["is_paid"] ?? stats["need_pay"] ?? track["is_vip"])
            ? 1
            : Int(number(track["fee"] ?? track["pay_flag"]))
        return Song(
            id: Self.stableID(identifier),
            name: firstString(track, keys: ["name", "trackName", "title"]) ?? "",
            artists: artistText.isEmpty ? (firstString(track, keys: ["artists_text", "artist", "singer"]) ?? "") : artistText,
            album: albumName,
            coverURL: cover,
            duration: duration,
            source: .qishui,
            qishuiID: identifier,
            fee: fee
        )
    }

    private func makePlaylist(_ raw: [String: Any]) -> Playlist? {
        let playlist = dictionary(raw["playlist"]) ?? raw
        guard let identifier = firstString(playlist, keys: ["id", "playlist_id"]), !identifier.isEmpty else { return nil }
        let cover = QishuiResourceURL.playlistCover(in: playlist)
        return Playlist(
            id: Self.stableID(identifier),
            name: firstString(playlist, keys: ["title", "name"]) ?? "未命名歌单",
            coverURL: cover,
            trackCount: Int(number(playlist["count_tracks"] ?? playlist["track_count"] ?? playlist["song_count"])),
            creatorName: firstString(playlist, keys: ["creator_name", "creatorName", "nickname"]) ?? "",
            playlistDescription: firstString(playlist, keys: ["description", "intro"]) ?? "",
            source: .qishui,
            qishuiID: identifier
        )
    }

    private func albums(from songs: [Song], limit: Int) -> [Album] {
        var grouped: [String: [Song]] = [:]
        for song in songs {
            let name = song.album.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = "\(normalizedAlbum(name))|\(normalizedArtist(song.artists))"
            grouped[key, default: []].append(song)
        }
        return grouped.values.compactMap { group in
            guard let first = group.first else { return nil }
            let key = "\(first.album)|\(first.artists)"
            return Album(
                id: "qishui-album-\(Self.stableID(key))",
                name: first.album,
                artistName: first.artists,
                coverURL: first.coverURL,
                source: .qishui,
                trackCount: group.count
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        .prefix(limit)
        .map { $0 }
    }

    private func trackDictionaries(_ value: Any?) -> [[String: Any]] {
        if let direct = value as? [[String: Any]] { return direct }
        if let object = value as? [String: Any] {
            if let direct = object["tracks"] as? [[String: Any]] { return direct }
            if let direct = object["media_resources"] as? [[String: Any]] { return direct }
            if let direct = object["data"] as? [[String: Any]] { return direct }
            return object.values.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    private func playlistDictionaries(_ value: Any?) -> [[String: Any]] {
        if let direct = value as? [[String: Any]] { return direct }
        if let object = value as? [String: Any] {
            if let direct = object["playlists"] as? [[String: Any]] { return direct }
            if let direct = object["data"] as? [[String: Any]] { return direct }
        }
        return []
    }

    private func dictionaryArray(_ value: Any?) -> [[String: Any]] {
        if let array = value as? [[String: Any]] { return array }
        if let array = value as? [Any] { return array.compactMap { $0 as? [String: Any] } }
        return []
    }

    private func dictionary(_ value: Any?) -> [String: Any]? { value as? [String: Any] }

    private func deduplicated(_ songs: [Song]) -> [Song] {
        var seen = Set<String>()
        return songs.filter { seen.insert($0.identityKey).inserted }
    }

    private func splitArtists(_ value: String) -> [String] {
        value.components(separatedBy: CharacterSet(charactersIn: "/／,，、&＆+＋|｜;；"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func normalizedArtist(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .filter { !$0.isWhitespace && !$0.isPunctuation }
    }

    private func normalizedAlbum(_ value: String) -> String {
        normalizedArtist(value)
    }

    private func number(_ value: Any?) -> Double {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) ?? 0 }
        return 0
    }

    private func bool(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String { return ["1", "true", "yes", "on"].contains(value.lowercased()) }
        return false
    }

    private func firstString(_ object: [String: Any]?, keys: [String]) -> String? {
        guard let object else { return nil }
        return firstString(object, keys: keys)
    }

    private func firstString(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty { return value }
            if let value = object[key] as? NSNumber { return value.stringValue }
        }
        return nil
    }

    private func firstURL(in object: [String: Any], keys: [String]) -> URL? {
        for key in keys {
            if let value = object[key] as? String, let url = URL(string: value), url.scheme != nil { return url }
            if let nested = object[key] as? [String: Any], let url = firstURL(in: nested, keys: keys) { return url }
        }
        for value in object.values {
            if let nested = value as? [String: Any], let url = firstURL(in: nested, keys: keys) { return url }
            if let list = value as? [[String: Any]] {
                for item in list where item[keys.first ?? ""] != nil {
                    if let url = firstURL(in: item, keys: keys) { return url }
                }
            }
        }
        return nil
    }

    private func readSessionID() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.sessionKeychainService,
            kSecAttrAccount as String: Self.sessionKeychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }

    private func saveSessionID(_ value: String) {
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.sessionKeychainService,
            kSecAttrAccount as String: Self.sessionKeychainAccount,
        ]
        SecItemDelete(base as CFDictionary)
        let attributes = base.merging([kSecValueData as String: data]) { _, new in new }
        SecItemAdd(attributes as CFDictionary, nil)
        isLoggedIn = true
    }

    static func stableID(_ value: String) -> Int {
        var hash: UInt64 = 1469598103934665603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        let positive = hash & 0x7fff_ffff_ffff_ffff
        return max(1, Int(positive))
    }
}
