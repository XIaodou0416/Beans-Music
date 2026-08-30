import Foundation

/// QQ 音乐搜索类型（musicu search_type：0 单曲 / 1 歌手 / 2 专辑 / 3 歌单 / 4 MV / 7 歌词 / 8 用户）
enum QQSearchType: Int {
    case song = 0
    case artist = 1
    case album = 2
}

/// QQ 音乐接口（搜索 / 播放地址 / 歌词 / 热搜）
/// 参考 wp_MusicApi（https://github.com/GitHub-ZC/wp_MusicApi）逆向结论：
/// - 歌曲搜索改用 client_search_cp（t=0），该接口对家庭/移动/数据中心网络均可用；
///   歌手/专辑搜索使用 musicu.fcg POST JSON（search_type 1/2），专辑空结果时自动用 client_search_cp t=8 兜底。
/// - vkey 播放地址经 musicu.fcg 获取，VIP 歌曲返回空；部分数据中心 IP 会被风控返回空，家庭网络正常。
final class QQMusicAPI {
    static let shared = QQMusicAPI()
    /// QQ「我的喜欢」不是“创建歌单”列表中的普通歌单，使用稳定占位 ID 进入专用加载流程。
    static let qqLikedPlaylistID = -201
    private static let qqLikedCoverURL = URL(string: "https://y.gtimg.cn/mediastyle/global/img/cover_like.png")

    private let base = "https://u.y.qq.com/cgi-bin/musicu.fcg"
    private let searchBase = "https://c.y.qq.com/soso/fcgi-bin/search_for_qq_cp"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    // MARK: - 基础请求

