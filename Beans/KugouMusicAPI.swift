import Foundation
import Security
import UIKit

final class KugouMusicAPI {
    static let shared = KugouMusicAPI()

    private let gateway = "https://gateway.kugou.com"
    private let loginBase = "https://login-user.kugou.com"
    private let userService = "https://userservice.kugou.com"
    private let appid = "3116"
    private let clientver = "11440"
    private let qrAppid = "1001"
    private let qrSrcAppid = "2919"
    private let androidSignKey = "LnT6xpN3khm36zse0QzvmgTZ3waWdRSA"
    private let webSignKey = "NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt"
    private let playSalt = "kgcloudv2"
    private let playSignSalt = "57ae12eb6890223e355ccfcb74edf70d"
    private let playAppid = "1005"
    private let playClientver = "20489"
    private let androidUA = "Android15-1070-11440-46-0-DiscoveryDRADProtocol-wifi"
    private let playbackUA = "Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi"
    private let rsaPublicKeyBase64 = "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDECi0Np2UR87scwrvTr72L6oO01rBbbBPriSDFPxr3Z5syug0O24QyQO8bg27+0+4kBzTBTBOZ/WWU0WryL1JSXRTXLgFVxtzIY41Pe7lPOgsfTCn5kZcvKhYKJesKnnJDNr5/abvTGf+rHG3YRwsCHcQ08/q6ifSioBszvb3QiwIDAQAB"

