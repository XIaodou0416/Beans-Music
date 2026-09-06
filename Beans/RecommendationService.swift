import Foundation

/// QQ 推荐接口的统一结果页。
struct QQRecommendationPage {
    let songs: [Song]
    let playlists: [Playlist]
    let artists: [Artist]
    let page: Int
    let hasMore: Bool
    let usedFallback: Bool
}

enum RecommendationServiceError: LocalizedError {
    case invalidURL
    case httpStatus(Int)
    case invalidResponse
    case emptyData
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "推荐接口地址无效"
        case .httpStatus(let status): return "推荐接口请求失败（HTTP \(status)）"
        case .invalidResponse: return "推荐接口返回格式无法解析"
        case .emptyData: return "推荐接口暂时没有数据"
        case .timeout: return "推荐接口请求超时"
        }
    }
}

/// QQ 音乐推荐服务。
///
/// `beans.qqRecommendationBaseURL` 可由宿主配置为推荐后端根地址；未配置时，
/// 服务复用现有 QQMusicAPI 官方接口，保证旧版本网络链路继续可用。
actor RecommendationService {
    static let shared = RecommendationService()
    static let baseURLKey = "beans.qqRecommendationBaseURL"

    private struct CacheEntry {
        let savedAt: Date
        let page: QQRecommendationPage
    }

    private let session: URLSession
    private var cache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 60

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 18
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func fetchNewSongs(limit: Int = 30) async throws -> QQRecommendationPage {
        try await fetch(.newSongs, page: 1, limit: limit)
    }

    func fetchGuessRecommendations(limit: Int = 30) async throws -> QQRecommendationPage {
        try await fetch(.guess, page: 1, limit: limit)
    }

    func fetchRadarRecommendations(page: Int = 1, limit: Int = 30) async throws -> QQRecommendationPage {
        let result = try await fetch(.radar, page: max(1, page), limit: limit)
        guard result.songs.isEmpty, page <= 1 else { return result }

        // 私人雷达为空时自动回退到猜你喜欢，再回退到每日推荐。
        let guess = try? await fetchGuessRecommendations(limit: limit)
        if let guess, !guess.songs.isEmpty {
            return QQRecommendationPage(
                songs: guess.songs,
                playlists: [],
                artists: guess.artists,
                page: 1,
                hasMore: false,
                usedFallback: true
            )
        }
        let daily = try? await fetchNewSongs(limit: limit)
        return QQRecommendationPage(
            songs: daily?.songs ?? [],
            playlists: [],
            artists: daily?.artists ?? [],
            page: 1,
            hasMore: false,
            usedFallback: true
        )
    }

    func fetchPlaylists(page: Int = 1, limit: Int = 25) async throws -> QQRecommendationPage {
        try await fetch(.playlists, page: max(1, page), limit: limit)
    }

    func fetchPlaylistDetail(id: Int) async throws -> QQRecommendationPage {
        guard id > 0 else { throw RecommendationServiceError.invalidResponse }
        let key = "detail-\(id)"
        if let cached = freshCache(for: key) { return cached }

        if configuredBaseURL != nil {
            let json = try await request(path: "/songlist/\(id)/detail", query: [:])
            let page = QQRecommendationPage(
                songs: Self.parseSongs(from: json),
                playlists: Self.parsePlaylists(from: json),
                artists: Self.parseArtists(from: json),
                page: 1,
                hasMore: false,
                usedFallback: false
            )
            guard !page.songs.isEmpty else { throw RecommendationServiceError.emptyData }
            save(page, for: key)
            return page
        }

        let songs = try await QQMusicAPI.shared.playlistSongs(listID: id)
        guard !songs.isEmpty else { throw RecommendationServiceError.emptyData }
        let page = QQRecommendationPage(songs: songs, playlists: [], artists: [], page: 1, hasMore: false, usedFallback: true)
        save(page, for: key)
        return page
    }

    private enum Endpoint: String {
        case newSongs = "new-songs"
        case guess
        case radar
        case playlists
    }

    private func fetch(_ endpoint: Endpoint, page: Int, limit: Int) async throws -> QQRecommendationPage {
        let key = "\(endpoint.rawValue)-\(page)-\(limit)"
        if let cached = freshCache(for: key) { return cached }

        let pageResult: QQRecommendationPage
        if configuredBaseURL != nil {
            let requests: [(path: String, query: [String: String])]
            switch endpoint {
            case .newSongs:
                requests = [
                    ("/recommend/get_recommend_newsong", ["limit": String(limit)]),
                    ("/getRecommend", ["limit": String(limit)])
                ]
            case .guess:
                requests = [
                    ("/recommend/get_guess_recommend", ["limit": String(limit)]),
                    ("/getRecommend", ["limit": String(limit)])
                ]
            case .radar:
                requests = [
                    ("/recommend/get_radar_recommend", ["page": String(page), "limit": String(limit)]),
                    ("/getRadioLists", ["page": String(max(0, page - 1)), "limit": String(limit)])
                ]
            case .playlists:
                requests = [
                    ("/recommend/get_recommend_songlist", ["page": String(page), "num": String(limit)]),
                    ("/getSongLists", ["page": String(max(0, page - 1)), "limit": String(limit), "categoryId": "10000000", "sortId": "5"])
                ]
            }
            let json = try await requestFirst(requests)
            pageResult = QQRecommendationPage(
                songs: Self.parseSongs(from: json),
                playlists: Self.parsePlaylists(from: json),
                artists: Self.parseArtists(from: json),
                page: page,
                hasMore: Self.hasMore(in: json, page: page, count: limit),
                usedFallback: false
            )
        } else {
            switch endpoint {
            case .newSongs:
                let songs = try await QQMusicAPI.shared.topListSongs(topid: 27, limit: limit)
                pageResult = QQRecommendationPage(songs: songs, playlists: [], artists: [], page: page, hasMore: false, usedFallback: true)
            case .guess:
                let songs = try await QQMusicAPI.shared.topListSongs(topid: 26, limit: limit)
                pageResult = QQRecommendationPage(songs: songs, playlists: [], artists: [], page: page, hasMore: false, usedFallback: true)
            case .radar:
                let songs = try await QQMusicAPI.shared.topListSongs(topid: 62, limit: limit)
                pageResult = QQRecommendationPage(songs: songs, playlists: [], artists: [], page: page, hasMore: false, usedFallback: true)
            case .playlists:
                let playlists = try await QQMusicAPI.shared.hotPlaylists(limit: limit)
                pageResult = QQRecommendationPage(songs: [], playlists: playlists, artists: [], page: page, hasMore: false, usedFallback: true)
            }
        }

        guard !pageResult.songs.isEmpty || !pageResult.playlists.isEmpty else {
            throw RecommendationServiceError.emptyData
        }
        save(pageResult, for: key)
        return pageResult
    }

    private var configuredBaseURL: URL? {
        guard let raw = UserDefaults.standard.string(forKey: Self.baseURLKey),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/") ? String(raw.dropLast()) : raw
        return URL(string: normalized)
    }

    private func request(path: String, query: [String: String]) async throws -> [String: Any] {
        guard let base = configuredBaseURL else { throw RecommendationServiceError.invalidURL }
        guard var components = URLComponents(url: base.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), resolvingAgainstBaseURL: false) else {
            throw RecommendationServiceError.invalidURL
        }
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw RecommendationServiceError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("BeansMusic/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw RecommendationServiceError.invalidResponse }
            guard http.statusCode == 200 else { throw RecommendationServiceError.httpStatus(http.statusCode) }
            guard !data.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw RecommendationServiceError.invalidResponse
            }
            return object
        } catch let error as RecommendationServiceError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw RecommendationServiceError.timeout
        } catch {
            throw RecommendationServiceError.invalidResponse
        }
    }

    private func requestFirst(_ requests: [(path: String, query: [String: String])]) async throws -> [String: Any] {
        var lastError: Error = RecommendationServiceError.invalidResponse
        for candidate in requests {
            do {
                return try await request(path: candidate.path, query: candidate.query)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func freshCache(for key: String) -> QQRecommendationPage? {
        guard let entry = cache[key], Date().timeIntervalSince(entry.savedAt) < cacheTTL else { return nil }
        return entry.page
    }

    private func save(_ page: QQRecommendationPage, for key: String) {
        cache[key] = CacheEntry(savedAt: Date(), page: page)
    }

    nonisolated static func parseSongs(from json: [String: Any]) -> [Song] {
        candidateDictionaries(in: json, keys: ["songs", "songlist", "songList", "tracks", "records", "items", "data", "result", "list"])
            .compactMap(song(from:))
            .deduplicated { $0.identityKey }
    }

    nonisolated static func parsePlaylists(from json: [String: Any]) -> [Playlist] {
        candidateDictionaries(in: json, keys: ["songlists", "songLists", "playlists", "playlist", "data", "result", "list", "items"])
            .compactMap(playlist(from:))
            .deduplicated { "\($0.source.rawValue)-\($0.id)" }
    }

    nonisolated static func parseArtists(from json: [String: Any]) -> [Artist] {
        candidateDictionaries(in: json, keys: ["artists", "singers", "singer", "artist", "data", "result", "list"])
            .compactMap(artist(from:))
            .deduplicated { "\($0.source.rawValue)-\($0.id)" }
    }

    private nonisolated static func candidateDictionaries(in json: [String: Any], keys: [String]) -> [[String: Any]] {
        for key in keys {
            if let value = json[key] {
                let found = dictionaries(from: value)
                if !found.isEmpty { return found }
            }
        }
        return dictionaries(from: json)
    }

    private nonisolated static func dictionaries(from value: Any) -> [[String: Any]] {
        if let dict = value as? [String: Any] {
            if looksLikeSong(dict) || looksLikePlaylist(dict) || looksLikeArtist(dict) { return [dict] }
            return dict.values.flatMap { dictionaries(from: $0) }
        }
        if let array = value as? [Any] { return array.flatMap { dictionaries(from: $0) } }
        if let array = value as? [[String: Any]] { return array }
        return []
    }

    private nonisolated static func song(from raw: [String: Any]) -> Song? {
        guard looksLikeSong(raw), let identity = stringValue(raw, keys: ["id", "songId", "songid", "songmid", "songMid", "mid"]) else { return nil }
        let id = intValue(raw["id"]) ?? deterministicID(identity)
        let name = stringValue(raw, keys: ["name", "songname", "songName", "title"]) ?? ""
        guard !name.isEmpty else { return nil }
        let artistValue: Any = raw["artists"] ?? raw["singers"] ?? raw["singer"] ?? raw["singerList"] ?? []
        let artistItems = dictionaries(from: artistValue)
        let artists = artistItems.compactMap { stringValue($0, keys: ["name", "singerName", "title"]) }.joined(separator: " / ")
        let artistText = artists.isEmpty ? (stringValue(raw, keys: ["artist", "artistName", "singerName"]) ?? "") : artists
        let albumDict = raw["album"] as? [String: Any]
        let album = stringValue(raw, keys: ["albumName", "albumname"]) ?? stringValue(albumDict ?? [:], keys: ["name", "albumName"]) ?? ""
        let coverRaw = stringValue(raw, keys: ["coverURL", "cover", "pic", "picUrl", "picurl", "imgurl", "albumPic", "albumPicUrl"])
            ?? stringValue(albumDict ?? [:], keys: ["picUrl", "picurl", "cover"])
        let durationRaw = raw["duration"] ?? raw["interval"] ?? raw["songDuration"] ?? raw["dt"] ?? 0
        let duration = normalizedDuration(durationRaw)
        let qqMid = stringValue(raw, keys: ["songmid", "songMid", "mid"]) ?? identity
        let mediaMid = stringValue(raw, keys: ["strMediaMid", "media_mid", "mediaMid"])
        let fee = intValue(raw["fee"]) ?? intValue(raw["pay"]) ?? intValue(raw["payplay"]) ?? 0
        return Song(id: id, name: name, artists: artistText, album: album, coverURL: qqImageURL(coverRaw), duration: duration, source: .qq, qqMid: qqMid, qqMediaMid: mediaMid, fee: fee)
    }

    private nonisolated static func playlist(from raw: [String: Any]) -> Playlist? {
        guard looksLikePlaylist(raw), let identity = stringValue(raw, keys: ["id", "songlistId", "songlist_id", "dissid", "diss_id", "tid"]) else { return nil }
        let id = intValue(raw["id"]) ?? intValue(raw["songlistId"]) ?? intValue(raw["dissid"]) ?? deterministicID(identity)
        let name = stringValue(raw, keys: ["name", "dissname", "dissName", "title", "songlistName"]) ?? ""
        guard !name.isEmpty else { return nil }
        let cover = stringValue(raw, keys: ["coverURL", "cover", "logo", "pic", "picUrl", "picurl", "imgurl"])
        let count = intValue(raw["trackCount"]) ?? intValue(raw["songnum"]) ?? intValue(raw["song_cnt"]) ?? intValue(raw["total_song_num"]) ?? 0
        return Playlist(id: id, name: name, coverURL: qqImageURL(cover), trackCount: count, source: .qq)
    }

    private nonisolated static func artist(from raw: [String: Any]) -> Artist? {
        guard looksLikeArtist(raw), let identity = stringValue(raw, keys: ["id", "singerMID", "singerMid", "mid", "singerId"]) else { return nil }
        let name = stringValue(raw, keys: ["name", "singerName", "title"]) ?? ""
        guard !name.isEmpty else { return nil }
        return Artist(id: identity, name: name, coverURL: qqImageURL(stringValue(raw, keys: ["cover", "pic", "picUrl", "picurl", "avatar"])), source: .qq)
    }

    private nonisolated static func looksLikeSong(_ raw: [String: Any]) -> Bool {
        stringValue(raw, keys: ["songname", "songName", "songmid", "songId", "songid"]) != nil
            || (stringValue(raw, keys: ["name"]) != nil && (raw["duration"] != nil || raw["interval"] != nil || raw["mid"] != nil))
    }

    private nonisolated static func looksLikePlaylist(_ raw: [String: Any]) -> Bool {
        stringValue(raw, keys: ["dissname", "dissName", "songlistId", "songlistName"]) != nil
            || (raw["song_cnt"] != nil && stringValue(raw, keys: ["name", "title"]) != nil)
    }

    private nonisolated static func looksLikeArtist(_ raw: [String: Any]) -> Bool {
        stringValue(raw, keys: ["singerName", "singerMID", "singerMid"]) != nil
    }

    private nonisolated static func stringValue(_ raw: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = raw[key] as? String, !value.isEmpty { return value }
            if let value = raw[key] as? NSNumber { return value.stringValue }
        }
        return nil
    }

    private nonisolated static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private nonisolated static func normalizedDuration(_ value: Any) -> TimeInterval {
        let raw: Double
        if let number = intValue(value) {
            raw = Double(number)
        } else if let number = value as? Double {
            raw = number
        } else {
            raw = 0
        }
        return raw > 1000 ? raw / 1000 : raw
    }

    private nonisolated static func deterministicID(_ value: String) -> Int {
        var result: UInt64 = 5381
        for byte in value.utf8 { result = ((result << 5) &+ result) &+ UInt64(byte) }
        return Int(result & 0x7fff_ffff)
    }

    private nonisolated static func qqImageURL(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("//") { return URL(string: "https:\(raw)") }
        if let url = URL(string: raw), url.scheme != nil { return url }
        return URL(string: "https://y.gtimg.cn/music/photo_new/T002R300x300M000\(raw).jpg")
    }

    private nonisolated static func hasMore(in json: [String: Any], page: Int, count: Int) -> Bool {
        if let value = json["hasMore"] as? Bool { return value }
        if let value = json["has_more"] as? Bool { return value }
        if let data = json["data"] as? [String: Any], let value = data["hasMore"] as? Bool { return value }
        let total = intValue(json["total"] ?? (json["data"] as? [String: Any])?["total"])
        return total.map { page * count < $0 } ?? false
    }
}

private extension Array {
    func deduplicated<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert(key($0)).inserted }
    }
}