    private func get(_ urlString: String, referer: String = "https://y.qq.com/", cookie: String = "") async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw NetEaseError.unknown("请求地址无效") }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 QQMusic/9.0.5", forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue(cookie.isEmpty ? "uin=0; qqmusic_fromtag=66" : cookie, forHTTPHeaderField: "Cookie")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NetEaseError.network
        }
        guard let json = parseJSON(data) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(120) ?? ""
            throw NetEaseError.decoding(String(snippet))
        }
        return json
    }

    /// musicu.fcg 统一入口：POST JSON body（与 wp_MusicApi 一致）；登录后附加 QQ Cookie
    private func musicu(_ payload: [String: Any], cookie: String = "", timeout: TimeInterval = 6) async throws -> [String: Any] {
        guard let body = try? JSONSerialization.data(withJSONObject: payload),
              let url = URL(string: base) else {
            throw NetEaseError.unknown("请求参数错误")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // musicu 偶发挂起/风控，搜索保持短超时，歌单同步允许更长时间完成回退请求。
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        if !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NetEaseError.network
        }
        guard let json = parseJSON(data) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(120) ?? ""
            throw NetEaseError.decoding(String(snippet))
        }
        return json
    }

    /// 表单 POST（fcg 老接口统一走这里，如 H5 评论接口）
    private func postForm(_ urlString: String, body: [String: Any], referer: String = "https://y.qq.com/", cookie: String = "") async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw NetEaseError.unknown("请求地址无效") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 QQMusic/9.0.5", forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue(cookie.isEmpty ? "uin=0; qqmusic_fromtag=66" : cookie, forHTTPHeaderField: "Cookie")
        var comps = URLComponents()
        comps.queryItems = body.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
        request.httpBody = comps.query?.data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NetEaseError.network
        }
        guard let json = parseJSON(data) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(120) ?? ""
            throw NetEaseError.decoding(String(snippet))
        }
        return json
    }

    /// 兼容纯 JSON 与 JSONP（`callback({...})`）两种响应；QQ 部分老接口会前置 `while(1);` 防护前缀
    private func parseJSON(_ data: Data) -> [String: Any]? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        guard var text = String(data: data, encoding: .utf8) else { return nil }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("while(1);") {
            text = String(text.dropFirst("while(1);".count))
        }
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }
        let slice = text[start...end]
        return try? JSONSerialization.jsonObject(with: Data(slice.utf8)) as? [String: Any]
    }

    private static func photoURL(_ mid: String?, size: String = "300x300") -> URL? {
        guard let mid, !mid.isEmpty else { return nil }
        return URL(string: "https://y.gtimg.cn/music/photo_new/T002R\(size)M000\(mid).jpg")
    }

    /// 歌手头像（T001 歌手模板；T002 专辑模板对歌手 mid 会 404，搜索歌手必须用 T001）
    private static func singerPhotoURL(_ mid: String?, size: String = "300x300") -> URL? {
        guard let mid, !mid.isEmpty else { return nil }
        return URL(string: "https://y.gtimg.cn/music/photo_new/T001R\(size)M000\(mid).jpg")
    }

    private static func normalizedQQImageURL(_ raw: Any?) -> URL? {
        guard var value = raw as? String else { return nil }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        value = value.replacingOccurrences(of: "\\/", with: "/")
        if value.hasPrefix("http://") {
            value = "https://" + String(value.dropFirst(7))
        } else if value.hasPrefix("//") {
            value = "https:" + value
        } else if value.hasPrefix("/") {
            value = "https://y.gtimg.cn" + value
        } else if !value.hasPrefix("https://") {
            value = "https://y.gtimg.cn/" + value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return URL(string: value)
    }

    private func musicuSearchPayload(keyword: String, limit: Int, type: QQSearchType) -> [String: Any] {
        [
            "comm": ["ct": 19, "cv": 1859, "uin": "0", "format": "json"],
            "req_1": [
                "module": "music.search.SearchCgiService",
                "method": "DoSearchForQQMusicDesktop",
                "param": [
                    "query": keyword,
                    "num_per_page": limit,
                    "page_num": 1,
                    "search_type": type.rawValue,
                    "grp": 1,
                ],
            ],
        ]
    }

    /// search_for_qq_cp 搜索 URL（未登录可用；t：0 单曲 / 8 专辑）
    private func clientSearchURL(keyword: String, limit: Int, type: Int, page: Int = 1) -> URL? {
        var comps = URLComponents(string: searchBase)
        comps?.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "w", value: keyword),
            URLQueryItem(name: "n", value: "\(limit)"),
            URLQueryItem(name: "p", value: "\(max(page, 1))"),
            URLQueryItem(name: "t", value: "\(type)"),
        ]
        return comps?.url
    }

    // MARK: - 搜索

    /// 搜索歌曲（client_search_cp，本机与手机网络均可）
    func searchSongs(keyword: String, limit: Int = 30, offset: Int = 0) async throws -> [Song] {
        let pageSize = max(limit, 1)
        let page = max(offset, 0) / pageSize + 1
        guard let url = clientSearchURL(keyword: keyword, limit: pageSize, type: 0, page: page) else {
            throw NetEaseError.unknown("搜索地址无效")
        }
        let json = try await get(url.absoluteString, referer: "https://y.qq.com/portal/player.html")
        let data = json["data"] as? [String: Any] ?? [:]
        let song = data["song"] as? [String: Any] ?? [:]
        let list = song["list"] as? [[String: Any]] ?? []
        var songs: [Song] = []
        for item in list {
            guard let songid = item["songid"] as? Int, let mid = item["songmid"] as? String else { continue }
            let singer = (item["singer"] as? [[String: Any]]) ?? []
            let artists = singer.compactMap { $0["name"] as? String }.joined(separator: " / ")
            let albumMid = item["albummid"] as? String ?? item["albumMID"] as? String
            let interval = (item["interval"] as? Int) ?? 0
            let pay = item["pay"] as? [String: Any]
            let fee = (item["fee"] as? Int) ?? (pay?["pay_play"] as? Int) ?? (pay?["payplay"] as? Int) ?? 0
            let file = item["file"] as? [String: Any]
            let mediaMid = file?["media_mid"] as? String
                ?? item["strMediaMid"] as? String
                ?? item["media_mid"] as? String
            songs.append(Song(
                id: songid,
                name: item["songname"] as? String ?? "",
                artists: artists,
                album: item["albumname"] as? String ?? item["albumName"] as? String ?? "",
                coverURL: Self.photoURL(albumMid),
                duration: TimeInterval(interval),
                source: .qq,
                qqMid: mid,
                qqMediaMid: mediaMid,
                fee: fee
            ))
        }
        return songs
    }

    /// 搜索歌手（musicu search_type=1 为主，字段 singerName/singerMID；musicu 被风控返回 2001 时用 smartbox_new 兜底）
    func searchArtists(keyword: String, limit: Int = 30) async throws -> [Artist] {
        if let json = try? await musicu(musicuSearchPayload(keyword: keyword, limit: limit, type: .artist)) {
            let list = nestedArray(json, path: ["req_1", "data", "body", "singer", "list"])
            var artists: [Artist] = []
            for item in list {
                let name = item["singerName"] as? String ?? (item["name"] as? String ?? (item["title"] as? String ?? ""))
                guard !name.isEmpty else { continue }
                let mid = item["singerMID"] as? String ?? (item["mid"] as? String)
                let numericID = item["singerID"] as? Int ?? (item["id"] as? Int ?? 0)
                artists.append(Artist(
                    id: mid ?? "qq-\(numericID)-\(name)",
                    name: name,
                    coverURL: Self.singerPhotoURL(mid),
                    source: .qq
                ))
            }
            if !artists.isEmpty { return artists }
        }
        // 兜底：smartbox_new.fcg 联想接口（含歌手/专辑，数据中心与移动网络均可用）
        if let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "https://c.y.qq.com/splcloud/fcgi-bin/smartbox_new.fcg?format=json&s_from=pc_header&type=1&key=\(encoded)"),
           let json = try? await get(url.absoluteString) {
            let singer = (json["data"] as? [String: Any])?["singer"] as? [String: Any] ?? [:]
            let list = singer["itemlist"] as? [[String: Any]] ?? []
            var artists: [Artist] = []
            for item in list.prefix(limit) {
                let name = item["name"] as? String ?? ""
                guard !name.isEmpty else { continue }
                let mid = item["mid"] as? String
                let numericID = item["id"] as? String ?? ""
                artists.append(Artist(
                    id: mid ?? "qq-\(numericID)-\(name)",
                    name: name,
                    coverURL: Self.normalizedQQImageURL(item["pic"]) ?? Self.singerPhotoURL(mid),
                    source: .qq
                ))
            }
            if !artists.isEmpty { return artists }
        }
        // 兜底 2：歌曲搜索结果里的歌手名去重（保证关键词搜索始终能出歌手）
        if let songs = try? await searchSongs(keyword: keyword, limit: 40) {
            var seen = Set<String>()
            var artists: [Artist] = []
            for song in songs {
                for part in song.artists.components(separatedBy: " / ") {
                    let name = part.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty, !seen.contains(name) else { continue }
                    seen.insert(name)
                    artists.append(Artist(id: "qq-name-\(name)", name: name, coverURL: nil, source: .qq))
                    if artists.count >= limit { break }
                }
                if artists.count >= limit { break }
            }
            if !artists.isEmpty { return artists }
        }
        return []
    }

    /// 搜索专辑（client_search_cp t=8 为主，与歌曲搜索同源、数据中心/移动网络均可用；musicu search_type=2 常被风控返回 2001 作为次选）
    func searchAlbums(keyword: String, limit: Int = 30) async throws -> [Album] {
        if let url = clientSearchURL(keyword: keyword, limit: limit, type: 8),
           let json = try? await get(url.absoluteString, referer: "https://y.qq.com/portal/player.html") {
            let data = json["data"] as? [String: Any] ?? [:]
            let album = data["album"] as? [String: Any] ?? [:]
            let list = album["list"] as? [[String: Any]] ?? []
            if !list.isEmpty {
                return parseAlbumItems(list)
            }
        }
        if let json = try? await musicu(musicuSearchPayload(keyword: keyword, limit: limit, type: .album)) {
            let list = nestedArray(json, path: ["req_1", "data", "body", "album", "list"])
            if !list.isEmpty {
                return parseAlbumItems(list)
            }
        }
        return []
    }

    private func parseAlbumItems(_ items: [[String: Any]]) -> [Album] {
        var albums: [Album] = []
        for item in items {
            let name = item["name"] as? String ?? (item["albumname"] as? String ?? item["albumName"] as? String ?? "")
            guard !name.isEmpty else { continue }
            let mid = item["mid"] as? String ?? (item["albummid"] as? String ?? item["albumMID"] as? String)
            let singer = (item["singer"] as? [[String: Any]]) ?? []
            var artistName = singer.compactMap { $0["name"] as? String }.joined(separator: " / ")
            if artistName.isEmpty { artistName = item["singerName"] as? String ?? "" }
            let numericID = item["id"] as? Int ?? 0
            albums.append(Album(
                id: mid ?? "qq-album-\(numericID)-\(name)",
                name: name,
                artistName: artistName,
                coverURL: Self.photoURL(mid),
                source: .qq,
                trackCount: item["total"] as? Int
            ))
        }
        return albums
    }

    /// QQ 音乐热搜词
    func hotKeys(limit: Int = 10) async throws -> [String] {
        let url = "https://c.y.qq.com/splcloud/fcgi-bin/gethotkey.fcg?format=json&inCharset=utf8&outCharset=utf-8"
        let json = try await get(url)
        let data = json["data"] as? [String: Any] ?? [:]
        let hots = data["hotkey"] as? [[String: Any]] ?? []
        return hots.compactMap { $0["k"] as? String }.prefix(limit).map { $0 }
    }

    // MARK: - 歌单管理（创建 / 删除 / 我喜欢）

    /// 创建歌单（create_playlist.fcg，需登录；code 0 成功 / 21 重名 / 1 未登录）
    /// URL 与表单同时携带 format=json/outCharset，兼容 while(1); 与 JSONP 响应，code 支持 Int/String 两种形态
    func createPlaylist(name: String) async throws -> Bool {
        let qqAuth = QQMusicAuth.shared
        guard qqAuth.isLoggedIn else { return false }
        let gtk = qqAuth.gtk
        let json = try await postForm("https://c.y.qq.com/splcloud/fcgi-bin/create_playlist.fcg?g_tk=\(gtk)&format=json&inCharset=utf8&outCharset=utf-8", body: [
            "loginUin": qqAuth.rawUin,
            "hostUin": 0,
            "format": "json",
            "inCharset": "utf8",
            "outCharset": "utf-8",
            "notice": 0,
            "platform": "yqq",
            "needNewCode": 0,
            "g_tk": gtk,
            "uin": qqAuth.rawUin,
            "name": name,
            "show": 1,
            "formsender": 1,
            "utf8": 1,
            "qzreferrer": "https://y.qq.com/portal/profile.html#sub=other&tab=create&",
        ], cookie: qqAuth.cookieHeader)
        let code = Self.extractCode(json) ?? -1
        return code == 0
    }

    /// 宽松提取接口 code（兼容 Int / String / "code":"0" 等形态）
    private static func extractCode(_ json: [String: Any]) -> Int? {
        if let n = json["code"] as? Int { return n }
        if let s = json["code"] as? String, let n = Int(s) { return n }
        if let n = json["ret"] as? Int { return n }
        if let s = json["ret"] as? String, let n = Int(s) { return n }
        return nil
    }

    /// 删除歌单（fcg_fav_modsongdir.fcg，需登录；返回 JSONP，parseJSON 自动剥离）
    func deletePlaylist(dirid: Int) async throws -> Bool {
        let qqAuth = QQMusicAuth.shared
        guard qqAuth.isLoggedIn else { return false }
        let gtk = qqAuth.gtk
        let json = try await postForm("https://c.y.qq.com/splcloud/fcgi-bin/fcg_fav_modsongdir.fcg?g_tk=\(gtk)", body: [
            "loginUin": qqAuth.rawUin,
            "hostUin": 0,
            "format": "fs",
            "inCharset": "GB2312",
            "outCharset": "gb2312",
            "notice": 0,
            "platform": "yqq",
            "needNewCode": 0,
            "g_tk": gtk,
            "uin": qqAuth.rawUin,
            "delnum": 1,
            "deldirids": dirid,
            "forcedel": 1,
            "formsender": 1,
            "source": 103,
        ], cookie: qqAuth.cookieHeader)
        let code = json["code"] as? Int ?? -1
        return code == 0
    }

    /// 我喜欢（红心）歌单歌曲列表（dirid=201 解析真实歌单 ID，再拉歌单详情）
    func favoriteSongs(limit: Int = 100) async throws -> [Song] {
        let qqAuth = QQMusicAuth.shared
        guard qqAuth.isLoggedIn else { return [] }
        let cookieCandidates = [qqAuth.playlistCookieHeader, qqAuth.cookieHeader]
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, value in
                if !result.contains(value) { result.append(value) }
            }
        guard let mapid = await likedPlaylistID(qqAuth: qqAuth, cookies: cookieCandidates), mapid > 0 else {
            BeansLogger.shared.log("QQ 我的喜欢歌单解析失败：未找到真实歌单 ID", level: .error)
            return []
        }
        for cookie in cookieCandidates {
            let songs = try await playlistSongs(listID: mapid, preferredCookie: cookie, limit: limit)
            if !songs.isEmpty { return songs }
        }
        return try await playlistSongs(listID: mapid, preferredCookie: nil, limit: limit)
    }

    /// 解析「我的喜欢」的真实歌单 ID。该歌单通常不会出现在 profile/create 的创建歌单列表中，
    /// 需要通过 dirid=201 专用接口或 GetUserPlaylist order=3 单独获取。
    private func likedPlaylistID(qqAuth: QQMusicAuth, cookies: [String]) async -> Int? {
        let favURL = "https://c.y.qq.com/splcloud/fcgi-bin/fcg_musiclist_getmyfav.fcg?dirid=201&dirinfo=1&g_tk=\(qqAuth.gtk)&format=json&utf8=1"
        for cookie in cookies {
            guard let favJson = try? await get(favURL, referer: "https://y.qq.com/n/yqq/playlist", cookie: cookie) else { continue }
            if let id = Self.likedMapID(favJson), id > 0 { return id }

            let data = favJson["data"] as? [String: Any] ?? favJson
            if let first = (data["cdlist"] as? [[String: Any]])?.first {
                let id = Self.integerValue(first["dissid"] ?? first["diss_id"])
                if id > 0 { return id }
            }
        }

        let identities = qqAuth.playlistIdentityCandidates
        for identity in identities {
            let numericUin = Int(identity) ?? 0
            let payload: [String: Any] = [
                "comm": [
                    "ct": 24,
                    "cv": 0,
                    "uin": numericUin,
                    "g_tk": qqAuth.gtk,
                    "platform": "yqq",
                ],
                "req_1": [
                    "module": "music.musichallSong.PlayListDataServer",
                    "method": "GetUserPlaylist",
                    "param": [
                        "uin": numericUin,
                        "sin": 0,
                        "size": 100,
                        "order": 3,
                    ],
                ],
            ]
            for cookie in cookies {
                guard let json = try? await musicu(payload, cookie: cookie, timeout: 15) else { continue }
                for item in playlistArray(from: json) {
                    let id = Self.integerValue(item["dissid"] ?? item["diss_id"] ?? item["tid"])
                    if id > 0 { return id }
                }
            }
        }
        return nil
    }

    /// fcg_musiclist_getmyfav 的 map 可能是标量、嵌套在 data 中，或是 {"201": 真实歌单 ID}。
    private static func likedMapID(_ json: [String: Any]) -> Int? {
        let data = json["data"] as? [String: Any] ?? [:]
        for value in [json["map"], json["mapid"], json["id"], data["map"], data["mapid"], data["id"]] {
            if let dict = value as? [String: Any] {
                let preferredID = integerValue(dict["201"])
                if preferredID > 0 { return preferredID }
                if let id = dict.values.lazy.map({ integerValue($0) }).first(where: { $0 > 0 }) { return id }
            } else {
                let id = integerValue(value)
                if id > 0 { return id }
            }
        }
        return nil
    }

    // MARK: - 红心收藏

    /// 红心 / 取消红心（musicu.fcg music.srfDissong do_dissong_op，借鉴 qqmusicapi 逆向实现）
    func like(songmid: String, liked: Bool) async throws -> Bool {
        let qqAuth = QQMusicAuth.shared
        let payload: [String: Any] = [
            "comm": [
                "ct": 24,
                "cv": 0,
                "uin": qqAuth.isLoggedIn ? qqAuth.uin : "0",
                "g_tk": 5381,
                "platform": "yqq",
                "format": "json",
            ],
            "req_0": [
                "module": "music.srfDissong",
                "method": "do_dissong_op",
                "param": [
                    "songmid": [songmid],
                    "op": liked ? 1 : 2,
                ],
            ],
        ]
        let json = try await musicu(payload, cookie: qqAuth.isLoggedIn ? qqAuth.cookieHeader : "")
        let req = json["req_0"] as? [String: Any]
        let code = req?["code"] as? Int ?? -1
        return code == 0
    }

    // MARK: - 播放 / 歌词

    /// 指定音质获取播放地址（br: M800=320kbps 高质量 / M500=128kbps 低质量），下载用
    func songURL(songmid: String, mediaMid: String? = nil, br: String) async throws -> String? {
        let qqAuth = QQMusicAuth.shared
        let uin = qqAuth.isLoggedIn ? qqAuth.uin : "0"
        let loginKey = qqAuth.isLoggedIn ? qqAuth.loginKey : ""
        let guid = Self.deviceGuid
        let resolvedMediaMid = await resolveMediaMid(songmid: songmid, provided: mediaMid, qqAuth: qqAuth)
        return try await vkeyURL(songmid: songmid, mediaMid: resolvedMediaMid, br: br, uin: uin, loginKey: loginKey, guid: guid, qqAuth: qqAuth)
    }

    /// 通过 vkey 获取 QQ 音乐播放地址（对齐 wp_MusicApi：GET + data JSON + filename + CDN 分发）
    /// 登录后携带 uin/loginKey/Cookie；先试 320kbps(M800)，拿不到再退 128kbps(M500)
    func songURL(songmid: String, mediaMid: String? = nil) async throws -> String? {
        let qqAuth = QQMusicAuth.shared
        let uin = qqAuth.isLoggedIn ? qqAuth.uin : "0"
        let loginKey = qqAuth.isLoggedIn ? qqAuth.loginKey : ""
        let guid = Self.deviceGuid
        let resolvedMediaMid = await resolveMediaMid(songmid: songmid, provided: mediaMid, qqAuth: qqAuth)
        // 独家 VIP 曲库并不保证所有 MP3 档位都存在；按 320K、128K、M4A 依次验证回退。
        for br in ["M800", "M500", "C400"] {
            if let url = try await vkeyURL(songmid: songmid, mediaMid: resolvedMediaMid, br: br, uin: uin, loginKey: loginKey, guid: guid, qqAuth: qqAuth) {
                return url
            }
        }
        return nil
    }

    /// 搜索接口经常不返回 file.media_mid；独家 VIP 歌曲的 media_mid 又常与 songmid 不同，必须补拉详情。
    private func resolveMediaMid(songmid: String, provided: String?, qqAuth: QQMusicAuth) async -> String {
        if let provided, !provided.isEmpty { return provided }
        let payload: [String: Any] = [
            "comm": ["ct": 24, "cv": 0, "uin": qqAuth.isLoggedIn ? qqAuth.uin : "0"],
            "songinfo": [
                "module": "music.pf_song_detail_svr",
                "method": "get_song_detail_yqq",
                "param": ["song_mid": songmid],
            ],
        ]
        guard let json = try? await musicu(payload, cookie: qqAuth.isLoggedIn ? qqAuth.cookieHeader : ""),
              let block = json["songinfo"] as? [String: Any],
              let data = block["data"] as? [String: Any],
              let track = data["track_info"] as? [String: Any],
              let file = track["file"] as? [String: Any],
              let mediaMid = file["media_mid"] as? String,
              !mediaMid.isEmpty else {
            BeansLogger.shared.log("QQ 歌曲详情未返回 media_mid，回退 songmid", level: .debug)
            return songmid
        }
        BeansLogger.shared.log("QQ 歌曲详情：media_mid=已获取 是否不同=\(mediaMid == songmid ? "否" : "是")", level: .debug)
        return mediaMid
    }

    /// 单次 vkey 请求（GET musicu.fcg，data 参数格式与 wp_MusicApi 完全一致）
    private func vkeyURL(songmid: String, mediaMid: String?, br: String, uin: String, loginKey: String, guid: String, qqAuth: QQMusicAuth) async throws -> String? {
        // 音质与扩展名：M500/M800 为 mp3，F000（无损）为 flac
        let ext: String
        if br.hasPrefix("F") {
            ext = "flac"
        } else if br.hasPrefix("C") {
            ext = "m4a"
        } else {
            ext = "mp3"
        }
        let preferredMid = (mediaMid?.isEmpty == false ? mediaMid : nil) ?? songmid
        // QQ 官方 Web 格式为 prefix + songmid + media_mid；其余格式用于兼容不同年代接口。
        var filenames = [
            "\(br)\(songmid)\(preferredMid).\(ext)",
            "\(br)\(preferredMid).\(ext)",
            "\(br)\(songmid)\(songmid).\(ext)",
            "\(br)\(songmid).\(ext)",
        ]
        var seenFilenames = Set<String>()
        filenames = filenames.filter { seenFilenames.insert($0).inserted }
        var param: [String: Any] = [
            "filename": filenames,
            "guid": guid,
            "songmid": Array(repeating: songmid, count: filenames.count),
            "songtype": Array(repeating: 0, count: filenames.count),
            "uin": uin,
            "loginflag": 1,
            "platform": "20",
        ]
        var comm: [String: Any] = ["uin": Int(uin) ?? 0, "format": "json", "ct": loginKey.isEmpty ? 24 : 19, "cv": 0]
        if !loginKey.isEmpty { comm["authst"] = loginKey }
        let payload: [String: Any] = [
            "comm": comm,
            "req": [
                "module": "CDN.SrfCdnDispatchServer",
                "method": "GetCdnDispatch",
                "param": ["guid": guid, "calltype": 0, "userip": ""],
            ],
            "req_0": [
                "module": "vkey.GetVkeyServer",
                "method": "CgiGetVkey",
                "param": param,
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let dataString = String(data: data, encoding: .utf8),
              var comps = URLComponents(string: "https://u.y.qq.com/cgi-bin/musicu.fcg") else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "data", value: dataString),
        ]
        guard let url = comps.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:80.0) Gecko/20100101 Firefox/80.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue(qqAuth.isLoggedIn ? qqAuth.cookieHeader : "uin=0; qqmusic_fromtag=66", forHTTPHeaderField: "Cookie")
        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = parseJSON(responseData),
              let req = json["req_0"] as? [String: Any],
              let reqData = req["data"] as? [String: Any],
              let infos = reqData["midurlinfo"] as? [[String: Any]] else { return nil }
        let playableInfos = infos.filter { ($0["purl"] as? String)?.isEmpty == false }
        guard !playableInfos.isEmpty else {
            let result = infos.first?["result"] ?? "unknown"
            BeansLogger.shared.log("QQ vkey 无可播地址：音质=\(br) result=\(result) 已登录=\(qqAuth.isLoggedIn ? "是" : "否")", level: .debug)
            return nil
        }
        let sips = reqData["sip"] as? [String] ?? []
        let cdnBases = sips.isEmpty ? ["https://isure.stream.qqmusic.qq.com/"] : sips
        for info in playableInfos {
            guard let purl = info["purl"] as? String, !purl.isEmpty else { continue }
            let candidateURLs: [String]
            if purl.hasPrefix("http") {
                candidateURLs = [purl]
            } else {
                candidateURLs = cdnBases.map { base in
                    let secureBase = base.hasPrefix("http://") ? "https://" + String(base.dropFirst("http://".count)) : base
                    return secureBase + purl
                }
            }
            for candidate in candidateURLs {
                guard let url = URL(string: candidate) else { continue }
                if await probeAudioURL(url, cookie: qqAuth.isLoggedIn ? qqAuth.cookieHeader : "") {
                    let filename = info["filename"] as? String ?? "unknown"
                    BeansLogger.shared.log("QQ 音频地址验证成功：音质=\(br) 文件=\(filename)", level: .debug)
                    return candidate
                }
            }
        }
        BeansLogger.shared.log("QQ vkey 返回地址但 CDN 验证失败：音质=\(br) 候选=\(playableInfos.count)", level: .debug)
        return nil
    }

    /// 在交给 AVPlayer 前验证 CDN，避免 purl 非空但实际 404 的假成功地址。
    private func probeAudioURL(_ url: URL, cookie: String) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue("bytes=0-2047", forHTTPHeaderField: "Range")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:80.0) Gecko/20100101 Firefox/80.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        if !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 || http.statusCode == 206,
              !data.isEmpty else { return false }
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        return !contentType.contains("text/html") && !contentType.contains("application/json")
    }

    /// 固定设备 GUID（持久化）：vkey 与 guid 强相关，随机 guid 会导致播放地址失效
    private static var deviceGuid: String {
        let key = "beans.qqmusic.guid.v1"
        if let saved = UserDefaults.standard.string(forKey: key), !saved.isEmpty {
            return saved
        }
        let guid = String(format: "%09d", Int.random(in: 100000000...999999999))
        UserDefaults.standard.set(guid, forKey: key)
        return guid
    }

    /// QQ 音乐歌词（LRC 文本）
    func lyric(songmid: String) async throws -> String? {
        guard let mid = songmid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        let url = "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=\(mid)&format=json&nobase64=1&g_tk=5381"
        let json = try await get(url, referer: "https://y.qq.com/portal/player.html")
        guard let lyric = json["lyric"] as? String, !lyric.isEmpty else { return nil }
        return lyric
    }

    // MARK: - 评论区 / 排行榜 / 推荐 / 歌单

    /// QQ 音乐评论分页（fcg_global_comment_h5；topid 必须用数字 songid 并带 cid/reqtype，用 songmid 会返回空）
    /// pagenum 从 0 开始；热评只在第一页返回，翻页只取普通评论
    struct QQCommentPage {
        let comments: [SongComment]
        let total: Int
    }

    func comments(songID: Int, limit: Int = 25, pagenum: Int = 0) async throws -> QQCommentPage {
        let json = try await postForm("https://c.y.qq.com/base/fcgi-bin/fcg_global_comment_h5.fcg?format=json&cid=205360772&reqtype=2", body: [
            "biztype": 1,
            "topid": songID,
            "LoginUin": 0,
            "cmd": 8,
            "pagenum": max(pagenum, 0),
            "pagesize": min(max(limit, 1), 25)
        ])
        let hot = pagenum == 0 ? (((json["hot_comment"] as? [String: Any])?["commentlist"] as? [[String: Any]]) ?? []) : []
        let normal = ((json["comment"] as? [String: Any])?["commentlist"] as? [[String: Any]]) ?? []
        let commentTotal = ((json["comment"] as? [String: Any])?["commenttotal"] as? Int) ?? 0
        var seen = Set<String>()
        var result: [SongComment] = []
        for item in hot + normal {
            let rootID = item["rootcommentid"] as? String ?? ""
            let commentID = item["commentid"] as? String ?? ""
            let key = rootID + "_" + commentID
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            var content = Self.decodeCommentEmoji(item["rootcommentcontent"] as? String ?? "")
            content = content.replacingOccurrences(of: "\\n", with: "\n")
            guard !content.isEmpty else { continue }
            var nick = item["nick"] as? String ?? ""
            if nick.isEmpty { nick = item["rootcommentnick"] as? String ?? "" }
            if nick.hasPrefix("@") { nick = String(nick.dropFirst()) }
            let avatar = item["avatarurl"] as? String ?? ""
            let time = item["time"] as? TimeInterval ?? 0
            result.append(SongComment(
                id: key.hashValue,
                content: content,
                nickname: nick,
                avatarURL: avatar.isEmpty ? nil : URL(string: avatar),
                time: time > 0 ? Date(timeIntervalSince1970: time) : Date(),
                likedCount: item["praisenum"] as? Int ?? 0,
                isHot: true
            ))
        }
        return QQCommentPage(comments: result, total: commentTotal)
    }

    /// QQ 评论表情解码（[em]eXXXXXX[/em] → 对应 Unicode 表情）
    private static let commentEmojis: [String: String] = [
        "e400846": "😘",
        "e400874": "😴",
        "e400825": "😃",
        "e400847": "😙",
        "e400835": "😍",
        "e400873": "😳",
        "e400836": "😎",
        "e400867": "😭",
        "e400832": "😊",
        "e400837": "😏",
        "e400875": "😫",
        "e400831": "😉",
        "e400855": "😡",
        "e400823": "😄",
        "e400862": "😨",
        "e400844": "😖",
        "e400841": "😓",
        "e400830": "😈",
        "e400828": "😆",
        "e400833": "😋",
        "e400822": "😀",
        "e400843": "😕",
        "e400829": "😇",
        "e400824": "😂",
        "e400834": "😌",
        "e400877": "😷",
        "e400132": "🍉",
        "e400181": "🍺",
        "e401067": "☕️",
        "e400186": "🥧",
        "e400343": "🐷",
        "e400116": "🌹",
        "e400126": "🍃",
        "e400613": "💋",
        "e401236": "❤️",
        "e400622": "💔",
        "e400637": "💣",
        "e400643": "💩",
        "e400773": "🔪",
        "e400102": "🌛",
        "e401328": "🌞",
        "e400420": "👏",
        "e400914": "🙌",
        "e400408": "👍",
        "e400414": "👎",
        "e401121": "✋",
        "e400396": "👋",
        "e400384": "👉",
        "e401115": "✊",
        "e400402": "👌",
        "e400905": "🙈",
        "e400906": "🙉",
        "e400907": "🙊",
        "e400562": "👻",
        "e400932": "🙏",
        "e400644": "💪",
        "e400611": "💉",
        "e400185": "🎁",
        "e400655": "💰",
        "e400325": "🐥",
        "e400612": "💊",
        "e400198": "🎉",
        "e401685": "⚡️",
        "e400631": "💝",
        "e400768": "🔥",
        "e400432": "👑",
    ]
    private static func decodeCommentEmoji(_ raw: String) -> String {
        var text = raw
        while let range = text.range(of: #"\[em\]e\d+\[/em\]"#, options: .regularExpression) {
            let token = String(text[range])
            let code = token.replacingOccurrences(of: "[em]", with: "").replacingOccurrences(of: "[/em]", with: "")
            text.replaceSubrange(range, with: commentEmojis[code] ?? "")
        }
        return text
    }

    /// QQ 峰尖榜总览（榜单列表在响应的 data.topList，字段为 topTitle / picUrl）
    func topLists() async throws -> [QQTopInfo] {
        let url = "https://c.y.qq.com/v8/fcg-bin/fcg_myqq_toplist.fcg?format=json"
        let json = try await get(url)
        let data = json["data"] as? [String: Any] ?? json
        let list = data["topList"] as? [[String: Any]] ?? []
        var result: [QQTopInfo] = []
        for item in list {
            guard let id = item["id"] as? Int else { continue }
            let songs = (item["songList"] as? [[String: Any]]) ?? []
            let topNames = songs.compactMap { $0["songname"] as? String }.prefix(3).map { $0 }
            result.append(QQTopInfo(
                id: id,
                name: item["topTitle"] as? String ?? (item["title"] as? String ?? ""),
                subTitle: item["subTitle"] as? String ?? "",
                topSongNames: topNames,
                coverURL: Self.normalizedQQImageURL(item["picUrl"])
            ))
        }
        return result
    }

    /// 某个峰尖榜的歌曲列表
    func topListSongs(topid: Int, limit: Int = 30) async throws -> [Song] {
        let url = "https://c.y.qq.com/v8/fcg-bin/fcg_v8_toplist_cp.fcg?format=json&page=detail&type=top&topid=\(topid)&song_begin=0&song_num=\(limit)"
        let json = try await get(url)
        let list = json["songlist"] as? [[String: Any]] ?? []
        return list.compactMap { item -> Song? in
            if let data = item["data"] as? [String: Any] {
                return song(from: data)
            }
            return song(from: item)
        }
    }

    /// QQ 每日推荐：热歌/新歌/飙升 三榜混合，按日期种子确定性打乱，每日轮换且与单个榜单内容区分
    func recommendSongs(limit: Int = 30) async throws -> [Song] {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        var songs: [Song] = []
        var seen = Set<String>()
        let per = max(8, (limit + 2) / 3)
        for topid in [26, 27, 62] {
            guard let list = try? await topListSongs(topid: topid, limit: per) else { continue }
            for song in list where !seen.contains(song.identityKey) {
                seen.insert(song.identityKey)
                songs.append(song)
            }
        }
        var rng = SeededRNG(state: UInt64(day) &* 2654435761)
        songs.shuffle(using: &rng)
        return Array(songs.prefix(limit))
    }

    /// 用户歌单（创建 + 收藏合并）。
    /// 微信网页登录可能没有 QQ uin，优先使用带微信 Cookie 的官方 GetUserPlaylist 接口，
    /// 同时保留旧版 fcg 接口作为 QQ 登录和部分旧账号的快速通道。
    func userPlaylists(uin: String) async throws -> [Playlist] {
        let qqAuth = QQMusicAuth.shared
        guard qqAuth.isLoggedIn else { return [] }

        let requestUin = qqAuth.playlistUin
        let cookieCandidates = [qqAuth.playlistCookieHeader, qqAuth.cookieHeader]
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, value in
                if !result.contains(value) { result.append(value) }
            }
        let legacyUins = (qqAuth.playlistIdentityCandidates + [requestUin, uin])
            .filter { !$0.isEmpty && $0 != "0" }
            .reduce(into: [String]()) { result, value in
                if !result.contains(value) { result.append(value) }
            }

        var playlists: [Playlist] = []
        var seen = Set<Int>()

        func append(_ item: [String: Any]) {
            guard let playlist = Self.playlist(fromQQDiss: item), !seen.contains(playlist.id) else { return }
            let text = playlist.name + " " + (item["hostname"] as? String ?? "")
            if text.lowercased().contains("qzone") || text.contains("空间") || text.contains("背景音乐") { return }
            seen.insert(playlist.id)
            playlists.append(playlist)
        }

        var createdLoaded = false
        var collectedLoaded = false

        // QQ/微信登录都尝试旧接口；部分微信态账号必须显式带 wxuin 才会返回歌单。
        for legacyUin in legacyUins {
            let createdURL = "https://c.y.qq.com/rsc/fcgi-bin/fcg_user_created_diss?hostUin=0&hostuin=\(legacyUin)&sin=0&size=200&g_tk=\(qqAuth.gtk)&loginUin=\(legacyUin)&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq.json&needNewCode=0"
            for cookie in cookieCandidates {
                guard let created = try? await get(createdURL, referer: "https://y.qq.com/portal/profile.html", cookie: cookie) else { continue }
                let data = created["data"] as? [String: Any] ?? created
                let disslist = (data["disslist"] as? [[String: Any]]) ?? (created["disslist"] as? [[String: Any]]) ?? []
                if !disslist.isEmpty {
                    createdLoaded = true
                    disslist.forEach(append)
                    break
                }
            }
            if createdLoaded { break }
        }

        for legacyUin in legacyUins {
            let collectURL = "https://c.y.qq.com/fav/fcgi-bin/fcg_get_profile_order_asset.fcg?ct=20&cid=205360956&userid=\(legacyUin)&reqtype=3&sin=0&ein=80&g_tk=\(qqAuth.gtk)"
            for cookie in cookieCandidates {
                guard let collected = try? await get(collectURL, referer: "https://y.qq.com/portal/profile.html", cookie: cookie) else { continue }
                let data = collected["data"] as? [String: Any] ?? collected
                let cdlist = (data["cdlist"] as? [[String: Any]]) ?? (collected["cdlist"] as? [[String: Any]]) ?? []
                if !cdlist.isEmpty {
                    collectedLoaded = true
                    cdlist.forEach(append)
                    break
                }
            }
            if collectedLoaded { break }
        }

        // 官方 App 接口按多个身份候选依次尝试，兼容 QQ 登录和微信网页登录。
        // order：1=创建，2=收藏，3=我喜欢。空响应仍继续尝试下一个身份参数。
        let officialUins = (qqAuth.playlistIdentityCandidates + [requestUin, "0"]).reduce(into: [String]()) { result, value in
            if !result.contains(value) { result.append(value) }
        }
        for (order, loaded) in [(1, createdLoaded), (2, collectedLoaded), (3, false)] {
            if loaded { continue }
            for officialUin in officialUins {
                let numericUin = Int(officialUin) ?? 0
                let payload: [String: Any] = [
                    "comm": [
                        "ct": 24,
                        "cv": 0,
                        "uin": numericUin,
                        "g_tk": qqAuth.gtk,
                        "platform": "yqq",
                    ],
                    "req_1": [
                        "module": "music.musichallSong.PlayListDataServer",
                        "method": "GetUserPlaylist",
                        "param": [
                            "uin": numericUin,
                            "sin": 0,
                            "size": 200,
                            "order": order,
                        ],
                    ],
                ]
                for cookie in cookieCandidates {
                    guard let json = try? await musicu(payload, cookie: cookie, timeout: 15) else { continue }
                    let list = Self.playlistArray(from: json)
                    if !list.isEmpty {
                        list.forEach(append)
                        break
                    }
                }
                if !playlists.isEmpty && order != 3 { break }
            }
        }

        if playlists.isEmpty {
            BeansLogger.shared.log("QQ 歌单列表为空（uin=\(uin)，playlistUin=\(requestUin)），可能是微信 Cookie 未包含完整登录态或接口返回空", level: .error)
        }

        // QQ 网页的 profile/create 只展示创建歌单，“我的喜欢”由 dirid=201 单独维护。
        // 即使各歌单列表接口没有把它返回，也要显式放回音乐库列表。
        if !seen.contains(Self.qqLikedPlaylistID) {
            playlists.insert(
                Playlist(
                    id: Self.qqLikedPlaylistID,
                    name: "我的喜欢",
                    coverURL: Self.qqLikedCoverURL,
                    source: .qq
                ),
                at: 0
            )
        }

        playlists.sort { lhs, rhs in
            let a = lhs.name.contains("我喜欢") || lhs.name.contains("我的喜欢") || lhs.name.contains("喜欢的音乐")
            let b = rhs.name.contains("我喜欢") || rhs.name.contains("我的喜欢") || rhs.name.contains("喜欢的音乐")
            if a != b { return a }
            return lhs.name < rhs.name
        }
        return playlists
    }

    /// QQ 歌单项解析，兼容旧 fcg 和 musicu GetUserPlaylist 的字段命名。
    private static func playlist(fromQQDiss item: [String: Any]) -> Playlist? {
        let rawName = item["diss_name"] as? String
            ?? (item["dissname"] as? String
                ?? (item["name"] as? String ?? (item["title"] as? String ?? "")))
        let dirid = integerValue(item["dirid"])
        let dissid = integerValue(item["dissid"] ?? item["diss_id"])
        let tid = integerValue(item["tid"])

        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if dirid == 201 || trimmedName == "我喜欢" || trimmedName == "我的喜欢" || trimmedName == "喜欢的音乐" {
            return Playlist(
                id: -201,
                name: "我的喜欢",
                coverURL: URL(string: "https://y.gtimg.cn/mediastyle/global/img/cover_like.png"),
                trackCount: integerValue(item["song_cnt"] ?? item["songnum"] ?? item["total_song_num"]),
                source: .qq
            )
        }

        // 目录项没有真实歌单 ID，不能展示成可打开但永远为空的歌单。
        if dissid == 0 && tid == 0 && dirid > 0 { return nil }
        let id = dissid > 0 ? dissid : (tid > 0 ? tid : (dirid > 0 ? dirid : integerValue(item["id"])))
        guard id > 0, !trimmedName.isEmpty else { return nil }

        let coverURL = [
            "diss_cover", "dir_pic_url", "logo", "picurl", "pic_url",
            "cover", "cover_url", "headurl", "imgurl",
        ].lazy.compactMap { normalizedQQImageURL(item[$0]) }.first
        let count = integerValue(item["song_cnt"] ?? item["songnum"] ?? item["total_song_num"] ?? item["song_count"])
        return Playlist(id: id, name: trimmedName, coverURL: coverURL, trackCount: count, source: .qq)
    }

    private static func integerValue(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? Double { return Int(value) }
        if let value = value as? String { return Int(value) ?? 0 }
        return 0
    }

    /// 兼容 GetUserPlaylist 在不同客户端版本中的嵌套位置。
    private static func playlistArray(from json: [String: Any]) -> [[String: Any]] {
        let paths = [
            ["req_1", "data", "v_playlist"],
            ["req_1", "data", "playlist"],
            ["req_1", "data", "list"],
            ["req_1", "data", "data", "v_playlist"],
            ["req_1", "data", "body", "v_playlist"],
        ]
        for path in paths {
            var current: Any = json
            for key in path {
                guard let dict = current as? [String: Any], let next = dict[key] else {
                    current = NSNull()
                    break
                }
                current = next
            }
            if let list = current as? [[String: Any]], !list.isEmpty {
                return list
            }
        }

        var result: [[String: Any]] = []
        func walk(_ value: Any) {
            guard result.isEmpty else { return }
            if let dict = value as? [String: Any] {
                for (key, child) in dict {
                    if key == "v_playlist", let list = child as? [[String: Any]], !list.isEmpty {
                        result = list
                        return
                    }
                    walk(child)
                }
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        walk(json)
        return result
    }

    /// QQ 推荐歌单
    func recommendPlaylists(limit: Int = 12) async throws -> [Playlist] {
        let payload: [String: Any] = [
            "comm": ["ct": 24, "cv": 0],
            "req_1": [
                "module": "music.srfDissInfo.RecommendPlaylist",
                "method": "GetRecommendPlaylist",
                "param": ["uin": 0, "lastDissid": 0, "songtype": 1, "scene": 0]
            ]
        ]
        let json = try await musicu(payload)
        let list = nestedArray(json, path: ["req_1", "data", "v_playlist"])
        var playlists: [Playlist] = []
        for item in list {
            guard let id = item["tid"] as? Int ?? (item["id"] as? Int) else { continue }
            let name = item["title"] as? String ?? ""
            let pic = Self.normalizedQQImageURL(item["cover"]) ?? Self.normalizedQQImageURL(item["pic_url"])
            let songNum = item["songnum"] as? Int ?? 0
            playlists.append(Playlist(id: id, name: name, coverURL: pic, trackCount: songNum, source: .qq))
        }
        return playlists
    }

    /// QQ 歌单内歌曲（主通道 fcg_ucc_getcdinfo_byids_cp，Mineradio 逆向；兜底 musicu GetPlaylistDetail）
    func playlistSongs(listID: Int) async throws -> [Song] {
        try await playlistSongs(listID: listID, preferredCookie: nil, limit: 100)
    }

    private func playlistSongs(listID: Int, preferredCookie: String?, limit: Int) async throws -> [Song] {
        if listID == Self.qqLikedPlaylistID {
            return try await favoriteSongs(limit: limit)
        }
        let qqAuth = QQMusicAuth.shared
        let cookie = preferredCookie ?? (qqAuth.isLoggedIn ? qqAuth.playlistCookieHeader : "")
        let loginUins = (qqAuth.isLoggedIn ? qqAuth.playlistIdentityCandidates : ["0"])
            .reduce(into: [String]()) { result, value in
                if !result.contains(value) { result.append(value) }
            }
        for loginUin in loginUins {
            let detailURL = "https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg?type=1&json=1&utf8=1&onlysong=0&new_format=1&disstid=\(listID)&loginUin=\(loginUin)&hostUin=0&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq.json&needNewCode=0"
            if let detailJson = try? await get(detailURL, referer: "https://y.qq.com/n/yqq/playlist", cookie: cookie),
               let cdlist = detailJson["cdlist"] as? [[String: Any]],
               let songlist = cdlist.first?["songlist"] as? [[String: Any]],
               !songlist.isEmpty {
                let songs = songlist.prefix(limit).compactMap { item -> Song? in
                    // 部分接口返回会把歌曲包在 track_info 里，先解包再走统一解析
                    let raw = (item["track_info"] as? [String: Any]) ?? item
                    return song(from: raw)
                }
                if !songs.isEmpty { return songs }
            }
        }
        // 兜底：musicu GetPlaylistDetail
        for loginUin in loginUins {
            let payload: [String: Any] = [
                "comm": ["ct": 24, "cv": 0, "uin": Int(loginUin) ?? 0, "g_tk": qqAuth.gtk, "platform": "yqq"],
                "req_1": [
                    "module": "music.playlist.PlayListDataServer",
                    "method": "GetPlaylistDetail",
                    "param": ["id": listID, "uin": Int(loginUin) ?? 0, "song_begin": 0, "song_num": limit]
                ]
            ]
            guard let json = try? await musicu(payload, cookie: cookie) else { continue }
            let list = nestedArray(json, path: ["req_1", "data", "songlist"])
            let songs = list.prefix(limit).compactMap { item -> Song? in
                let raw = (item["track_info"] as? [String: Any]) ?? item
                return song(from: raw)
            }
            if !songs.isEmpty { return songs }
        }
        return []
    }

    /// 歌单第一首歌曲封面（歌单封面缺失时的兜底；失败返回 nil）
    func firstSongCover(listID: Int) async throws -> URL? {
        let songs = try await playlistSongs(listID: listID)
        return songs.first?.coverURL
    }

    /// QQ 歌手热门歌曲（分页加载，避免接口单页最多返回 30 首）
    func artistHotSongs(mid: String?, name: String, limit: Int = 120) async throws -> [Song] {
        guard let mid, !mid.isEmpty else { return [] }
        let targetCount = max(limit, 1)
        let pageSize = min(targetCount, 30)
        var songs: [Song] = []
        var seen = Set<String>()
        var begin = 0

        while songs.count < targetCount {
            let url = "https://c.y.qq.com/v8/fcg-bin/fcg_v8_singer_track_cp.fcg?singer_mid=\(mid)&order=listen&begin=\(begin)&num=\(pageSize)&format=json"
            guard let json = try? await get(url) else { break }
            let data = json["data"] as? [String: Any] ?? [:]
            let list = data["list"] as? [[String: Any]] ?? []
            guard !list.isEmpty else { break }

            var added = 0
            for item in list {
                let raw = (item["musicData"] as? [String: Any]) ?? item
                guard let parsed = song(from: raw), seen.insert(parsed.identityKey).inserted else { continue }
                songs.append(parsed)
                added += 1
                if songs.count >= targetCount { break }
            }

            // 某些接口异常时会重复返回同一页，避免陷入无限请求。
            guard added > 0 else { break }
            begin += list.count
            if list.count < pageSize { break }
        }
        return Array(songs.prefix(targetCount))
    }

    /// QQ 歌手专辑（fcg_v8_singer_album；接口异常时返回空）
    func artistAlbums(mid: String?, name: String, limit: Int = 30) async throws -> [Album] {
        guard let mid, !mid.isEmpty else { return [] }
        let url = "https://c.y.qq.com/v8/fcg-bin/fcg_v8_singer_album.fcg?singer_mid=\(mid)&order=time&begin=0&num=\(limit)&format=json"
        guard let json = try? await get(url) else { return [] }
        let data = json["data"] as? [String: Any] ?? [:]
        let list = data["list"] as? [[String: Any]] ?? []
        var albums: [Album] = []
        for item in list {
            let albumName = item["albumName"] as? String ?? ""
            guard !albumName.isEmpty else { continue }
            let albumMid = item["albumMID"] as? String ?? ""
            albums.append(Album(
                id: "qq-album-\(albumMid)-\(albumName)",
                name: albumName,
                artistName: name,
                coverURL: Self.normalizedQQImageURL(item["pic"]) ?? Self.photoURL(albumMid.isEmpty ? nil : albumMid),
                source: .qq,
                trackCount: item["songnum"] as? Int
            ))
        }
        return albums
    }

    /// 通用 QQ 歌曲解析（各接口字段略有差异，此处统一容错）
    private func song(from item: [String: Any]) -> Song? {
        let mid = item["songmid"] as? String ?? (item["mid"] as? String ?? "")
        let sid = item["songid"] as? Int ?? (item["id"] as? Int ?? 0)
        guard !mid.isEmpty || sid > 0 else { return nil }
        let singers = (item["singer"] as? [[String: Any]]) ?? (item["songer"] as? [[String: Any]]) ?? []
        let artists = singers.compactMap { $0["name"] as? String }.joined(separator: " / ")
        let albumDict = item["album"] as? [String: Any] ?? [:]
        let albumName = albumDict["name"] as? String ?? (item["albumname"] as? String ?? "")
        let albumMid = albumDict["mid"] as? String ?? (item["albummid"] as? String ?? "")
        let interval = item["interval"] as? Int ?? 0
        let pay = item["pay"] as? [String: Any]
        let fee = (item["fee"] as? Int) ?? (pay?["pay_play"] as? Int) ?? (pay?["payplay"] as? Int) ?? 0
        let file = item["file"] as? [String: Any]
        let mediaMid = file?["media_mid"] as? String
            ?? item["strMediaMid"] as? String
            ?? item["media_mid"] as? String
        return Song(
            id: sid,
            name: item["songname"] as? String ?? (item["name"] as? String ?? ""),
            artists: artists,
            album: albumName,
            coverURL: Self.photoURL(albumMid.isEmpty ? nil : albumMid),
            duration: TimeInterval(interval),
            source: .qq,
            qqMid: mid.isEmpty ? nil : mid,
            qqMediaMid: mediaMid,
            fee: fee
        )
    }

    // MARK: - 工具

    private func nestedArray(_ json: [String: Any], path: [String]) -> [[String: Any]] {
        var current: Any = json
        for key in path {
            if let dict = current as? [String: Any] {
                current = dict[key] ?? [:]
            } else {
                return []
            }
        }
        return (current as? [[String: Any]]) ?? []
    }
}

/// 可播种随机数生成器（用于每日推荐按日期确定性打乱，同一天内刷新结果一致）
private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