    private let session: URLSession
    private var lastMembershipProbeAt: Date?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 18
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config)
    }

    struct QRLogin: Equatable {
        let key: String
        let url: String
    }

    enum QRState: Equatable {
        case waiting
        case scanned
        case expired
        case success(String)
        case error(String)
    }

    func qrKey() async throws -> QRLogin {
        KugouMusicAuth.shared.prepareDevice()
        let qrcodeText = "https://h5.kugou.com/apps/loginQRCode/html/index.html?appid=\(appid)&"
        let response = try await gatewayRequest(
            "/v2/qrcode",
            baseURL: loginBase,
            signType: .web,
            params: [
                "appid": qrAppid,
                "type": "1",
                "plat": "4",
                "qrcode_txt": qrcodeText,
                "srcappid": qrSrcAppid,
            ],
            headers: [
                "User-Agent": Self.browserUA,
                "x-router": "login-user.kugou.com",
            ]
        )
        let json = response.json
        let key = Self.deepString(json, names: ["qrcode", "key"])
        guard !key.isEmpty else { throw NetEaseError.unknown("酷狗二维码生成失败") }
        return QRLogin(key: key, url: "https://h5.kugou.com/apps/loginQRCode/html/index.html?qrcode=\(Self.urlEncode(key))")
    }

    func pollQR(key: String) async throws -> QRState {
        let response = try await gatewayRequest(
            "/v2/get_userinfo_qrcode",
            baseURL: loginBase,
            signType: .web,
            params: [
                "plat": "4",
                "appid": appid,
                "srcappid": qrSrcAppid,
                "qrcode": key,
            ],
            headers: [
                "User-Agent": Self.browserUA,
                "x-router": "login-user.kugou.com",
            ]
        )
        let json = response.json
        let status = Self.deepInt(json, names: ["status"])
        let token = Self.deepString(json, names: ["token", "user_token", "access_token", "key"])
        let userId = Self.deepString(json, names: ["userid", "user_id", "uid", "kugooid", "kugouid"]).filter(\.isNumber)
        guard !token.isEmpty, !userId.isEmpty else {
            if status == 2 { return .scanned }
            if status == 3 { return .expired }
            return .waiting
        }
        let nick = Self.deepString(json, names: ["nickname", "nick", "username", "user_name", "uname"])
        let avatar = Self.deepString(json, names: ["avatar", "pic", "img", "headpic", "user_pic", "userpic"])
        let vip = Self.deepInt(json, names: ["vip_type", "vipType", "viptype", "isvip", "is_vip", "vip"])
        KugouMusicAuth.shared.saveLogin(userId: userId, token: token, nickname: nick, avatar: avatar, vipType: vip)
        await registerDevice()
        await refreshMembershipStatusIfNeeded(force: true)
        return .success(nick.isEmpty ? "酷狗音乐用户 \(userId)" : nick)
    }

    func userPlaylists() async throws -> [Playlist] {
        let auth = KugouMusicAuth.shared
        guard auth.isLoggedIn else { return [] }
        await refreshMembershipStatusIfNeeded()
        let dataBody: [String: Any] = [
            "total_ver": 979,
            "type": 2,
            "page": 1,
            "pagesize": 200,
            "userid": Int(auth.userId) ?? 0,
            "token": auth.token,
        ]
        let response = try await gatewayRequest(
            "/v7/get_all_list",
            method: "POST",
            params: [
                "total_ver": "979",
                "type": "2",
                "page": "1",
                "pagesize": "200",
                "userid": auth.userId,
                "token": auth.token,
            ],
            data: dataBody,
            headers: ["x-router": "cloudlist.service.kugou.com"]
        )
        let json = response.json
        let code = Self.deepInt(json, names: ["error_code", "errcode", "code"])
        let status = Self.deepInt(json, names: ["status"])
        let raw = Self.deepArrays(json, names: ["lists", "list", "info", "data", "listinfo", "collection_list", "playlist"])
        BeansLogger.shared.log("酷狗歌单同步：status=\(status) code=\(code) 返回 \(raw.count) 个", level: .debug)
        var seen = Set<Int>()
        return raw.compactMap { item in
            guard let playlist = Self.mapPlaylist(item), !seen.contains(playlist.id) else { return nil }
            seen.insert(playlist.id)
            return playlist
        }
    }

    /// 酷狗自有移动端搜索接口：搜索结果携带 hash、专辑和封面，可直接复用酷狗播放地址解析。
    /// 优先使用酷狗新版综合搜索，旧网页接口作为兜底。
    func searchSongs(keyword: String, limit: Int = 30) async throws -> [Song] {
        if let complete = try? await searchSongsComplete(keyword: keyword, limit: limit), !complete.isEmpty {
            BeansLogger.shared.log("酷狗综合搜索完成：\(keyword) 结果=\(complete.count)", level: .info)
            return complete
        }

        var components = URLComponents(string: "https://songsearch.kugou.com/song_search_v2")!
        components.queryItems = [
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pagesize", value: "\(min(max(limit, 1), 100))"),
        ]
        guard let url = components.url else {
            throw NetEaseError.unknown("酷狗搜索地址无效")
        }
        let json = try await getJSON(url, ua: Self.browserUA)
        let raw = Self.deepArrays(json, names: ["info", "songs", "song", "list", "data"])
        let songs = raw.compactMap(Self.mapTrack)
        BeansLogger.shared.log("酷狗搜索完成：\(keyword) 结果=\(songs.count)", level: .info)
        return songs
    }

    /// 酷狗 iOS 综合搜索接口。该接口返回的结果比旧网页接口完整，
    /// 同时携带歌曲 hash、专辑、歌手、封面和权限字段。
    private func searchSongsComplete(keyword: String, limit: Int) async throws -> [Song] {
        var result: [Song] = []
        var seen = Set<String>()
        let pageSize = min(max(limit, 1), 50)
        // 综合搜索接口经常固定只返回 15 条，即使 pagesize 请求更大；
        // 不要用 songs.count < pageSize 判断分页结束，否则歌手页永远只得到首屏。
        let pages = max(1, min(30, Int(ceil(Double(min(max(limit, 1), 300)) / 15.0)) + 2))
        for page in 1...pages {
            let songs = try await searchSongsCompletePage(keyword: keyword, page: page, pageSize: pageSize)
            guard !songs.isEmpty else { break }
            let before = result.count
            for song in songs where seen.insert(song.identityKey).inserted {
                result.append(song)
                if result.count >= limit { return result }
            }
            if result.count == before { break }
        }
        return result
    }

    private func searchSongsCompletePage(keyword: String, page: Int, pageSize: Int) async throws -> [Song] {
        let auth = KugouMusicAuth.shared
        auth.prepareDevice()
        let clientTime = "\(Int(Date().timeIntervalSince1970))"
        let userID = auth.isLoggedIn ? auth.userId : "0"
        let token = auth.isLoggedIn ? auth.token : ""
        let mid = auth.mid
        let dfid = auth.dfid
        let uuid = auth.guid.isEmpty ? mid : auth.guid
        var params: [String: String] = [
            "ab_tag": "1",
            "ability": "57343",
            "albumhide": "1",
            "apiver": "22",
            "appid": "1000",
            "area_code": "1",
            "clienttime": clientTime,
            "clientver": "20549",
            "com_user_type": "0",
            "cursor": "\(max(page, 1))",
            "dfid": dfid,
            "is_gpay": "0",
            "iscorrection": "1",
            "keyword": keyword,
            "mid": mid,
            "mode_ability": "0",
            "nocollect": "0",
            "osversion": "16.0",
            "platform": "IOSFilter",
            "recver": "2",
            "req_ai": "1",
            "search_ability": "31",
            "search_source": "手动输入",
            "sec_aggre": "1",
            "sec_aggre_bitmap": "22",
            "style_type": "3",
            "tag": "em",
            "token": token,
            "userid": userID,
            "uuid": uuid,
        ]
        params["signature"] = Self.searchSignature(params)

        var components = URLComponents(string: "https://gateway.kugou.com/complexsearch/v3/search/mixed")!
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw NetEaseError.unknown("酷狗综合搜索地址无效") }
        let headers = [
            "KG-RF": "D4407D2505656C0FDC1621BA6FA3FEB5",
            "KG-FAKE": "359933394",
            "KG-FAKE-TYPE": "29,1",
            "KG-RC": "1",
            "UNI-UserAgent": "iOS16.0-Phone-1009-0-WiFi",
            "Accept": "*/*",
            "Accept-Language": "zh-Hans-CN;q=1",
        ]
        let json = try await getJSON(url, ua: "IPhone-20549-Search#183534257/723988397/625045823/284854956-SearchGeneralInfoWithKeyWordV8", headers: headers)
        guard let data = json["data"] as? [String: Any],
              let groups = data["lists"] as? [[String: Any]],
              let songGroup = groups.first(where: {
                  let type = Self.string($0["type"]).lowercased()
                  return type == "song" || type == "songs"
              }),
              let rows = songGroup["lists"] as? [[String: Any]] else {
            return []
        }
        return rows.prefix(min(max(pageSize, 1), 100)).compactMap(Self.mapCompleteTrack)
    }

    /// 基于酷狗官方歌曲搜索结果聚合歌手，保留官方歌手名与封面。
    func searchArtists(keyword: String, limit: Int = 40) async throws -> [Artist] {
        let songs = try await searchSongs(keyword: keyword, limit: limit)
        var result: [Artist] = []
        var seen = Set<String>()
        for song in songs {
            for name in song.artists.split(separator: "/").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                let value = String(name)
                guard !value.isEmpty, seen.insert(value).inserted else { continue }
                result.append(Artist(
                    id: value,
                    name: value,
                    coverURL: song.coverURL,
                    source: .kugou
                ))
            }
        }
        return result
    }

    /// 基于酷狗官方歌曲搜索结果聚合专辑，保留官方专辑名、歌手与封面。
    func searchAlbums(keyword: String, limit: Int = 40) async throws -> [Album] {
        let songs = try await searchSongs(keyword: keyword, limit: limit)
        var result: [Album] = []
        var seen = Set<String>()
        for song in songs where !song.album.isEmpty {
            let key = "\(song.album)|\(song.artists)"
            guard seen.insert(key).inserted else { continue }
            result.append(Album(
                id: key,
                name: song.album,
                artistName: song.artists,
                coverURL: song.coverURL,
                source: .kugou,
                trackCount: nil
            ))
        }
        return result
    }

    /// 酷狗官方排行榜列表（移动站点 JSON）。
    func topLists(limit: Int = 10) async throws -> [KugouTopInfo] {
        if let lists = try? await officialWebTopLists(limit: limit), !lists.isEmpty {
            return lists
        }
        guard let url = URL(string: "https://m.kugou.com/rank/list?json=true") else {
            throw NetEaseError.unknown("酷狗排行榜地址无效")
        }
        let json = try await getJSON(url, ua: Self.browserUA)
        guard let rank = json["rank"] as? [String: Any],
              let list = rank["list"] as? [[String: Any]] else {
            throw NetEaseError.decoding("酷狗排行榜数据格式异常")
        }
        return list.prefix(limit).compactMap { item in
            let id = Self.int(item["rankid"] ?? item["id"])
            guard id > 0 else { return nil }
            let name = Self.string(item["rankname"] ?? item["name"])
            guard !name.isEmpty else { return nil }
            let cover = Self.normalizeURL(Self.string(item["album_img_9"] ?? item["img_9"] ?? item["imgurl"])
                .replacingOccurrences(of: "{size}", with: "400")
            )
            return KugouTopInfo(
                id: id,
                name: name,
                updateFrequency: Self.string(item["update_frequency"] ?? item["updateFrequency"]),
                coverURL: URL(string: cover)
            )
        }
    }

    /// 酷狗官方排行榜歌曲。
    func rankSongs(rankID: Int, limit: Int = 100) async throws -> [Song] {
        if let songs = try? await officialWebRankSongs(rankID: rankID, limit: limit), !songs.isEmpty {
            guard songs.contains(where: { $0.coverURL == nil }) else { return songs }
            if let mobileSongs = try? await mobileRankSongs(rankID: rankID, limit: limit), !mobileSongs.isEmpty {
                let merged = Self.mergeRankCovers(primary: songs, fallback: mobileSongs)
                BeansLogger.shared.log("酷狗排行榜封面补齐：rankid=\(rankID) 官网=\(songs.count) 移动端=\(mobileSongs.count)", level: .debug)
                return merged
            }
            return songs
        }
        return try await mobileRankSongs(rankID: rankID, limit: limit)
    }

    private func mobileRankSongs(rankID: Int, limit: Int) async throws -> [Song] {
        var components = URLComponents(string: "https://m.kugou.com/rank/info")!
        components.queryItems = [
            URLQueryItem(name: "rankid", value: "\(rankID)"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "json", value: "true"),
        ]
        guard let url = components.url else { throw NetEaseError.unknown("酷狗排行榜地址无效") }
        let json = try await getJSON(url, ua: Self.browserUA)
        let rows = (json["songs"] as? [String: Any])?["list"] as? [[String: Any]] ?? []
        return rows.prefix(limit).compactMap(Self.mapTrack)
    }

    /// 酷狗官方歌单广场（移动站点 JSON）。
    func recommendPlaylists(limit: Int = 12) async throws -> [Playlist] {
        if let playlists = try? await officialWebPlaylists(limit: limit), !playlists.isEmpty {
            return playlists
        }
        guard let url = URL(string: "https://m.kugou.com/plist/index?json=true&page=1") else {
            throw NetEaseError.unknown("酷狗歌单广场地址无效")
        }
        let json = try await getJSON(url, ua: Self.browserUA)
        let rows = (((json["plist"] as? [String: Any])?["list"] as? [String: Any])?["info"] as? [[String: Any]]) ?? []
        return rows.prefix(limit).compactMap { item in
            let id = Self.int(item["specialid"] ?? item["id"])
            guard id > 0 else { return nil }
            let name = Self.string(item["specialname"] ?? item["name"] ?? item["title"])
            guard !name.isEmpty else { return nil }
            let cover = Self.normalizeURL(Self.string(item["imgurl"] ?? item["pic"] ?? item["cover"])
                .replacingOccurrences(of: "{size}", with: "400")
            )
            return Playlist(
                id: id,
                name: name,
                coverURL: URL(string: cover),
                trackCount: Self.int(item["songcount"] ?? item["song_count"]),
                source: .kugou
            )
        }
    }

    private func officialWebTopLists(limit: Int) async throws -> [KugouTopInfo] {
        guard let url = URL(string: "https://www.kugou.com/yy/html/rank.html") else {
            throw NetEaseError.unknown("酷狗官网排行榜地址无效")
        }
        let html = try await getString(url, ua: Self.browserUA)
        let pattern = #"<a title="([^"]+)"[^>]*href="https://www\.kugou\.com/yy/rank/home/1-(\d+)\.html\?from=rank"[\s\S]*?background-image:url\(([^\)]+)\)"#
        var seen = Set<Int>()
        let rows = Self.regexMatches(pattern, in: html).compactMap { groups -> KugouTopInfo? in
            guard groups.count >= 4 else { return nil }
            let id = Int(groups[2]) ?? 0
            guard id > 0, seen.insert(id).inserted else { return nil }
            let cover = Self.normalizeURL(groups[3].trimmingCharacters(in: .whitespacesAndNewlines))
            return KugouTopInfo(
                id: id,
                name: Self.clean(Self.htmlDecode(groups[1])),
                updateFrequency: "酷狗官网热门榜单",
                coverURL: URL(string: cover)
            )
        }
        BeansLogger.shared.log("酷狗官网热门榜单：返回 \(rows.count) 个", level: .debug)
        return Array(rows.prefix(limit))
    }

    private func officialWebRankSongs(rankID: Int, limit: Int) async throws -> [Song] {
        guard let url = URL(string: "https://www.kugou.com/yy/rank/home/1-\(rankID).html?from=rank") else {
            throw NetEaseError.unknown("酷狗官网排行榜歌曲地址无效")
        }
        let html = try await getString(url, ua: Self.browserUA)
        guard let rows = Self.javascriptArray(named: "global.features", in: html) else {
            throw NetEaseError.decoding("酷狗官网排行榜歌曲格式异常")
        }
        let songs = rows.prefix(limit).compactMap(Self.mapCompleteTrack)
        BeansLogger.shared.log("酷狗官网排行榜歌曲：rankid=\(rankID) 返回 \(songs.count) 首", level: .debug)
        return songs
    }

    private func officialWebPlaylists(limit: Int) async throws -> [Playlist] {
        guard let url = URL(string: "https://www.kugou.com/yy/html/special.html") else {
            throw NetEaseError.unknown("酷狗官网歌单广场地址无效")
        }
        let html = try await getString(url, ua: Self.browserUA)
        let pattern = #"<li class="s_(\d+)"[\s\S]*?<a[^>]+title="([^"]+)" href="https://www\.kugou\.com/songlist/(gcid_[^/]+)/"[\s\S]*?_src="([^"]+)""#
        var seen = Set<Int>()
        let rows = Self.regexMatches(pattern, in: html).compactMap { groups -> Playlist? in
            guard groups.count >= 5 else { return nil }
            let id = Int(groups[1]) ?? 0
            guard id > 0, seen.insert(id).inserted else { return nil }
            let cover = Self.normalizeURL(groups[4].replacingOccurrences(of: "{size}", with: "400"))
            return Playlist(
                id: id,
                name: Self.clean(Self.htmlDecode(groups[2])),
                coverURL: URL(string: cover),
                trackCount: 0,
                source: .kugou
            )
        }
        BeansLogger.shared.log("酷狗官网歌单广场：返回 \(rows.count) 个", level: .debug)
        return Array(rows.prefix(limit))
    }

    private func officialWebPlaylistSongs(listID: Int) async throws -> [Song] {
        guard let url = URL(string: "https://www.kugou.com/yy/special/single/\(listID).html") else {
            throw NetEaseError.unknown("酷狗官网歌单歌曲地址无效")
        }
        let html = try await getString(url, ua: Self.browserUA)
        guard let rows = Self.javascriptArray(named: "data", in: html) else {
            throw NetEaseError.decoding("酷狗官网歌单歌曲格式异常")
        }
        let songs = rows.compactMap(Self.mapCompleteTrack)
        BeansLogger.shared.log("酷狗官网歌单歌曲：specialid=\(listID) 返回 \(songs.count) 首", level: .debug)
        return songs
    }

    /// 酷狗搜索页专用热词。酷狗没有稳定公开的热搜 JSON 合约时使用独立词表，
    /// 确保切换到酷狗后不会继续显示网易云热搜。
    func hotWords() async -> [String] {
        [
            "周杰伦", "林俊杰", "陈奕迅", "薛之谦", "邓紫棋",
            "凤凰传奇", "五月天", "毛不易", "告五人", "热门歌曲"
        ]
    }

    func playlistSongs(listID: Int) async throws -> [Song] {
        if listID >= 1000,
           let songs = try? await officialWebPlaylistSongs(listID: listID),
           !songs.isEmpty {
            return songs
        }
        let auth = KugouMusicAuth.shared
        guard auth.isLoggedIn else { return [] }
        let pid = "\(listID)"
        var all: [[String: Any]] = []
        var page = 1
        repeat {
            let body: [String: Any] = [
                "listid": pid,
                "page": page,
                "pagesize": 200,
                "area_code": 1,
                "show_relate_goods": 0,
                "allplatform": 1,
                "show_cover": 1,
                "type": 0,
                "userid": Int(auth.userId) ?? 0,
                "token": auth.token,
            ]
            let json = try await cloudlistRequest("/v4/get_list_all_file", params: ["listid": pid, "page": "\(page)", "pagesize": "200"], data: body)
            let pageTracks = Self.deepArrays(json, names: ["songs", "songlist", "list", "info", "files", "data"])
            BeansLogger.shared.log("酷狗歌单歌曲：listid=\(pid) page=\(page) 返回 \(pageTracks.count) 首", level: .debug)
            all.append(contentsOf: pageTracks)
            if pageTracks.count < 200 { break }
            page += 1
        } while page <= 10
        return all
            .sorted { (Self.int($0["fsort"] ?? $0["sort"] ?? $0["position"]) ) < (Self.int($1["fsort"] ?? $1["sort"] ?? $1["position"])) }
            .compactMap(Self.mapTrack)
    }

    func songURL(song: Song, quality: BeansAudioQuality? = nil) async throws -> String? {
        await refreshMembershipStatusIfNeeded()
        let requestedQuality = quality ?? BeansAudioQuality.current
        var primary = song.kugouHash
        var qualityHashes = song.kugouQualityHashes
        var albumAudioId = song.kugouAlbumAudioId
        var albumId = song.kugouAlbumId
        if Self.qualityHashCandidates(primary: primary, qualityHashes: qualityHashes, quality: requestedQuality).isEmpty,
           let completed = try? await completePlaybackMetadata(for: song) {
            primary = completed.kugouHash ?? primary
            qualityHashes = completed.kugouQualityHashes ?? qualityHashes
            albumAudioId = completed.kugouAlbumAudioId ?? albumAudioId
            albumId = completed.kugouAlbumId ?? albumId
            BeansLogger.shared.log("酷狗播放元数据补齐：\(song.name) hash=\((primary ?? "").isEmpty ? "无" : "有") albumAudioId=\(albumAudioId ?? "")", level: .debug)
        }
        let hashes = Self.qualityHashCandidates(primary: primary, qualityHashes: qualityHashes, quality: requestedQuality)
        guard !hashes.isEmpty else { return nil }
        return try await songURL(hashes: hashes, albumAudioId: albumAudioId, albumId: albumId, quality: requestedQuality)
    }

    func songURL(hash: String, albumAudioId: String?, albumId: String?) async throws -> String? {
        try await songURL(hashes: [hash], albumAudioId: albumAudioId, albumId: albumId, quality: BeansAudioQuality.current)
    }

    private func songURL(hashes: [String], albumAudioId: String?, albumId: String?, quality: BeansAudioQuality) async throws -> String? {
        let auth = KugouMusicAuth.shared
        let vipTypes = Self.vipTypeCandidates(auth.vipType, loggedIn: auth.isLoggedIn)
        var lastCode = 0
        var lastStatus = 0
        for hash in hashes {
            for vipType in vipTypes {
                let result = try await songURLOnce(hash: hash, albumAudioId: albumAudioId, albumId: albumId, vipType: vipType)
                lastCode = result.code
                lastStatus = result.status
                if let url = result.url, !url.isEmpty {
                    if vipType != auth.vipType {
                        BeansLogger.shared.log("酷狗播放地址命中：hash=\(hash.prefix(8)) vipType=\(vipType)", level: .debug)
                    }
                    return url
                }
            }
            // 酷狗新版客户端使用 v5/url。旧版 i/v2 在部分新曲和会员曲目上
            // 只返回 status，不返回播放地址，因此再尝试一次官方新版通道。
            for vipType in vipTypes {
                let v5 = try await songURLV5Once(hash: hash, albumAudioId: albumAudioId, albumId: albumId, vipType: vipType, quality: quality)
                lastCode = v5.code
                lastStatus = v5.status
                if let url = v5.url, !url.isEmpty {
                    if vipType != auth.vipType {
                        BeansLogger.shared.log("酷狗 v5 播放地址命中：hash=\(hash.prefix(8)) vipType=\(vipType)", level: .debug)
                    }
                    return url
                }
            }
            let web = try await songURLWebOnce(hash: hash, albumAudioId: albumAudioId, albumId: albumId)
            lastCode = web.code
            lastStatus = web.status
            if let url = web.url, !url.isEmpty { return url }
        }
        let vipTypeText = vipTypes.map(String.init).joined(separator: "/")
        BeansLogger.shared.log("酷狗播放地址为空：hash候选=\(hashes.count) vipType=\(vipTypeText) 已登录=\(auth.isLoggedIn ? "是" : "否") token=\(auth.token.isEmpty ? "无" : "有") dfid=\(auth.dfid.isEmpty ? "无" : "有") status=\(lastStatus) code=\(lastCode)", level: .debug)
        return nil
    }

    /// 酷狗官方新版播放地址接口，参数结构与酷狗客户端的 v5/url 通道一致。
    private func songURLV5Once(hash: String, albumAudioId: String?, albumId: String?, vipType: Int, quality requestedQuality: BeansAudioQuality) async throws -> (url: String?, status: Int, code: Int) {
        let auth = KugouMusicAuth.shared
        var components = URLComponents(string: "\(gateway)/v5/url")!
        let quality: String
        switch requestedQuality {
        case .standard:
            quality = "128"
        case .higher, .exhigh:
            quality = "320"
        case .lossless:
            quality = "flac"
        case .hires:
            quality = "hires"
        }
        let userId = auth.userId.isEmpty ? "0" : auth.userId
        let fileHash = hash.lowercased()
        var params: [String: String] = [
            "album_id": albumId ?? "0",
            "area_code": "1",
            "hash": fileHash,
            "ssa_flag": "is_fromtrack",
            "version": "11430",
            "quality": quality,
            "behavior": "play",
            "pid": "2",
            "pidversion": "3001",
            "cmd": "26",
            "appid": playAppid,
            "page_id": "151369488",
            "ppage_id": "463467626,350369493,788954147",
            "cdnBackup": "1",
            "module": "",
            "clientver": playClientver,
            "dfid": auth.dfid,
            "mid": auth.mid,
            "userid": userId,
            "token": auth.token,
            "vipType": "\(vipType)",
            "IsFreePart": vipType > 0 ? "0" : "1",
            "key": "\(fileHash)\(playSignSalt)\(playAppid)\(auth.mid)\(userId)".kgMD5Hex,
        ]
        if let albumAudioId, !albumAudioId.isEmpty {
            params["album_audio_id"] = albumAudioId
        }
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.setValue(playbackUA, forHTTPHeaderField: "User-Agent")
        request.setValue("trackercdn.kugou.com", forHTTPHeaderField: "x-router")
        request.setValue(auth.dfid, forHTTPHeaderField: "dfid")
        request.setValue(auth.mid, forHTTPHeaderField: "mid")
        request.setValue(auth.cookieHeader, forHTTPHeaderField: "Cookie")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return (nil, 0, -1) }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = Self.deepInt(json, names: ["status", "result"])
        let code = Self.deepInt(json, names: ["error_code", "errcode", "code"])
        let raw = Self.deepString(json, names: ["play_url", "play_backup_url", "url", "src", "backup_url"])
        return (raw.isEmpty ? nil : raw, status, code)
    }

    /// 网页播放通道。部分帐号登录态在移动端 tracker 返回 20006 时，网页接口仍会返回授权后的播放地址。
    private func songURLWebOnce(hash: String, albumAudioId: String?, albumId: String?) async throws -> (url: String?, status: Int, code: Int) {
        let auth = KugouMusicAuth.shared
        var components = URLComponents(string: "https://wwwapi.kugou.com/yy/index.php")!
        var params: [String: String] = [
            "r": "play/getdata",
            "hash": hash.uppercased(),
            "appid": "1014",
            "platid": "4",
            "mid": auth.mid,
            "dfid": auth.dfid,
            "userid": auth.userId.isEmpty ? "0" : auth.userId,
            "token": auth.token,
        ]
        if let albumId, !albumId.isEmpty { params["album_id"] = albumId }
        if let albumAudioId, !albumAudioId.isEmpty { params["album_audio_id"] = albumAudioId }
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.setValue(Self.browserUA, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.kugou.com/", forHTTPHeaderField: "Referer")
        request.setValue(auth.cookieHeader, forHTTPHeaderField: "Cookie")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return (nil, 0, -1) }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = Self.deepInt(json, names: ["status", "result"])
        let code = Self.deepInt(json, names: ["error_code", "errcode", "code"])
        let raw = Self.deepString(json, names: ["play_url", "play_backup_url", "url", "src", "backup_url"])
        return (raw.isEmpty ? nil : raw, status, code)
    }

    private func completePlaybackMetadata(for song: Song) async throws -> Song? {
        let keyword = ([song.name, song.artists].filter { !$0.isEmpty }).joined(separator: " ")
        guard !keyword.isEmpty else { return nil }
        let candidates = try await searchSongs(keyword: keyword, limit: 8)
        let targetDuration = song.duration
        return candidates.first { candidate in
            if let expected = song.kugouAlbumAudioId,
               let actual = candidate.kugouAlbumAudioId,
               !expected.isEmpty,
               expected == actual {
                return true
            }
            let nameOK = candidate.name == song.name
            let artistOK = song.artists.isEmpty || candidate.artists.contains(song.artists) || song.artists.contains(candidate.artists)
            let durationOK = targetDuration <= 0 || abs(candidate.duration - targetDuration) < 12
            return nameOK && artistOK && durationOK
        } ?? candidates.first
    }

    private func songURLOnce(hash: String, albumAudioId: String?, albumId: String?, vipType: Int) async throws -> (url: String?, status: Int, code: Int) {
        let auth = KugouMusicAuth.shared
        let h = hash.uppercased()
        var comps = URLComponents(string: "https://trackercdn.kugou.com/i/v2/")!
        var params: [String: String] = [
            "cmd": "26",
            "hash": h,
            "behavior": "play",
            "appid": appid,
            "pid": "2",
            "mid": auth.mid,
            "userid": auth.userId.isEmpty ? "0" : auth.userId,
            "version": clientver,
            "vipType": "\(vipType)",
            "token": auth.token.isEmpty ? "0" : auth.token,
            "key": "\(h)\(playSalt)\(appid)\(auth.mid)\(auth.userId.isEmpty ? "0" : auth.userId)".kgMD5Hex,
        ]
        if let albumAudioId, !albumAudioId.isEmpty { params["album_audio_id"] = albumAudioId }
        if let albumId, !albumId.isEmpty { params["album_id"] = albumId }
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: comps.url!)
        request.setValue(androidUA, forHTTPHeaderField: "User-Agent")
        request.setValue(auth.cookieHeader, forHTTPHeaderField: "Cookie")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return (nil, 0, -1) }
        var text = String(data: data, encoding: .utf8) ?? ""
        text = text.replacingOccurrences(of: "<!--KG_TAG_RES_START-->", with: "").replacingOccurrences(of: "<!--KG_TAG_RES_END-->", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return (nil, 0, -2) }
        let status = Self.deepInt(json, names: ["status"])
        let code = Self.deepInt(json, names: ["error_code", "errcode", "code"])
        let raw = Self.deepString(json, names: ["play_url", "play_backup_url", "url", "src", "backup_url"])
        return (raw.isEmpty ? nil : raw, status, code)
    }

    private func refreshMembershipStatusIfNeeded(force: Bool = false) async {
        let auth = KugouMusicAuth.shared
        guard auth.isLoggedIn, !auth.hasMembership else { return }
        if !force, let lastMembershipProbeAt, Date().timeIntervalSince(lastMembershipProbeAt) < 300 {
            return
        }
        lastMembershipProbeAt = Date()
        for listID in ["3", "2"] {
            do {
                let body: [String: Any] = [
                    "listid": listID,
                    "page": 1,
                    "pagesize": 1,
                    "area_code": 1,
                    "show_relate_goods": 0,
                    "allplatform": 1,
                    "show_cover": 1,
                    "type": 0,
                    "userid": Int(auth.userId) ?? 0,
                    "token": auth.token,
                ]
                let json = try await cloudlistRequest("/v4/get_list_all_file", params: ["listid": listID, "page": "1", "pagesize": "1"], data: body)
                guard let first = Self.deepArrays(json, names: ["songs", "songlist", "list", "info", "files", "data"]).first else { continue }
                guard let song = Self.mapTrack(first), let hash = song.kugouHash, !hash.isEmpty else { continue }
                let probe = try await songURLOnce(hash: hash, albumAudioId: song.kugouAlbumAudioId, albumId: song.kugouAlbumId, vipType: 1)
                if let url = probe.url, !url.isEmpty {
                    KugouMusicAuth.shared.updateVIPType(1)
                    BeansLogger.shared.log("酷狗会员状态补齐：播放探测成功 listid=\(listID) vipType=1", level: .debug)
                    return
                }
                BeansLogger.shared.log("酷狗会员状态探测未命中：listid=\(listID) status=\(probe.status) code=\(probe.code)", level: .debug)
            } catch {
                BeansLogger.shared.log("酷狗会员状态探测失败：listid=\(listID) \(error.localizedDescription)", level: .debug)
            }
        }
    }

    func lyric(hash: String, duration: TimeInterval) async -> String {
        guard !hash.isEmpty else { return "" }
        var search = URLComponents(string: "http://lyrics.kugou.com/search")!
        search.queryItems = [
            URLQueryItem(name: "ver", value: "1"),
            URLQueryItem(name: "man", value: "yes"),
            URLQueryItem(name: "client", value: "pc"),
            URLQueryItem(name: "hash", value: hash.uppercased()),
            URLQueryItem(name: "duration", value: "\(Int(duration * 1000))"),
        ]
        guard let sjson = try? await getJSON(search.url!, ua: Self.browserUA),
              let first = (sjson["candidates"] as? [[String: Any]])?.first,
              let id = first["id"], let accessKey = first["accesskey"] else { return "" }
        var download = URLComponents(string: "http://lyrics.kugou.com/download")!
        download.queryItems = [
            URLQueryItem(name: "ver", value: "1"),
            URLQueryItem(name: "client", value: "pc"),
            URLQueryItem(name: "id", value: "\(id)"),
            URLQueryItem(name: "accesskey", value: "\(accessKey)"),
            URLQueryItem(name: "fmt", value: "lrc"),
            URLQueryItem(name: "charset", value: "utf8"),
        ]
        guard let djson = try? await getJSON(download.url!, ua: Self.browserUA),
              let content = djson["content"] as? String,
              let data = Data(base64Encoded: content.replacingOccurrences(of: "\n", with: "")) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - 酷狗评论

    struct KugouCommentPage {
        let comments: [SongComment]
        let total: Int
    }

    /// 酷狗官方移动评论接口。评论读取不依赖会员权限。
    func comments(mixSongID: String, hash: String?, page: Int = 1, limit: Int = 30) async throws -> KugouCommentPage {
        var commentID = mixSongID.trimmingCharacters(in: .whitespacesAndNewlines)
        if commentID.isEmpty || Int(commentID) == nil {
            commentID = try await commentAudioID(hash: hash) ?? commentID
        }
        guard !commentID.isEmpty else {
            throw NetEaseError.unknown("酷狗评论缺少歌曲 ID")
        }
        let params = [
            "mixsongid": commentID,
            "need_show_image": "1",
            "p": "\(max(page, 1))",
            "pagesize": "\(min(max(limit, 1), 30))",
            "show_classify": "1",
            "show_hotword_list": "1",
            "extdata": "0",
            "code": "fc4be23b4e972707f36b8a828a93ba8a",
        ]
        let json: [String: Any]
        do {
            let response = try await gatewayRequest(
                "/mcomment/v1/cmtlist",
                baseURL: gateway,
                method: "POST",
                params: params,
                headers: ["x-router": "mcomment.service.kugou.com"]
            )
            json = response.json
        } catch {
            BeansLogger.shared.log("酷狗评论 POST 失败：\(error.localizedDescription)，尝试 GET 兜底", level: .debug)
            do {
                json = try await gatewayCommentJSON(params: params)
            } catch {
                BeansLogger.shared.log("酷狗评论 gateway 全部失败：\(error.localizedDescription)，尝试旧版评论接口", level: .debug)
                json = try await legacyCommentJSON(childrenID: commentID, page: page, limit: limit)
            }
        }
        let parsed = Self.parseComments(json: json, page: page, songName: commentID)
        if parsed.comments.isEmpty, let legacy = try? await legacyCommentJSON(childrenID: commentID, page: page, limit: limit) {
            return Self.parseComments(json: legacy, page: page, songName: commentID)
        }
        return parsed
    }

    private func gatewayCommentJSON(params: [String: String]) async throws -> [String: Any] {
        do {
            let response = try await gatewayRequest(
                "/mcomment/v1/cmtlist",
                baseURL: gateway,
                method: "GET",
                params: params,
                headers: ["x-router": "mcomment.service.kugou.com"]
            )
            return response.json
        } catch {
            BeansLogger.shared.log("酷狗评论 GET 失败：\(error.localizedDescription)，尝试备用路由", level: .debug)
            let response = try await gatewayRequest(
                "/m.comment.service/v1/cmtlist",
                baseURL: gateway,
                method: "GET",
                params: params,
                headers: ["x-router": "m.comment.service.kugou.com"]
            )
            return response.json
        }
    }

    private func legacyCommentJSON(childrenID: String, page: Int, limit: Int) async throws -> [String: Any] {
        var components = URLComponents(string: "http://m.comment.service.kugou.com/index.php")!
        components.queryItems = [
            URLQueryItem(name: "r", value: "commentsv2/getCommentWithLike"),
            URLQueryItem(name: "childrenid", value: childrenID),
            URLQueryItem(name: "code", value: "fc4be23b4e972707f36b8a828a93ba8a"),
            URLQueryItem(name: "extdata", value: "0"),
            URLQueryItem(name: "p", value: "\(max(page, 1))"),
            URLQueryItem(name: "pagesize", value: "\(min(max(limit, 1), 30))"),
        ]
        guard let url = components.url else { throw NetEaseError.network }
        return try await getJSON(url, ua: Self.browserUA)
    }

    private func commentAudioID(hash: String?) async throws -> String? {
        guard let hash, !hash.isEmpty else { return nil }
        var components = URLComponents(string: "https://wwwapi.kugou.com/yy/index.php")!
        components.queryItems = [
            URLQueryItem(name: "r", value: "play/getdata"),
            URLQueryItem(name: "hash", value: hash.uppercased()),
            URLQueryItem(name: "appid", value: "1014"),
            URLQueryItem(name: "platid", value: "4"),
        ]
        guard let url = components.url else { return nil }
        let json = try await getJSON(url, ua: Self.browserUA)
        let value = Self.deepString(json, names: ["album_audio_id", "audio_id", "mixsongid", "songid", "id"])
        return value.isEmpty ? nil : value
    }

    private static func parseComments(json: [String: Any], page: Int, songName: String) -> KugouCommentPage {
        let rows = Self.deepArrays(
            json,
            names: ["commentlist", "comments", "list", "comment", "hot_comment", "hot_comments"]
        )
        var seen = Set<Int>()
        let comments = rows.compactMap { raw -> SongComment? in
            let rawID = Self.string(raw["commentid"] ?? raw["comment_id"] ?? raw["id"] ?? raw["cid"])
            let content = Self.clean(Self.string(
                raw["content"] ?? raw["comment_content"] ?? raw["commentContent"] ?? raw["text"]
            ))
            guard !content.isEmpty else { return nil }
            let nickname = Self.clean(Self.string(
                raw["nick"] ?? raw["nickname"] ?? raw["username"] ?? raw["user_name"] ?? raw["author"]
            ))
            let avatar = Self.string(
                raw["avatarurl"] ?? raw["avatar_url"] ?? raw["avatar"] ?? raw["user_pic"] ?? raw["headurl"]
            )
            let timestamp = Self.double(
                raw["addtime"] ?? raw["add_time"] ?? raw["time"] ?? raw["timestamp"] ?? raw["created_at"]
            )
            let seconds = timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp
            let id = rawID.isEmpty ? abs(content.hashValue) : abs(rawID.hashValue)
            guard seen.insert(id).inserted else { return nil }
            return SongComment(
                id: id,
                content: content,
                nickname: nickname.isEmpty ? "酷狗用户" : nickname,
                avatarURL: avatar.isEmpty ? nil : URL(string: avatar),
                time: seconds > 0 ? Date(timeIntervalSince1970: seconds) : Date(),
                likedCount: Self.int(raw["praisenum"] ?? raw["like_count"] ?? raw["liked_count"] ?? raw["likes"]),
                isHot: page == 1
            )
        }
        let total = Self.deepInt(json, names: ["total", "commenttotal", "comment_total", "count"])
        BeansLogger.shared.log("酷狗评论：mixsongid=\(songName) page=\(page) 返回 \(comments.count) 条", level: .debug)
        return KugouCommentPage(comments: comments, total: total)
    }

    private func registerDevice() async {
        let auth = KugouMusicAuth.shared
        let guid = auth.guid.isEmpty ? UUID().uuidString : auth.guid
        let dataMap: [String: Any] = [
            "availableRamSize": 4983533568,
            "availableRomSize": 48114719,
            "availableSDSize": 48114717,
            "basebandVer": "",
            "batteryLevel": 100,
            "batteryStatus": 3,
            "brand": "Redmi",
            "buildSerial": "unknown",
            "device": "marble",
            "imei": guid,
            "imsi": "",
            "manufacturer": "Xiaomi",
            "uuid": guid,
            "accelerometer": false,
            "gyroscope": false,
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dataMap),
              let aes = Self.randomLower(6),
              let encrypted = Self.aesCBCEncrypt(jsonData, password: aes),
              let pData = try? JSONSerialization.data(withJSONObject: ["aes": aes, "uid": Int(auth.userId) ?? 0, "token": auth.token]),
              let rsa = Self.rsaEncryptPKCS1(pData, publicKeyBase64: rsaPublicKeyBase64) else { return }
        do {
            let response = try await gatewayRequest(
                "/risk/v2/r_register_dev",
                baseURL: userService,
                method: "POST",
                params: ["part": "1", "platid": "1", "p": rsa.kgHexString],
                dataRaw: encrypted,
                headers: [
                    "x-router": "userservice.kugou.com",
                    "Content-Type": "application/octet-stream",
                ],
                responseAsData: true
            )
            var json: [String: Any]?
            if let parsed = try? JSONSerialization.jsonObject(with: response.rawData) as? [String: Any] {
                json = parsed
            } else if let decrypted = Self.aesCBCDecrypt(response.rawData, password: aes),
                      let parsed = try? JSONSerialization.jsonObject(with: decrypted) as? [String: Any] {
                json = parsed
            }
            let dfid = Self.deepString(json ?? [:], names: ["dfid"])
            if !dfid.isEmpty { KugouMusicAuth.shared.saveDeviceDFID(dfid) }
            BeansLogger.shared.log("酷狗设备注册：dfid=\(dfid.isEmpty ? "未返回" : "已获取")", level: .debug)
        } catch {
            BeansLogger.shared.log("酷狗设备注册失败：\(error.localizedDescription)", level: .debug)
        }
    }

    private enum SignType { case android, web }
    private struct RawResponse { let json: [String: Any]; let rawData: Data }

    private func cloudlistRequest(_ path: String, params: [String: String], data: [String: Any]) async throws -> [String: Any] {
        let auth = KugouMusicAuth.shared
        var final = baseParams()
        final["userid"] = auth.userId
        final["token"] = auth.token
        params.forEach { final[$0.key] = $0.value }
        let body = try JSONSerialization.data(withJSONObject: data)
        final["signature"] = androidSignature(params: final, data: String(data: body, encoding: .utf8) ?? "")
        let response = try await request(path, baseURL: gateway, method: body.isEmpty ? "GET" : "POST", params: final, body: body, headers: [
            "User-Agent": androidUA,
            "x-router": "cloudlist.service.kugou.com",
            "kg-rc": "1",
            "kg-thash": "5d816a0",
            "kg-rec": "1",
            "kg-rf": "B9EDA08A64250DEFFBCADDEE00F8F25F",
            "dfid": auth.dfid,
            "mid": auth.mid,
            "Content-Type": "application/json",
            "Cookie": auth.cookieHeader,
        ])
        return response.json
    }

    private func gatewayRequest(_ path: String, baseURL: String? = nil, method: String = "GET", signType: SignType = .android, params: [String: String] = [:], data: [String: Any]? = nil, dataRaw: Data? = nil, headers: [String: String] = [:], responseAsData: Bool = false) async throws -> RawResponse {
        var final = baseParams()
        params.forEach { final[$0.key] = $0.value }
        let body = try data.map { try JSONSerialization.data(withJSONObject: $0) } ?? dataRaw
        let bodyString = body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        final["signature"] = signType == .web ? webSignature(params: final) : androidSignature(params: final, data: bodyString)
        var requestHeaders = [
            "User-Agent": androidUA,
            "kg-rc": "1",
            "kg-thash": "5d816a0",
            "kg-rec": "1",
            "kg-rf": "B9EDA08A64250DEFFBCADDEE00F8F25F",
            "dfid": KugouMusicAuth.shared.dfid,
            "mid": KugouMusicAuth.shared.mid,
            "clienttime": final["clienttime"] ?? "",
        ]
        if !KugouMusicAuth.shared.cookieHeader.isEmpty { requestHeaders["Cookie"] = KugouMusicAuth.shared.cookieHeader }
        headers.forEach { requestHeaders[$0.key] = $0.value }
        let response = try await request(path, baseURL: baseURL ?? gateway, method: method, params: final, body: body, headers: requestHeaders)
        if responseAsData { return response }
        return response
    }

    private func request(_ path: String, baseURL: String, method: String, params: [String: String], body: Data?, headers: [String: String]) async throws -> RawResponse {
        guard var comps = URLComponents(string: baseURL + path) else { throw NetEaseError.network }
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url else { throw NetEaseError.network }
        var request = URLRequest(url: url)
        request.httpMethod = method
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw NetEaseError.network }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return RawResponse(json: json, rawData: data)
    }

    private func baseParams() -> [String: String] {
        let auth = KugouMusicAuth.shared
        var p = [
            "dfid": auth.dfid,
            "mid": auth.mid,
            "uuid": "-",
            "appid": appid,
            "clientver": clientver,
            "clienttime": "\(Int(Date().timeIntervalSince1970))",
        ]
        if auth.isLoggedIn {
            p["token"] = auth.token
            p["userid"] = auth.userId
        }
        return p
    }

    private func androidSignature(params: [String: String], data: String) -> String {
        let body = params.keys.sorted().map { "\($0)=\(params[$0] ?? "")" }.joined()
        return "\(androidSignKey)\(body)\(data)\(androidSignKey)".kgMD5Hex
    }

    private func webSignature(params: [String: String]) -> String {
        let body = params.keys.sorted().map { "\($0)=\(params[$0] ?? "")" }.joined()
        return "\(webSignKey)\(body)\(webSignKey)".kgMD5Hex
    }

    private func getJSON(_ url: URL, ua: String) async throws -> [String: Any] {
        try await getJSON(url, ua: ua, headers: [:])
    }

    private func getJSON(_ url: URL, ua: String, headers: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw NetEaseError.network }
        return obj
    }

    private func getString(_ url: URL, ua: String) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.kugou.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else { throw NetEaseError.network }
        return text
    }

    private static func searchSignature(_ params: [String: String]) -> String {
        let body = params
            .filter { $0.key != "signature" }
            .keys
            .sorted()
            .map { "\($0)=\(params[$0] ?? "")" }
            .joined()
        return "y9tjae~n)k)vn[8\(body)y9tjae~n)k)vn[8".kgMD5Hex
    }

    private static func javascriptArray(named name: String, in html: String) -> [[String: Any]]? {
        guard let startRange = html.range(of: "\(name) = [") ?? html.range(of: "\(name)=[") else { return nil }
        guard let openIndex = html[startRange.lowerBound...].firstIndex(of: "[") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var endIndex: String.Index?
        var index = openIndex
        while index < html.endIndex {
            let char = html[index]
            if inString {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                }
            } else if char == "\"" {
                inString = true
            } else if char == "[" {
                depth += 1
            } else if char == "]" {
                depth -= 1
                if depth == 0 {
                    endIndex = html.index(after: index)
                    break
                }
            }
            index = html.index(after: index)
        }
        guard let endIndex else { return nil }
        let jsonText = String(html[openIndex..<endIndex])
        guard let data = jsonText.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return rows
    }

    private static func regexMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: nsrange).map { match in
            (0..<match.numberOfRanges).map { index in
                guard let range = Range(match.range(at: index), in: text) else { return "" }
                return String(text[range])
            }
        }
    }

    private static func normalizeURL(_ value: String) -> String {
        if value.hasPrefix("//") { return "https:" + value }
        if value.hasPrefix("http://") { return "https://" + String(value.dropFirst("http://".count)) }
        return value
    }

    private static func htmlDecode(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func mapCompleteTrack(_ raw: [String: Any]) -> Song? {
        var normalized = raw
        if normalized["singername"] == nil,
           let authors = raw["authors"] as? [[String: Any]] {
            let names = authors.compactMap { author -> String? in
                let name = string(author["author_name"] ?? author["name"])
                return name.isEmpty ? nil : name
            }
            if !names.isEmpty { normalized["singername"] = names.joined(separator: " / ") }
        }
        normalized["songname"] = raw["SongName"] ?? raw["FileName"] ?? raw["songname"]
        normalized["filename"] = raw["FileName"] ?? raw["SongName"] ?? raw["filename"]
        normalized["singername"] = raw["SingerName"] ?? raw["singername"] ?? normalized["singername"]
        normalized["album_name"] = raw["AlbumName"] ?? raw["album_name"]
        normalized["hash"] = raw["FileHash"] ?? raw["Hash"] ?? raw["hash"]
        normalized["mixsongid"] = raw["MixSongID"] ?? raw["mixsongid"] ?? raw["audio_id"] ?? raw["audioid"] ?? raw["encrypt_id"]
        normalized["audio_id"] = raw["audio_id"] ?? raw["audioid"] ?? raw["encrypt_id"]
        normalized["album_id"] = raw["AlbumID"] ?? raw["album_id"]
        normalized["duration"] = raw["Duration"] ?? raw["duration"] ?? raw["timeLen"] ?? raw["timelength"]
        normalized["album_sizable_cover"] = raw["Image"] ?? raw["ImageUrl"] ?? raw["AlbumImg"] ?? raw["album_sizable_cover"]
        normalized["pay_type"] = raw["PayType"] ?? raw["Privilege"] ?? raw["pay_type"]
        normalized["feetype"] = raw["FeeType"] ?? raw["feetype"]
        normalized["privilege"] = raw["Privilege"] ?? raw["privilege"]
        normalized["pay_type_320"] = raw["PayType320"] ?? raw["pay_type_320"]
        normalized["pay_type_sq"] = raw["PayTypeSQ"] ?? raw["pay_type_sq"]
        return mapTrack(normalized)
    }

    private static func mapPlaylist(_ raw: [String: Any]) -> Playlist? {
        let id = int(raw["listid"] ?? raw["id"] ?? raw["global_collection_id"] ?? raw["specialid"])
        guard id > 0 else { return nil }
        let name = string(raw["name"] ?? raw["listname"] ?? raw["list_name"] ?? raw["specialname"] ?? raw["title"])
        let cover = string(raw["pic"] ?? raw["img"] ?? raw["cover"] ?? raw["sizable_cover"] ?? raw["list_pic"]).replacingOccurrences(of: "{size}", with: "240")
        let count = int(raw["count"] ?? raw["song_count"] ?? raw["total"] ?? raw["file_count"] ?? raw["songcount"])
        return Playlist(id: id, name: name.isEmpty ? "酷狗歌单" : name, coverURL: URL(string: cover), trackCount: count, source: .kugou)
    }

    private static func mapTrack(_ raw: [String: Any]) -> Song? {
        let trans = raw["trans_param"] as? [String: Any] ?? raw["transParam"] as? [String: Any] ?? [:]
        let qualityHashes = qualityHashes(raw: raw, trans: trans)
        let hash = string(raw["hash"] ?? raw["Hash"] ?? raw["file_hash"] ?? raw["FileHash"] ?? raw["audio_hash"] ?? qualityHashes["exhigh"] ?? qualityHashes["standard"] ?? qualityHashes["lossless"])
        let albumAudioId = string(raw["album_audio_id"] ?? raw["albumAudioId"] ?? raw["audio_id"] ?? raw["audioid"] ?? raw["mixsongid"] ?? raw["songid"] ?? raw["id"])
        let stable = abs((hash.isEmpty ? albumAudioId : hash).hashValue)
        var title = clean(string(raw["songname"] ?? raw["song_name"] ?? raw["name"] ?? raw["title"]))
        var artist = clean(string(raw["singername"] ?? raw["singer_name"] ?? raw["author_name"] ?? raw["singer"] ?? raw["artist"]))
        let filename = clean(string(raw["filename"] ?? raw["FileName"]))
        if !filename.isEmpty {
            let parts = filename.components(separatedBy: " - ")
            if parts.count >= 2 {
                if artist.isEmpty { artist = clean(parts[0]) }
                if title.isEmpty || title == filename { title = clean(parts.dropFirst().joined(separator: " - ")) }
            } else if title.isEmpty {
                title = filename
            }
        }
        guard !title.isEmpty, !hash.isEmpty || !albumAudioId.isEmpty else { return nil }
        let album = string(raw["album_name"] ?? raw["albumname"] ?? raw["album"] ?? (raw["albuminfo"] as? [String: Any])?["name"])
        let cover = normalizeURL(
            string(raw["pic"] ?? raw["img"] ?? raw["image"] ?? raw["cover"] ?? raw["album_sizable_cover"] ?? raw["sizable_cover"] ?? trans["union_cover"])
                .replacingOccurrences(of: "{size}", with: "300")
        )
        let durRaw = double(raw["timelength"] ?? raw["time_length"] ?? raw["timelen"] ?? raw["duration"] ?? raw["interval"])
        let seconds = durRaw > 1000 ? durRaw / 1000.0 : durRaw
        return Song(
            id: stable,
            name: title,
            artists: artist.isEmpty ? clean(string(raw["h5_author_name"] ?? raw["authors"])) : artist,
            album: album,
            coverURL: URL(string: cover),
            duration: seconds,
            source: .kugou,
            kugouHash: hash,
            kugouAlbumAudioId: albumAudioId,
            kugouAlbumId: string(raw["album_id"] ?? raw["albumid"] ?? raw["AlbumID"] ?? raw["albumId"]),
            kugouQualityHashes: qualityHashes.isEmpty ? nil : qualityHashes,
            fee: kugouVIPFee(raw)
        )
    }

    private static func mergeRankCovers(primary: [Song], fallback: [Song]) -> [Song] {
        var byHash: [String: Song] = [:]
        var byAudioId: [String: Song] = [:]
        var byTitle: [String: Song] = [:]
        for song in fallback where song.coverURL != nil {
            if let hash = song.kugouHash?.lowercased(), !hash.isEmpty { byHash[hash] = song }
            if let audioId = song.kugouAlbumAudioId, !audioId.isEmpty { byAudioId[audioId] = song }
            byTitle[rankCoverMatchKey(song)] = song
        }
        return primary.map { song in
            guard song.coverURL == nil else { return song }
            let fallbackSong: Song?
            if let hash = song.kugouHash?.lowercased(), !hash.isEmpty, let hit = byHash[hash] {
                fallbackSong = hit
            } else if let audioId = song.kugouAlbumAudioId, !audioId.isEmpty, let hit = byAudioId[audioId] {
                fallbackSong = hit
            } else {
                fallbackSong = byTitle[rankCoverMatchKey(song)]
            }
            guard let coverURL = fallbackSong?.coverURL else { return song }
            return Song(
                id: song.id,
                name: song.name,
                artists: song.artists,
                album: song.album,
                coverURL: coverURL,
                duration: song.duration,
                source: song.source,
                qqMid: song.qqMid,
                qqMediaMid: song.qqMediaMid,
                kugouHash: song.kugouHash,
                kugouAlbumAudioId: song.kugouAlbumAudioId,
                kugouAlbumId: song.kugouAlbumId,
                kugouQualityHashes: song.kugouQualityHashes,
                fee: song.fee
            )
        }
    }

    private static func rankCoverMatchKey(_ song: Song) -> String {
        "\(song.name)|\(song.artists)".lowercased()
    }

    private static func qualityHashes(raw: [String: Any], trans: [String: Any]) -> [String: String] {
        let values: [(String, String)] = [
            ("standard", string(raw["128hash"] ?? raw["hash"] ?? raw["Hash"] ?? raw["file_hash"] ?? raw["FileHash"] ?? trans["ogg_128_hash"])),
            ("exhigh", string(raw["320hash"] ?? raw["HQFileHash"] ?? trans["ogg_320_hash"] ?? raw["hash"] ?? raw["Hash"] ?? raw["file_hash"] ?? raw["FileHash"])),
            ("lossless", string(raw["sqhash"] ?? raw["SQFileHash"] ?? raw["flac_hash"] ?? raw["hash"] ?? raw["Hash"] ?? raw["file_hash"] ?? raw["FileHash"])),
            ("hires", string(raw["hrhash"] ?? raw["high_hash"] ?? raw["sqhash"] ?? raw["SQFileHash"] ?? raw["hash"] ?? raw["Hash"] ?? raw["file_hash"] ?? raw["FileHash"])),
        ]
        var result: [String: String] = [:]
        for (key, value) in values where !value.isEmpty {
            result[key] = value
        }
        return result
    }

    private static func qualityHashCandidates(primary: String?, qualityHashes: [String: String]?, quality requestedQuality: BeansAudioQuality? = nil) -> [String] {
        let requested = requestedQuality ?? BeansAudioQuality.current
        let order: [String]
        switch requested {
        case .hires:
            order = ["hires", "lossless", "exhigh", "standard"]
        case .lossless:
            order = ["lossless", "exhigh", "standard"]
        case .exhigh, .higher:
            order = ["exhigh", "standard"]
        case .standard:
            order = ["standard"]
        }
        var seen = Set<String>()
        var result: [String] = []
        func append(_ value: String?) {
            let hash = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !hash.isEmpty, !seen.contains(hash) else { return }
            seen.insert(hash)
            result.append(hash)
        }
        for key in order { append(qualityHashes?[key]) }
        append(primary)
        ["hires", "lossless", "exhigh", "standard"].forEach { append(qualityHashes?[$0]) }
        return result
    }

    private static func vipTypeCandidates(_ vipType: Int, loggedIn: Bool) -> [Int] {
        let values = vipType > 0 ? [vipType, 6, 1, 0] : (loggedIn ? [1, 6, 0] : [0])
        var seen = Set<Int>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: #"\.(mp3|flac|m4a|aac|ogg|wav)$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func kugouVIPFee(_ raw: [String: Any]) -> Int {
        let explicitKeys: Set<String> = [
            "fee", "feetype", "fee_type", "pay_type", "paytype", "paytype320",
            "pay_type_320", "pay_type_sq", "media_pay_type", "needpay", "need_pay"
        ]
        let boolKeys: Set<String> = [
            "vip", "isvip", "is_vip", "onlyvipplayable", "only_vip_playable",
            "viprequired", "vip_required", "needvip", "need_vip"
        ]
        var explicit = 0
        var privilege = 0
        var flag = false
        func walk(_ value: Any) {
            if let dict = value as? [String: Any] {
                for (key, child) in dict {
                    let normalized = key
                        .replacingOccurrences(of: "_", with: "")
                        .replacingOccurrences(of: "-", with: "")
                        .lowercased()
                    let lower = key.lowercased()
                    if explicitKeys.contains(lower) || explicitKeys.contains(normalized) {
                        explicit = max(explicit, int(child))
                    }
                    if lower == "privilege" || lower == "media_privilege" || lower == "320privilege" || lower == "sqprivilege" {
                        privilege = max(privilege, int(child))
                    }
                    if boolKeys.contains(lower) || boolKeys.contains(normalized) {
                        if let bool = child as? Bool, bool { flag = true }
                        if int(child) > 0 { flag = true }
                        let text = string(child).lowercased()
                        if text == "true" || text.contains("vip") || text.contains("会员") { flag = true }
                    }
                    walk(child)
                }
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        walk(raw)
        if explicit > 0 { return explicit }
        if privilege >= 9 { return 1 }
        if flag { return 1 }
        return 0
    }

    private static func deepString(_ obj: Any, names: [String]) -> String {
        if let value = deepValue(obj, names: names), let array = value as? [Any] {
            return array.first.map { string($0) } ?? ""
        }
        return string(deepValue(obj, names: names))
    }

    private static func deepInt(_ obj: Any, names: [String]) -> Int { int(deepValue(obj, names: names)) }

    private static func deepArrays(_ obj: Any, names: [String]) -> [[String: Any]] {
        var best: [[String: Any]] = []
        func walk(_ value: Any) {
            if let array = value as? [[String: Any]], array.count > best.count {
                best = array
            } else if let dict = value as? [String: Any] {
                for (key, child) in dict {
                    if names.contains(where: { $0.lowercased() == key.lowercased() }) {
                        walk(child)
                    }
                }
                if best.isEmpty {
                    dict.values.forEach(walk)
                }
            } else if let array = value as? [Any] {
                for child in array { walk(child) }
            }
        }
        walk(obj)
        return best
    }

    private static func deepValue(_ obj: Any, names: [String]) -> Any? {
        let wanted = Set(names.map { $0.lowercased() })
        func walk(_ value: Any) -> Any? {
            if let dict = value as? [String: Any] {
                for (key, child) in dict where wanted.contains(key.lowercased()) {
                    return child
                }
                for child in dict.values {
                    if let found = walk(child) { return found }
                }
            } else if let array = value as? [Any] {
                for child in array {
                    if let found = walk(child) { return found }
                }
            }
            return nil
        }
        return walk(obj)
    }

    private static func string(_ value: Any?) -> String {
        if let s = value as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = value as? NSNumber { return n.stringValue }
        return ""
    }

    private static func int(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) ?? 0 }
        return 0
    }

    private static func double(_ value: Any?) -> Double {
        if let d = value as? Double { return d }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) ?? 0 }
        return 0
    }

    private static func urlEncode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
    }

    private static var browserUA: String {
        "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
    }

    private static func randomLower(_ length: Int) -> String? {
        let chars = Array("1234567890abcdefghijklmnopqrstuvwxyz")
        return String((0..<length).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }

    private static func aesCBCEncrypt(_ data: Data, password: String) -> Data? {
        let digest = password.kgMD5Hex
        return crypt(data, op: CCOperation(kCCEncrypt), key: Data(digest.prefix(16).utf8), iv: Data(digest.suffix(16).utf8))
    }

    private static func aesCBCDecrypt(_ data: Data, password: String) -> Data? {
        let digest = password.kgMD5Hex
        return crypt(data, op: CCOperation(kCCDecrypt), key: Data(digest.prefix(16).utf8), iv: Data(digest.suffix(16).utf8))
    }

    private static func crypt(_ data: Data, op: CCOperation, key: Data, iv: Data) -> Data? {
        var out = Data(count: data.count + kCCBlockSizeAES128)
        let outputCapacity = out.count
        var outLen = 0
        let status = out.withUnsafeMutableBytes { outPtr in
            data.withUnsafeBytes { dataPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(op, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), keyPtr.baseAddress, kCCKeySizeAES128, ivPtr.baseAddress, dataPtr.baseAddress, data.count, outPtr.baseAddress, outputCapacity, &outLen)
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        out.removeSubrange(outLen..<outputCapacity)
        return out
    }

    private static func rsaEncryptPKCS1(_ data: Data, publicKeyBase64: String) -> Data? {
        guard let keyData = Data(base64Encoded: publicKeyBase64) else { return nil }
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: 1024,
        ]
        guard let key = SecKeyCreateWithData(keyData as CFData, attrs as CFDictionary, nil) else { return nil }
        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(key, .rsaEncryptionPKCS1, data as CFData, &error) else { return nil }
        return encrypted as Data
    }
}

private extension Data {
    var kgHexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    var kgMD5Hex: String { Data(utf8).md5Hex() }
}
