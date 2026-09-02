import Foundation

final class NetEaseAPI {
    static let shared = NetEaseAPI()

    private let domain = "https://music.163.com"
    private let apiDomain = "https://interface.music.163.com"
    private let session: URLSession

    // 模拟 PC 客户端环境（与 NeteaseCloudMusicApi 一致）
    private let os = "pc"
    private let appver = "3.1.17.204416"
    private let osver = "Microsoft-Windows-10-Professional-build-19045-64bit"
    private let channel = "netease"

    private let nuid: String
    private let deviceId: String
    private let wnMcid: String
    private let cookiesKey = "beans.netease.cookies"
    private var storedCookies: [String: String] = [:]

    init() {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)

        nuid = Self.randomHex(length: 32)      // 64 位 hex
        deviceId = Self.randomHex(length: 26)  // 52 位 hex
        wnMcid = "\(Self.randomLowercase(6)).\(Int(Date().timeIntervalSince1970 * 1000)).01.0"

        if let data = UserDefaults.standard.data(forKey: cookiesKey),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            storedCookies = saved
        }
    }

    // MARK: - 请求

    private func request(_ uri: String, payload: [String: Any], crypto: String) async throws -> [String: Any] {
        let url: URL
        let form: String
        var request: URLRequest

        if crypto == "weapi" {
            guard let parsed = URL(string: domain + "/weapi" + uri.dropFirst(4)) else { throw NetEaseError.unknown("请求地址无效") }
            url = parsed
            var data = payload
            data["csrf_token"] = csrfToken
            let enc = NetEaseCrypto.weapi(data)
            form = "params=\(formEncode(enc["params"] ?? ""))&encSecKey=\(formEncode(enc["encSecKey"] ?? ""))"
            request = URLRequest(url: url)
            request.setValue(weapiCookieHeader(), forHTTPHeaderField: "Cookie")
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0", forHTTPHeaderField: "User-Agent")
            request.setValue(domain, forHTTPHeaderField: "Referer")
        } else {
            guard let parsed = URL(string: apiDomain + "/eapi" + uri.dropFirst(4)) else { throw NetEaseError.unknown("请求地址无效") }
            url = parsed
            let header = eapiHeader()
            var data = payload
            data["e_r"] = false
            data["header"] = header
            let enc = NetEaseCrypto.eapi(data, path: uri)
            form = "params=\(formEncode(enc["params"] ?? ""))"
            request = URLRequest(url: url)
            request.setValue(eapiCookieHeader(header: header), forHTTPHeaderField: "Cookie")
            request.setValue("NeteaseMusic 9.0.90/5038 (iPhone; iOS 16.2; zh_CN)", forHTTPHeaderField: "User-Agent")
        }

        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(form.utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetEaseError.network }
        storeCookies(from: http)
        guard http.statusCode == 200 else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(120) ?? ""
            throw NetEaseError.httpStatus(http.statusCode, String(snippet))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(120) ?? ""
            throw NetEaseError.decoding(String(snippet))
        }
        return json
    }

    private func formEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    // MARK: - Cookie 构造

    private var csrfToken: String {
        cookieValue(named: "__csrf")
    }

    private var musicU: String {
        cookieValue(named: "MUSIC_U")
    }

    private func cookieValue(named name: String) -> String {
        storedCookies[name] ?? ""
    }

    func clearCookies() {
        storedCookies.removeAll()
        UserDefaults.standard.removeObject(forKey: cookiesKey)
    }

    /// 应用内网页登录：将 WKWebView 中 music.163.com 的 Cookie 合并进登录态并持久化
    func importWebCookies(_ cookies: [String: String]) {
        var changed = false
        for (key, value) in cookies where !value.isEmpty {
            if storedCookies[key] != value {
                storedCookies[key] = value
                changed = true
            }
        }
        if changed, let data = try? JSONEncoder().encode(storedCookies) {
            UserDefaults.standard.set(data, forKey: cookiesKey)
        }
    }

    private func storeCookies(from response: HTTPURLResponse) {
        var changed = false
        for (key, value) in response.allHeaderFields {
            guard let key = key as? String, key.lowercased() == "set-cookie",
                  let value = value as? String, !value.isEmpty,
                  let url = response.url
            else { continue }
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": value], for: url)
            for cookie in cookies where !cookie.value.isEmpty {
                if storedCookies[cookie.name] != cookie.value {
                    storedCookies[cookie.name] = cookie.value
                    changed = true
                }
            }
        }
        if changed {
            if let data = try? JSONEncoder().encode(storedCookies) {
                UserDefaults.standard.set(data, forKey: cookiesKey)
            }
        }
    }

    private func weapiCookieHeader() -> String {
        let ts = String(Int(Date().timeIntervalSince1970 * 1000))
        var parts: [String] = []
        parts.append("__remember_me=true")
        parts.append("ntes_kaola_ad=1")
        parts.append("_ntes_nuid=\(nuid)")
        parts.append("_ntes_nnid=\(nuid),\(ts)")
        parts.append("WNMCID=\(wnMcid)")
        parts.append("WEVNSM=1.0.0")
        parts.append("osver=\(osver)")
        parts.append("deviceId=\(deviceId)")
        parts.append("os=\(os)")
        parts.append("channel=\(channel)")
        parts.append("appver=\(appver)")
        parts.append("NMTID=\(Self.randomHex(length: 16))")
        if !musicU.isEmpty { parts.append("MUSIC_U=\(musicU)") }
        if !csrfToken.isEmpty { parts.append("__csrf=\(csrfToken)") }
        return parts.joined(separator: "; ")
    }

    private func eapiHeader() -> [String: String] {
        let ts = String(Int(Date().timeIntervalSince1970 * 1000))
        let buildver = String(ts.prefix(10))
        var header: [String: String] = [
            "osver": osver,
            "deviceId": deviceId,
            "os": os,
            "appver": appver,
            "versioncode": "140",
            "mobilename": "",
            "buildver": buildver,
            "resolution": "1920x1080",
            "__csrf": csrfToken,
            "channel": channel,
            "requestId": "\(ts)_\(String(format: "%04d", Int.random(in: 0...999)))",
        ]
        if !musicU.isEmpty { header["MUSIC_U"] = musicU }
        return header
    }

    private func eapiCookieHeader(header: [String: String]) -> String {
        header.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "; ")
    }

    private static func randomHex(length: Int) -> String {
        let chars = "0123456789abcdef"
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }

    private static func randomLowercase(_ count: Int) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyz"
        return String((0..<count).compactMap { _ in chars.randomElement() })
    }

    // MARK: - 登录（二维码，eapi 优先、weapi 降级）

    func qrKey() async throws -> String {
        do {
            return try await qrKeyEAPI()
        } catch {
            return try await qrKeyWEAPI()
        }
    }

    private func qrKeyEAPI() async throws -> String {
        let json = try await request("/api/login/qrcode/unikey", payload: ["type": 3], crypto: "eapi")
        if let key = json["unikey"] as? String, !key.isEmpty { return key }
        if let data = json["data"] as? [String: Any], let key = data["unikey"] as? String, !key.isEmpty { return key }
        throw NetEaseError.unknown("获取二维码密钥失败")
    }

    private func qrKeyWEAPI() async throws -> String {
        let json = try await request("/api/login/qrcode/unikey", payload: ["type": 3], crypto: "weapi")
        if let key = json["unikey"] as? String, !key.isEmpty { return key }
        if let data = json["data"] as? [String: Any], let key = data["unikey"] as? String, !key.isEmpty { return key }
        throw NetEaseError.unknown("获取二维码密钥失败")
    }

    func qrLoginURL(key: String) -> String {
        "https://music.163.com/login?codekey=\(key)"
    }

    func qrCheck(key: String) async throws -> Int {
        do {
            let json = try await request("/api/login/qrcode/client/login", payload: ["key": key, "type": 3], crypto: "eapi")
            let code = json["code"] as? Int ?? -1
            if code != -1 { return code }
        } catch {}
        let json = try await request("/api/login/qrcode/client/login", payload: ["key": key, "type": 3], crypto: "weapi")
        return json["code"] as? Int ?? -1
    }

    func account() async throws -> NetEaseUser {
        let json = try await request("/api/w/nuser/account/get", payload: [:], crypto: "weapi")
        guard let profile = json["profile"] as? [String: Any], let user = NetEaseUser(json: profile) else {
            throw NetEaseError.unknown("获取账号信息失败")
        }
        return user
    }

    // MARK: - 音乐库

    func userPlaylists(uid: Int) async throws -> [Playlist] {
        let json = try await request("/api/user/playlist", payload: ["uid": uid, "limit": 1000, "offset": 0, "includeVideo": true], crypto: "weapi")
        let list = json["playlist"] as? [[String: Any]] ?? []
        return list.compactMap(Playlist.init(json:))
    }

    func playlistTracks(id: Int) async throws -> [Song] {
        let json = try await request("/api/v6/playlist/detail", payload: ["id": id, "n": 100000, "s": 8], crypto: "eapi")
        let playlist = json["playlist"] as? [String: Any] ?? [:]
        let tracks = playlist["tracks"] as? [[String: Any]] ?? []
        return tracks.compactMap(Song.init(json:))
    }

    func songURLs(ids: [Int], level: String = "standard") async throws -> [Int: String] {
        let idsString = "[" + ids.map(String.init).joined(separator: ",") + "]"
        let json = try await request("/api/song/enhance/player/url/v1", payload: ["ids": idsString, "level": level, "encodeType": "flac"], crypto: "eapi")
        let data = json["data"] as? [[String: Any]] ?? []
        var result: [Int: String] = [:]
        for item in data {
            if let id = item["id"] as? Int, let url = item["url"] as? String, !url.isEmpty {
                result[id] = url
            }
        }
        return result
    }

    /// 歌曲播放地址 + 试听标记（用于灰色/VIP 歌曲解锁判断）
    struct SongURLInfo {
        let url: String?
        /// 存在 freeTrialInfo 表示仅返回试听片段（VIP 歌曲）
        let freeTrial: Bool
    }

    func songURLInfo(ids: [Int], level: String = "standard") async throws -> [Int: SongURLInfo] {
        let idsString = "[" + ids.map(String.init).joined(separator: ",") + "]"
        let json = try await request("/api/song/enhance/player/url/v1", payload: ["ids": idsString, "level": level, "encodeType": "flac"], crypto: "eapi")
        let data = json["data"] as? [[String: Any]] ?? []
        var result: [Int: SongURLInfo] = [:]
        for item in data {
            guard let id = item["id"] as? Int else { continue }
            let rawURL = item["url"] as? String
            let url = (rawURL?.isEmpty ?? true) ? nil : rawURL
            let freeTrial = (item["freeTrialInfo"] as? [String: Any]) != nil
            result[id] = SongURLInfo(url: url, freeTrial: freeTrial)
        }
        return result
    }

    // MARK: - 歌词

    func lyric(id: Int) async throws -> String? {
        let json = try await request("/api/song/lyric", payload: ["id": id, "lv": -1, "kv": -1, "tv": -1], crypto: "weapi")
        guard let lrc = json["lrc"] as? [String: Any], let text = lrc["lyric"] as? String, !text.isEmpty else {
            return nil
        }
        return text
    }

    /// 歌词 + 翻译（tlyric），用于歌词翻译显示
    func lyricWithTranslation(id: Int) async throws -> (lrc: String?, tlyric: String?) {
        let json = try await request("/api/song/lyric", payload: ["id": id, "lv": -1, "kv": -1, "tv": -1], crypto: "weapi")
        let lrc = (json["lrc"] as? [String: Any])?["lyric"] as? String
        let tlyric = (json["tlyric"] as? [String: Any])?["lyric"] as? String
        return (lrc, tlyric)
    }

    // MARK: - 评论

    struct SongCommentPage {
        let total: Int
        let hot: [SongComment]
        var comments: [SongComment]
    }

    /// 歌曲评论（含热门评论）
    func songComments(id: Int, limit: Int = 30, offset: Int = 0) async throws -> SongCommentPage {
        let json = try await request("/api/v1/resource/comments/R_SO_4_\(id)", payload: ["rid": id, "limit": limit, "offset": offset, "beforeTime": 0], crypto: "weapi")
        let total = json["total"] as? Int ?? 0
        let hot = (json["hotComments"] as? [[String: Any]] ?? []).compactMap { SongComment(json: $0, isHot: true) }
        let comments = (json["comments"] as? [[String: Any]] ?? []).compactMap { SongComment(json: $0) }
        return SongCommentPage(total: total, hot: hot, comments: comments)
    }

    // MARK: - 搜索

    func search(keyword: String, limit: Int = 30, offset: Int = 0) async throws -> [Song] {
        let json = try await request("/api/cloudsearch/pc", payload: ["s": keyword, "type": 1, "limit": limit, "offset": offset, "total": true], crypto: "weapi")
        let result = json["result"] as? [String: Any] ?? [:]
        let songs = result["songs"] as? [[String: Any]] ?? []
        return songs.compactMap(Song.init(json:))
    }

    /// 搜索歌手（type=100）
    func searchArtists(keyword: String, limit: Int = 30) async throws -> [Artist] {
        let json = try await request("/api/cloudsearch/pc", payload: ["s": keyword, "type": 100, "limit": limit, "offset": 0, "total": true], crypto: "weapi")
        let result = json["result"] as? [String: Any] ?? [:]
        let list = result["artists"] as? [[String: Any]] ?? []
        var artists: [Artist] = []
        for item in list {
            guard let id = item["id"] as? Int else { continue }
            let pic = item["picUrl"] as? String ?? (item["img1v1Url"] as? String ?? "")
            artists.append(Artist(
                id: "netease-\(id)",
                name: item["name"] as? String ?? "",
                coverURL: pic.isEmpty ? nil : URL(string: pic),
                source: .netease
            ))
        }
        return artists
    }

    /// 搜索专辑（type=10）
    func searchAlbums(keyword: String, limit: Int = 30) async throws -> [Album] {
        let json = try await request("/api/cloudsearch/pc", payload: ["s": keyword, "type": 10, "limit": limit, "offset": 0, "total": true], crypto: "weapi")
        let result = json["result"] as? [String: Any] ?? [:]
        let list = result["albums"] as? [[String: Any]] ?? []
        var albums: [Album] = []
        for item in list {
            guard let id = item["id"] as? Int else { continue }
            let artist = (item["artist"] as? [String: Any])?["name"] as? String ?? ""
            let pic = item["picUrl"] as? String ?? ""
            albums.append(Album(
                id: "netease-\(id)",
                name: item["name"] as? String ?? "",
                artistName: artist,
                coverURL: pic.isEmpty ? nil : URL(string: pic),
                source: .netease,
                trackCount: item["size"] as? Int
            ))
        }
        return albums
    }

    // MARK: - 歌手主页

    /// 歌手热门歌曲（分页加载，避免接口单页最多返回 30 首）
    func artistHotSongs(artistID: Int, limit: Int = 120) async throws -> [Song] {
        let targetCount = max(limit, 1)
        let pageSize = min(targetCount, 30)
        var songs: [Song] = []
        var seen = Set<String>()
        var offset = 0

        while songs.count < targetCount {
            let json = try await request(
                "/api/artist/songs",
                payload: [
                    "id": artistID,
                    "private_cloud": true,
                    "work_type": 1,
                    "order": "hot",
                    "offset": offset,
                    "limit": pageSize,
                ],
                crypto: "weapi"
            )
            let list = json["songs"] as? [[String: Any]] ?? []
            guard !list.isEmpty else { break }

            var added = 0
            for item in list {
                guard let song = Song(json: item), seen.insert(song.identityKey).inserted else { continue }
                songs.append(song)
                added += 1
                if songs.count >= targetCount { break }
            }

            // 某些接口异常时会重复返回同一页，避免陷入无限请求。
            guard added > 0 else { break }
            offset += list.count
            if list.count < pageSize { break }
        }
        return Array(songs.prefix(targetCount))
    }

    /// 歌手专辑
    func artistAlbums(artistID: Int, limit: Int = 50) async throws -> [Album] {
        let json = try await request("/api/artist/albums", payload: ["id": artistID, "limit": limit, "offset": 0], crypto: "weapi")
        let list = json["hotAlbums"] as? [[String: Any]] ?? []
        var albums: [Album] = []
        for item in list {
            guard let id = item["id"] as? Int else { continue }
            let artistName = (item["artist"] as? [String: Any])?["name"] as? String ?? ""
            let pic = item["picUrl"] as? String ?? ""
            albums.append(Album(
                id: "netease-\(id)",
                name: item["name"] as? String ?? "",
                artistName: artistName,
                coverURL: pic.isEmpty ? nil : URL(string: pic),
                source: .netease,
                trackCount: item["size"] as? Int
            ))
        }
        return albums
    }

    /// 专辑内歌曲
    func albumSongs(albumID: Int) async throws -> [Song] {
        let json = try await request("/api/album", payload: ["id": albumID], crypto: "weapi")
        let list = json["songs"] as? [[String: Any]] ?? []
        return list.compactMap { Song(json: $0) }
    }

    // MARK: - 收藏

    /// 听歌排行（type=1 最近一周 / type=0 所有时间）
    /// 本周取 100 顶；累计上限 1000，并优先从 size 字段读取真实总数（避免总是显示 100）
    func playRecord(uid: Int, type: Int) async throws -> PlayRecordResult {
        let limit = type == 1 ? 100 : 1000
        let json = try await request("/api/v1/play/record", payload: ["uid": uid, "type": type, "limit": limit], crypto: "weapi")
        let key = type == 1 ? "weekData" : "allData"
        let sizeKey = type == 1 ? "weekDataSize" : "allDataSize"
        let list = json[key] as? [[String: Any]] ?? []
        let total = json[sizeKey] as? Int ?? list.count
        let items = list.compactMap { item -> PlayRecordItem? in
            guard let songJSON = item["song"] as? [String: Any], let song = Song(json: songJSON) else { return nil }
            let count = item["playCount"] as? Int ?? 0
            return PlayRecordItem(song: song, playCount: count)
        }
        return PlayRecordResult(items: items, totalCount: max(total, items.count))
    }

    func like(id: Int, liked: Bool) async throws -> Bool {
        let time = String(Int(Date().timeIntervalSince1970 * 1000))
        let payloads: [[String: Any]] = [
            ["alg": "itembased", "trackId": id, "like": liked, "time": time],
            ["trackId": id, "like": liked],
            ["songId": id, "like": liked]
        ]
        var lastCode = -1
        var lastError = ""
        for payload in payloads {
            do {
                let json = try await request("/api/song/like?t=\(liked)", payload: payload, crypto: "weapi")
                let code = json["code"] as? Int ?? -1
                lastCode = code
                if code == 200 {
                    return true
                }
                lastError = json["message"] as? String ?? json["msg"] as? String ?? ""
            } catch {
                lastError = error.localizedDescription
            }
        }
        BeansLogger.shared.log("网易云红心同步失败：id=\(id) liked=\(liked) code=\(lastCode) \(lastError)", level: .error)
        return false
    }

    // MARK: - 发现

    func topLists() async throws -> [TopList] {
        let json = try await request("/api/toplist/detail", payload: [:], crypto: "weapi")
        let list = json["list"] as? [[String: Any]] ?? []
        return list.prefix(12).compactMap(TopList.init(json:))
    }

    func dailyRecommend() async throws -> [Song] {
        let json = try await request("/api/v3/discovery/recommend/songs", payload: [:], crypto: "weapi")
        let data = json["data"] as? [String: Any] ?? [:]
        let songs = data["dailySongs"] as? [[String: Any]] ?? []
        return songs.compactMap(Song.init(json:))
    }

    /// 歌单广场（对应网易云「发现音乐-歌单广场」，默认热门排序）
    func playlistSquare(cat: String = "全部", order: String = "hot", limit: Int = 12) async throws -> [Playlist] {
        let json = try await request("/api/playlist/list", payload: ["cat": cat, "order": order, "limit": limit, "offset": 0, "total": true], crypto: "weapi")
        let list = json["playlists"] as? [[String: Any]] ?? []
        return list.compactMap(Playlist.init(json:))
    }

    /// 精品歌单（官方歌单广场默认内容，网易云编辑精选；对应 music.163.com/discover/playlist 的「精品歌单」）
    func highQualityPlaylists(cat: String = "全部", limit: Int = 18) async throws -> [Playlist] {
        let json = try await request("/api/playlist/highquality/list", payload: ["cat": cat, "limit": limit, "offset": 0, "total": true], crypto: "weapi")
        let list = json["playlists"] as? [[String: Any]] ?? []
        return list.compactMap(Playlist.init(json:))
    }

    /// 官方歌单分类（官网 discover/playlist 的分类标签；失败返回空数组，调用方回落内置分类）
    func playlistCatlist() async -> [String] {
        guard let json = try? await request("/api/playlist/catlist", payload: [:], crypto: "weapi") else { return [] }
        let sub = json["sub"] as? [[String: Any]] ?? []
        return sub.compactMap { $0["name"] as? String }
    }

    func personalizedPlaylists(limit: Int = 20) async throws -> [Playlist] {
        let json = try await request("/api/personalized/playlist", payload: ["limit": limit, "n": limit], crypto: "weapi")
        let list = json["result"] as? [[String: Any]] ?? []
        return list.compactMap(Playlist.init(personalizedJSON:))
    }

    func recommendResource() async throws -> [Playlist] {
        let json = try await request("/api/v1/discovery/recommend/resource", payload: [:], crypto: "weapi")
        let list = json["recommend"] as? [[String: Any]] ?? []
        return list.compactMap(Playlist.init(json:))
    }

    func recommendedHomePlaylists(loggedIn: Bool, limit: Int = 18) async -> [Playlist] {
        if loggedIn {
            async let recommend = try? recommendResource()
            async let personalized = try? personalizedPlaylists(limit: limit)
            let head = await recommend ?? []
            let tail = await personalized ?? []
            var seen = Set<Int>()
            return Array((head + tail).filter { seen.insert($0.id).inserted }.prefix(limit))
        }
        return (try? await personalizedPlaylists(limit: limit)) ?? []
    }

    // MARK: - 更多发现

    func hotSearch() async throws -> [String] {
        let json = try await request("/api/search/hot", payload: ["type": 1111], crypto: "weapi")
        let hots = json["result"] as? [String: Any] ?? [:]
        let list = hots["hots"] as? [[String: Any]] ?? []
        return list.compactMap { $0["first"] as? String }.prefix(10).map { $0 }
    }

    func newSongs(limit: Int = 10) async throws -> [Song] {
        let json = try await request("/api/personalized/newsong", payload: ["type": 0, "limit": limit], crypto: "weapi")
        let list = json["result"] as? [[String: Any]] ?? []
        var songs: [Song] = []
        for item in list {
            if let songJSON = item["song"] as? [String: Any], let song = Song(json: songJSON) {
                songs.append(song)
            } else if let song = Song(json: item) {
                songs.append(song)
            }
        }
        return songs
    }

    func topPlaylists(limit: Int = 10) async throws -> [Playlist] {
        let json = try await request("/api/top/playlist", payload: ["limit": limit, "order": "hot", "cat": "全部", "total": true], crypto: "weapi")
        let list = json["playlists"] as? [[String: Any]] ?? []
        return list.compactMap(Playlist.init(json:))
    }

    func simiSongs(id: Int) async throws -> [Song] {
        let json = try await request("/api/simi/song", payload: ["songid": id], crypto: "weapi")
        let list = json["songs"] as? [[String: Any]] ?? []
        return list.compactMap(Song.init(json:))
    }

    func intelligenceList(songID: Int, playlistID: Int, count: Int = 30) async throws -> [Song] {
        let json = try await request(
            "/api/playmode/intelligence/list",
            payload: [
                "songId": songID,
                "type": "fromPlayOne",
                "playlistId": playlistID,
                "startMusicId": songID,
                "count": count
            ],
            crypto: "weapi"
        )
        let data = json["data"] as? [[String: Any]] ?? []
        return data.compactMap { item in
            if let songInfo = item["songInfo"] as? [String: Any] {
                return Song(json: songInfo)
            }
            return Song(json: item)
        }
    }

    func personalFM(limit: Int = 12) async throws -> [Song] {
        var songs: [Song] = []
        var seen = Set<String>()
        let batchCount = max(1, Int(ceil(Double(limit) / 3.0)))
        for _ in 0..<batchCount {
            let json = try await request("/api/v1/radio/get", payload: [:], crypto: "weapi")
            let list = json["data"] as? [[String: Any]] ?? []
            let batch = list.compactMap(Song.init(json:))
            for song in batch where seen.insert(song.identityKey).inserted {
                songs.append(song)
                if songs.count >= limit { return songs }
            }
            if batch.isEmpty { break }
        }
        return songs
    }

    // MARK: - 歌单编辑

    func createPlaylist(name: String) async throws -> Int {
        let json = try await request("/api/playlist/create", payload: ["name": name, "privacy": 0], crypto: "weapi")
        guard let id = json["id"] as? Int else {
            throw NetEaseError.unknown("创建歌单失败")
        }
        return id
    }

    func addToPlaylist(playlistID: Int, songIDs: [Int]) async throws -> Bool {
        let tracks = "[" + songIDs.map(String.init).joined(separator: ",") + "]"
        let json = try await request("/api/playlist/manipulate/tracks", payload: ["op": "add", "pid": playlistID, "tracks": tracks], crypto: "weapi")
        return (json["code"] as? Int) == 200
    }

    func removeFromPlaylist(playlistID: Int, songIDs: [Int]) async throws -> Bool {
        let tracks = "[" + songIDs.map(String.init).joined(separator: ",") + "]"
        let json = try await request("/api/playlist/manipulate/tracks", payload: ["op": "del", "pid": playlistID, "tracks": tracks], crypto: "weapi")
        return (json["code"] as? Int) == 200
    }

    func deletePlaylist(id: Int) async throws -> Bool {
        let json = try await request("/api/playlist/remove", payload: ["ids": "[" + String(id) + "]"], crypto: "weapi")
        return (json["code"] as? Int) == 200
    }
}

enum NetEaseError: LocalizedError {
    case network
    case httpStatus(Int, String)
    case decoding(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .network: return "网络连接失败，请检查网络"
        case .httpStatus(let code, let snippet):
            return snippet.isEmpty ? "服务器响应异常（\(code)）" : "服务器响应异常（\(code)）\(snippet)"
        case .decoding(let snippet):
            return snippet.isEmpty ? "数据解析失败" : "数据解析失败：\(snippet)"
        case .unknown(let message): return message
        }
    }
}
