import Foundation
import CryptoKit

// API mapping adapted from CeruMusic ceru.bilibili 1.0.2 (MIT).
// See Beans/Resources/CeruBilibili-LICENSE.txt for attribution.
struct BilibiliError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
struct BilibiliCollection {
    let playlist: Playlist
    let songs: [Song]
}

actor BilibiliAPI {
    static let shared = BilibiliAPI()
    nonisolated static let headers = [
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        "Referer": "https://www.bilibili.com/", "Origin": "https://www.bilibili.com"
    ]
    private let session: URLSession
    private var cookie = ""
    private var restoredSession = false
    private var pendingQRLogin: (key: String, values: [String: String], redirect: URL?)?
    private var fingerprint = ""
    private var wbiKey = ""
    private var wbiDate = Date.distantPast
    private var cache: [String: (Date, [String: Any])] = [:]
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config)
    }
    func setCookie(_ value: String) {
        cookie = BilibiliProtocol.normalizeCookie(value)
        restoredSession = true
        pendingQRLogin = nil
        cache.removeAll()
        wbiKey = ""
    }
    func raw(_ url: URL, cookieOverride: String? = nil) async throws -> ([String: Any], HTTPURLResponse) {
        if cookieOverride == nil, !restoredSession {
            let saved = await BilibiliAuth.shared.cookieHeader
            if !restoredSession {
                cookie = saved
                restoredSession = true
            }
        }
        var request = URLRequest(url: url)
        Self.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let cookies = [cookieOverride ?? cookie, fingerprint].filter { !$0.isEmpty }.joined(separator: "; ")
        if !cookies.isEmpty { request.setValue(cookies, forHTTPHeaderField: "Cookie") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BilibiliError(message: "哔哩哔哩请求失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)）")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BilibiliError(message: "哔哩哔哩返回了无法识别的数据")
        }
        return (object, http)
    }
    func get(_ path: String, _ query: [String: String] = [:], signed: Bool = false, identity: Bool = false, ttl: Double = 0) async throws -> [String: Any] {
        let key = path + query.keys.sorted().map { $0 + "=" + query[$0]! }.joined(separator: "&")
        if ttl > 0, let entry = cache[key], Date().timeIntervalSince(entry.0) < ttl { return entry.1 }
        if identity && fingerprint.isEmpty {
            let fp = try await get("/x/frontend/finger/spi")
            if let b3 = fp["b_3"] as? String, let b4 = fp["b_4"] as? String {
                fingerprint = "buvid3=\(b3); buvid4=\(b4)"
            }
        }
        var values = query
        if signed {
            if wbiKey.isEmpty || Date().timeIntervalSince(wbiDate) > 3600 {
                let nav = try await get("/x/web-interface/nav")
                let img = nav["wbi_img"] as? [String: Any] ?? [:]
                let parts = ["img_url", "sub_url"].map { URL(string: img[$0] as? String ?? "")?.deletingPathExtension().lastPathComponent ?? "" }.joined()
                let chars = Array(parts)
                let mixin = [46,47,18,2,53,8,23,32,15,50,10,31,58,3,45,35,27,43,5,49,33,9,42,19,29,28,14,39,12,38,41,13,37,48,7,16,24,55,40,61,26,17,0,1,60,51,30,4,22,25,54,21,56,59,6,63,57,62,11,36,20,34,44,52]
                guard chars.count >= 64 else { throw BilibiliError(message: "无法取得 B 站签名参数") }
                wbiKey = String(mixin.prefix(32).map { chars[$0] })
                wbiDate = Date()
            }
            values["wts"] = String(Int(Date().timeIntervalSince1970))
            values = values.mapValues { $0.filter { !"!'()*".contains($0) } }
            let encoded = values.keys.sorted().map { Self.encode($0) + "=" + Self.encode(values[$0]!) }.joined(separator: "&")
            values["w_rid"] = Insecure.MD5.hash(data: Data((encoded + wbiKey).utf8)).map { String(format: "%02x", $0) }.joined()
        }
        var components = URLComponents(string: "https://api.bilibili.com" + path)!
        components.percentEncodedQuery = values.keys.sorted().map { Self.encode($0) + "=" + Self.encode(values[$0]!) }.joined(separator: "&")
        let (root, _) = try await raw(components.url!)
        let code = (root["code"] as? NSNumber)?.intValue ?? -1
        let data = root["data"] as? [String: Any] ?? root["result"] as? [String: Any] ?? [:]
        guard code == 0 || (path == "/x/web-interface/nav" && code == -101 && data["wbi_img"] != nil) else {
            let message: String
            switch code {
            case -101: message = "请先登录哔哩哔哩账号"
            case -352, -412: message = "哔哩哔哩暂时限制了请求，请稍后重试"
            case -403, -10403: message = "当前账号无权访问该内容"
            case -404: message = "视频或收藏夹已删除或不可访问"
            default: message = root["message"] as? String ?? "平台请求失败"
            }
            throw BilibiliError(message: "\(message)（\(code)）")
        }
        if ttl > 0 {
            if cache.count >= 160, let oldest = cache.min(by: { $0.value.0 < $1.value.0 })?.key { cache.removeValue(forKey: oldest) }
            cache[key] = (Date(), data)
        }
        return data
    }
    nonisolated private static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~")) ?? ""
    }
    nonisolated static func text(_ value: Any?) -> String {
        let string = value as? String ?? (value as? NSNumber)?.stringValue ?? ""
        return string.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&nbsp;", with: " ")
    }
    nonisolated static func image(_ value: Any?) -> URL? {
        let s = text(value)
        guard !s.isEmpty else { return nil }
        return URL(string: s.hasPrefix("//") ? "https:" + s : s)
    }
    nonisolated static func stableID(_ s: String) -> Int { QishuiAPI.stableID("bilibili:" + s) }
    nonisolated static func videoID(_ input: String) -> String? {
        if let range = input.range(of: "BV[0-9A-Za-z]{10}", options: .regularExpression) { return String(input[range]) }
        if let range = input.range(of: "av[0-9]+", options: [.regularExpression, .caseInsensitive]) { return String(input[range]).lowercased() }
        return nil
    }
    func video(_ id: String) async throws -> [String: Any] {
        guard let videoID = Self.videoID(id) else { throw BilibiliError(message: "B站视频编号无效") }
        return try await get("/x/web-interface/view", videoID.hasPrefix("BV") ? ["bvid":videoID] : ["aid":String(videoID.dropFirst(2))], ttl: 300)
    }
    func song(_ item: [String: Any], part: [String: Any]? = nil) -> Song? {
        let bvid = Self.text(item["bvid"])
        let aid = Self.text(item["aid"] ?? item["id"])
        guard !bvid.isEmpty || !aid.isEmpty else { return nil }
        let cid = Self.text(part?["cid"] ?? item["cid"])
        let key = (bvid.isEmpty ? "av" + aid : bvid) + (part == nil ? "" : ":" + cid)
        let owner = item["owner"] as? [String: Any] ?? item["upper"] as? [String: Any] ?? [:]
        let rawDuration = Self.text(part?["duration"] ?? item["duration"])
        let duration = rawDuration.split(separator: ":").reduce(0.0) { $0 * 60 + (Double($1) ?? 0) }
        return Song(id: Self.stableID(key), name: Self.text(part?["part"] ?? item["title"]), artists: Self.text(item["author"] ?? owner["name"]), album: Self.text(item["title"]), coverURL: Self.image(item["pic"] ?? item["cover"]), duration: duration, source: .bilibili, bilibiliID: key)
    }
    private func search(_ keyword: String, type: String = "video", limit: Int = 30) async throws -> [[String: Any]] {
        var results: [[String: Any]] = []
        let target = min(max(limit, 1), 200)
        for page in 1...10 {
            try Task.checkCancellation()
            let data = try await get("/x/web-interface/search/type", ["search_type":type,"keyword":keyword,"page":String(page),"page_size":"20"], identity: true, ttl: 300)
            let next = data["result"] as? [[String: Any]] ?? []
            results += next
            if next.count < 20 || results.count >= target { break }
        }
        return Array(results.prefix(target))
    }
    func searchSongs(keyword: String, limit: Int = 30) async throws -> [Song] { try await search(keyword, limit: limit).compactMap { song($0) } }
    func searchArtists(keyword: String, limit: Int = 30) async throws -> [Artist] {
        try await search(keyword, type: "bili_user", limit: limit).map {
            Artist(id: Self.text($0["mid"]), name: Self.text($0["uname"]), coverURL: Self.image($0["upic"]), source: .bilibili)
        }
    }
    private func playlist(_ item: [String: Any]) -> Playlist {
        let id = "video:" + Self.text(item["bvid"])
        let owner = item["owner"] as? [String: Any] ?? [:]
        return Playlist(id: Self.stableID(id), name: Self.text(item["title"]), coverURL: Self.image(item["pic"] ?? item["cover"]), trackCount: item["videos"] as? Int ?? 1, creatorName: Self.text(item["author"] ?? owner["name"]), creatorAvatarURL: Self.image(owner["face"]), playlistDescription: Self.text(item["description"] ?? item["desc"]), source: .bilibili, bilibiliID: id)
    }
    func searchPlaylists(keyword: String, limit: Int = 30) async throws -> [Playlist] { try await search(keyword, limit: limit).map { playlist($0) } }
    func searchAlbums(keyword: String, limit: Int = 30) async throws -> [Album] {
        try await search(keyword, limit: limit).map {
            let p = playlist($0)
            return Album(id: p.bilibiliID ?? "", name: p.name, artistName: p.creatorName, coverURL: p.coverURL, source: .bilibili, trackCount: p.trackCount, releaseDate: Album.releaseDateText(from: $0["pubdate"]), albumDescription: p.playlistDescription)
        }
    }
    func artistSongs(name: String, id: String? = nil, limit: Int = 100) async throws -> [Song] {
        let mid: String
        if let id, !id.isEmpty, id.allSatisfy(\.isNumber) { mid = id }
        else {
            let artists = try await searchArtists(keyword: name, limit: 20)
            guard let artist = artists.first(where: { $0.name == name }) else { return [] }
            mid = artist.id
        }
        var results: [Song] = []
        for page in 1...max(1, min(10, (limit + 29) / 30)) {
            let data = try await get("/x/space/wbi/arc/search", ["mid":mid,"ps":"30","pn":String(page),"order":"pubdate"], signed: true, identity: true, ttl: 300)
            let list = (data["list"] as? [String: Any])?["vlist"] as? [[String: Any]] ?? []
            results += list.compactMap { song($0) }
            if list.count < 30 { break }
        }
        return Array(results.prefix(limit))
    }
    func recommendedPlaylists(limit: Int = 18, category: String = "music") async throws -> [Playlist] {
        let data = category == "popular"
            ? try await get("/x/web-interface/popular", ["pn":"1","ps":String(min(limit,50))], identity:true, ttl:1800)
            : try await get("/x/web-interface/ranking/v2", ["rid":"3","type":"all"], signed:true, identity:true, ttl:1800)
        return Array((data["list"] as? [[String: Any]] ?? []).prefix(limit)).map { playlist($0) }
    }
    func popularVideos(page: Int, force: Bool = false) async throws -> (videos: [BilibiliFeedVideo], hasMore: Bool) {
        let data = try await get("/x/web-interface/popular", ["pn": String(max(1, page)), "ps": "20"], identity: true, ttl: force ? 0 : 900)
        let rows = data["list"] as? [[String: Any]] ?? []
        let videos = rows.compactMap { row -> BilibiliFeedVideo? in
            guard let track = song(row) else { return nil }
            let owner = row["owner"] as? [String: Any] ?? [:]
            let stat = row["stat"] as? [String: Any] ?? [:]
            return BilibiliFeedVideo(song: track, ownerAvatarURL: Self.image(owner["face"]),
                                     playCount: (stat["view"] as? NSNumber)?.intValue ?? 0,
                                     danmakuCount: (stat["danmaku"] as? NSNumber)?.intValue ?? 0)
        }
        let noMore = (data["no_more"] as? Bool) ?? ((data["no_more"] as? NSNumber)?.boolValue ?? false)
        return (videos, !noMore && !rows.isEmpty)
    }
    func recommendedSongs(limit: Int = 30) async throws -> [Song] {
        let data = try await get("/x/web-interface/ranking/v2", ["rid":"3","type":"all"], signed:true, identity:true, ttl:1800)
        return Array((data["list"] as? [[String:Any]] ?? []).prefix(limit)).compactMap { song($0) }
    }
    func collection(_ input: String, force: Bool = false) async throws -> BilibiliCollection {
        if let vid = Self.videoID(input) {
            let data = try await video(vid)
            let pages = data["pages"] as? [[String: Any]] ?? []
            let p = playlist(data)
            let songs = pages.isEmpty ? [song(data)].compactMap { $0 } : pages.compactMap { song(data, part:$0) }
            return BilibiliCollection(playlist:p,songs:songs)
        }
        var fid = input.hasPrefix("fav:") ? String(input.dropFirst(4)) : ""
        if fid.isEmpty, let components = URLComponents(string:input) {
            fid = components.queryItems?.first(where: { ["fid","media_id"].contains($0.name) })?.value ?? ""
        }
        if fid.isEmpty, let range = input.range(of:"(?<=/ml)[0-9]+",options:.regularExpression) { fid = String(input[range]) }
        guard !fid.isEmpty, fid.allSatisfy(\.isNumber) else { throw BilibiliError(message:"请粘贴 B站视频、BV号或公开收藏夹链接") }
        var tracks: [Song] = [], info: [String:Any] = [:], seen = Set<String>()
        for page in 1...500 {
            try Task.checkCancellation()
            let data = try await get("/x/v3/fav/resource/list",["media_id":fid,"platform":"web","ps":"20","pn":String(page)],identity:true,ttl:force ? 0 : 300)
            if page == 1 { info = data["info"] as? [String:Any] ?? [:] }
            let items = data["medias"] as? [[String:Any]] ?? []
            let next = items.compactMap { song($0) }.filter { seen.insert($0.identityKey).inserted }
            tracks += next
            if data["has_more"] as? Bool != true || next.isEmpty { break }
            if page == 500 { throw BilibiliError(message:"收藏夹过大，请拆分后导入") }
        }
        let owner = info["upper"] as? [String:Any] ?? [:]
        let p = Playlist(id:Self.stableID("fav:"+fid),name:Self.text(info["title"]),coverURL:Self.image(info["cover"]),trackCount:tracks.count,creatorName:Self.text(owner["name"]),creatorAvatarURL:Self.image(owner["face"]),playlistDescription:Self.text(info["intro"]),source:.bilibili,bilibiliID:"fav:"+fid)
        return BilibiliCollection(playlist:p,songs:tracks)
    }
    func playbackURL(for track: Song, quality: BeansAudioQuality = .hires) async throws -> URL {
        let urls = try await playbackURLs(for: track, quality: quality)
        guard let first = urls.first else { throw BilibiliError(message: "该视频没有可播放的音轨") }
        return first
    }

    func playbackURLs(for track: Song, quality: BeansAudioQuality = .hires) async throws -> [URL] {
        let key = track.bilibiliID ?? ""
        let data = try await video(key)
        let selectedCID = key.split(separator: ":").dropFirst().first.map(String.init)
        let cid = selectedCID ?? Self.text(data["cid"])
        guard !cid.isEmpty else { throw BilibiliError(message: "该视频缺少分P编号，请重新打开视频") }
        let preferred = quality == .standard ? 30216 : quality == .higher ? 30232 : 30280
        var query = ["cid": cid, "qn": "80", "fnval": "16", "fnver": "0", "fourk": "1"]
        let bvid = Self.text(data["bvid"])
        if bvid.isEmpty { query["aid"] = Self.text(data["aid"]) } else { query["bvid"] = bvid }
        var lastError: Error = BilibiliError(message: "该视频没有返回可播放的 AAC 音轨，可能需要登录或已不可用")
        for signed in [false, true] {
            try Task.checkCancellation()
            do {
                let response = try await get(signed ? "/x/player/wbi/playurl" : "/x/player/playurl", query, signed: signed)
                let urls = BilibiliProtocol.audioURLs(response, preferredID: preferred)
                if !urls.isEmpty { return urls }
                let progressive = BilibiliProtocol.progressiveURLs(response)
                if !progressive.isEmpty { return progressive }
            } catch is CancellationError { throw CancellationError() }
            catch { lastError = error }
        }
        // A few public videos return only a single progressive MP4 rather than
        // DASH audio. AVPlayer can play its audio track without displaying video.
        do {
            query["fnval"] = "1"
            query["qn"] = "16"
            query["platform"] = "html5"
            let response = try await get("/x/player/playurl", query)
            let urls = BilibiliProtocol.progressiveURLs(response)
            if !urls.isEmpty { return urls }
        } catch is CancellationError { throw CancellationError() }
        catch { lastError = error }
        throw lastError
    }
    func lyric(for track: Song) async throws -> String? {
        let key = track.bilibiliID ?? ""
        let video = try await video(key)
        let cid = key.split(separator:":").dropFirst().first.map(String.init) ?? Self.text(video["cid"])
        let data = try await get("/x/player/wbi/v2",["bvid":Self.text(video["bvid"]),"cid":cid],signed:true,identity:true)
        let subtitles = (data["subtitle"] as? [String:Any])?["subtitles"] as? [[String:Any]] ?? []
        guard let selected = subtitles.first(where:{ Self.text($0["lan"]).hasPrefix("zh") }) ?? subtitles.first,
              let url = Self.image(selected["subtitle_url"]), let host = url.host, host == "hdslb.com" || host.hasSuffix(".hdslb.com") else { return nil }
        let (root,_) = try await raw(url, cookieOverride: "")
        return (root["body"] as? [[String:Any]] ?? []).map { row in
            let from = (row["from"] as? NSNumber)?.doubleValue ?? 0
            let text = Self.text(row["content"]).replacingOccurrences(of:"\n",with:" ")
            return String(format:"[%02d:%06.3f]",Int(from / 60),from.truncatingRemainder(dividingBy:60)) + text
        }.joined(separator:"\n")
    }
    func comments(for track: Song, limit: Int = 20, offset: Int = 0) async throws -> NetEaseAPI.SongCommentPage {
        let video = try await video(track.bilibiliID ?? "")
        let page = offset / max(limit, 1)
        let common: [String: String] = ["type":"1", "oid":Self.text(video["aid"]), "plat":"1", "next":String(page)]
        let latestData = try await get("/x/v2/reply/wbi/main", common.merging(["mode":"2"]) { _, new in new }, signed:true, identity:true)
        let hotData: [String: Any]
        if page == 0 {
            hotData = try await get("/x/v2/reply/wbi/main", common.merging(["mode":"3", "next":"0"]) { _, new in new }, signed:true, identity:true)
        } else {
            hotData = [:]
        }
        func convert(_ rows: [[String:Any]], isHot: Bool = false) -> [SongComment] {
            rows.compactMap { row in
                let member = row["member"] as? [String:Any] ?? [:]
                let content = row["content"] as? [String:Any] ?? [:]
                guard let id = row["rpid"] as? Int else { return nil }
                return SongComment(id:id,content:Self.text(content["message"]),nickname:Self.text(member["uname"]),avatarURL:Self.image(member["avatar"]),time:Date(timeIntervalSince1970:(row["ctime"] as? NSNumber)?.doubleValue ?? 0),likedCount:row["like"] as? Int ?? 0,isHot:isHot)
            }
        }
        let cursor = latestData["cursor"] as? [String: Any] ?? [:]
        let pageInfo = latestData["page"] as? [String: Any] ?? [:]
        let total = (cursor["all_count"] as? NSNumber)?.intValue ?? (pageInfo["count"] as? NSNumber)?.intValue ?? 0
        return NetEaseAPI.SongCommentPage(total:total, hot:convert(hotData["hots"] as? [[String:Any]] ?? [],isHot:true), comments:convert(latestData["replies"] as? [[String:Any]] ?? []))
    }
    func account(cookie value: String) async throws -> String {
        try await accountInfo(cookie: value).nickname
    }
    func accountInfo(cookie value: String) async throws -> (nickname: String, mid: String) {
        let (root,_) = try await raw(URL(string:"https://api.bilibili.com/x/web-interface/nav")!,cookieOverride:value)
        guard let data = root["data"] as? [String:Any], data["isLogin"] as? Bool == true else { throw BilibiliError(message:"B站登录凭据已过期或无效") }
        return (Self.text(data["uname"]), Self.text(data["mid"]))
    }
    func personalPlaylists() async throws -> [Playlist] {
        let nav = try await get("/x/web-interface/nav",identity:true)
        guard nav["isLogin"] as? Bool == true else { throw BilibiliError(message:"请先登录哔哩哔哩") }
        let data = try await get("/x/v3/fav/folder/created/list-all",["up_mid":Self.text(nav["mid"])],identity:true)
        return (data["list"] as? [[String:Any]] ?? []).map { item in
            let id = "fav:" + Self.text(item["id"])
            return Playlist(id:Self.stableID(id),name:Self.text(item["title"]),coverURL:Self.image(item["cover"]),trackCount:item["media_count"] as? Int ?? 0,creatorName:Self.text(nav["uname"]),playlistDescription:Self.text(item["intro"]),source:.bilibili,bilibiliID:id)
        }
    }
    func loginQR() async throws -> (url: String, key: String) {
        let (root,_) = try await raw(URL(string:"https://passport.bilibili.com/x/passport-login/web/qrcode/generate")!)
        guard let data=root["data"] as? [String:Any],let url=data["url"] as? String, let key=data["qrcode_key"] as? String,
              let parsed=URL(string:url),parsed.scheme == "https",let host=parsed.host,host == "bilibili.com" || host.hasSuffix(".bilibili.com") else { throw BilibiliError(message:"无法生成 B站登录二维码") }
        pendingQRLogin = nil
        return (url,key)
    }
    func pollQR(_ key: String) async throws -> (code: Int, cookie: String) {
        if pendingQRLogin?.key == key { return try await completeQRLogin(key) }
        var components = URLComponents(string: "https://passport.bilibili.com/x/passport-login/web/qrcode/poll")!
        components.queryItems = [URLQueryItem(name: "qrcode_key", value: key)]
        let (root, response) = try await raw(components.url!)
        guard (root["code"] as? NSNumber)?.intValue == 0,
              let data = root["data"] as? [String: Any], let code = (data["code"] as? NSNumber)?.intValue else {
            throw BilibiliError(message: "B站扫码状态异常，请刷新二维码")
        }
        guard code == 0 else { return (code, "") }
        let redirect = (data["url"] as? String).flatMap(BilibiliProtocol.loginURL)
        pendingQRLogin = (key, BilibiliProtocol.responseCookies(response), redirect)
        return try await completeQRLogin(key)
    }

    private func completeQRLogin(_ key: String) async throws -> (code: Int, cookie: String) {
        guard let pending = pendingQRLogin, pending.key == key else { throw CancellationError() }
        var values = pending.values
        if let redirect = pending.redirect {
            values.merge(BilibiliProtocol.queryCookies(from: redirect)) { current, _ in current }
            if values["SESSDATA"] == nil {
                values.merge(try await crossDomainCookies(from: redirect)) { current, _ in current }
            }
        }
        guard pendingQRLogin?.key == key else { throw CancellationError() }
        pendingQRLogin = (key, values, pending.redirect)
        return (0, BilibiliProtocol.cookieHeader(values))
    }

    private func crossDomainCookies(from url: URL) async throws -> [String: String] {
        guard url.path.lowercased().contains("crossdomain") else { return [:] }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        let exchange = URLSession(configuration: config, delegate: BilibiliLoginRedirectDelegate(), delegateQueue: nil)
        defer { exchange.invalidateAndCancel() }
        var next: URL? = url
        var values: [String: String] = [:]
        for _ in 0..<5 {
            try Task.checkCancellation()
            guard let current = next, BilibiliProtocol.loginURL(current.absoluteString) != nil else { break }
            var request = URLRequest(url: current)
            Self.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            let (_, response) = try await exchange.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
                throw BilibiliError(message: "扫码已确认，但登录凭据交换失败，请刷新二维码重试")
            }
            values.merge(BilibiliProtocol.responseCookies(http)) { _, latest in latest }
            if values["SESSDATA"] != nil { return values }
            guard let location = http.value(forHTTPHeaderField: "Location"),
                  let redirect = URL(string: location, relativeTo: current)?.absoluteURL,
                  BilibiliProtocol.loginURL(redirect.absoluteString) != nil else { break }
            values.merge(BilibiliProtocol.queryCookies(from: redirect)) { _, latest in latest }
            next = redirect
        }
        return values
    }
}
