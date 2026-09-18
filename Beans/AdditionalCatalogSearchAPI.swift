import CommonCrypto
import Compression
import CoreFoundation
import Foundation

enum AdditionalCatalogSearchError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "搜索服务暂未返回有效结果"
        }
    }
}

/// 仅负责补充目录搜索。实际播放仍统一走已导入音源的解析链路，避免把平台私有
/// 播放地址混入播放器。
enum AdditionalCatalogSearchAPI {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration)
    }()

    static func searchKuwo(keyword: String, limit: Int = 40) async throws -> [Song] {
        var components = URLComponents(string: "https://search.kuwo.cn/r.s")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "kt"),
            URLQueryItem(name: "all", value: keyword),
            URLQueryItem(name: "pn", value: "0"),
            URLQueryItem(name: "rn", value: String(min(max(limit, 1), 60))),
            URLQueryItem(name: "uid", value: "794762570"),
            URLQueryItem(name: "ver", value: "kwplayer_ar_9.2.2.1"),
            URLQueryItem(name: "vipver", value: "1"),
            URLQueryItem(name: "show_copyright_off", value: "1"),
            URLQueryItem(name: "newver", value: "1"),
            URLQueryItem(name: "ft", value: "music"),
            URLQueryItem(name: "cluster", value: "0"),
            URLQueryItem(name: "strategy", value: "2012"),
            URLQueryItem(name: "rformat", value: "json"),
            URLQueryItem(name: "encoding", value: "utf8"),
            URLQueryItem(name: "vermerge", value: "1"),
            URLQueryItem(name: "mobi", value: "1"),
            URLQueryItem(name: "issubtitle", value: "1"),
        ]
        let root = try await fetchObject(
            components.url!,
            headers: ["Referer": "https://www.kuwo.cn/", "User-Agent": browserUserAgent]
        )
        let list = (root["abslist"] as? [[String: Any]])
            ?? (root["data"] as? [[String: Any]])
            ?? []
        return list.compactMap(kuwoSong)
    }

    static func searchMigu(keyword: String, limit: Int = 40) async throws -> [Song] {
        let root = try await miguSongSearch(keyword: keyword, limit: limit)
        let pages = ((root["songResultData"] as? [String: Any])?["resultList"] as? [[Any]]) ?? []
        return pages.flatMap { $0 }.compactMap { $0 as? [String: Any] }.compactMap(miguSong)
    }

    /// The catalogue search uses the same mobile request family as the
    /// reference implementation. Playback continues to use Beans' existing
    /// source resolver after the result is selected.
    static func searchCatalogQQ(keyword: String, limit: Int = 40) async throws -> [Song] {
        for attempt in 0..<3 {
            let searchID = (0..<16).map { _ in String(Int.random(in: 0...9)) }.joined()
            let request: [String: Any] = [
                "comm": ["ct": "11", "cv": "14090508", "v": "14090508", "tmeAppID": "qqmusic",
                         "phonetype": "EBG-AN10", "deviceScore": "553.47", "devicelevel": "50",
                         "newdevicelevel": "20", "rom": "HuaWei/EMOTION/EmotionUI_14.2.0", "os_ver": "12",
                         "OpenUDID": "0", "OpenUDID2": "0", "QIMEI36": "0", "udid": "0", "chid": "0",
                         "aid": "0", "oaid": "0", "taid": "0", "tid": "0", "wid": "0", "uid": "0",
                         "sid": "0", "modeSwitch": "6", "teenMode": "0", "ui_mode": "2", "nettype": "1020",
                         "v4ip": ""],
                "req": ["module": "music.search.SearchCgiService", "method": "DoSearchForQQMusicMobile",
                        "param": ["search_type": 0, "searchid": searchID, "query": keyword, "page_num": 1,
                                  "num_per_page": min(max(limit, 1), 50), "highlight": 0, "nqc_flag": 0,
                                  "multi_zhida": 0, "cat": 2, "grp": 1, "sin": 0, "sem": 0]],
            ]
            do {
                let body = try JSONSerialization.data(withJSONObject: request)
                guard let sign = zzcSign(body) else { throw AdditionalCatalogSearchError.invalidResponse }
                var components = URLComponents(string: "https://u.y.qq.com/cgi-bin/musics.fcg")!
                components.queryItems = [URLQueryItem(name: "sign", value: sign)]
                var requestObject = URLRequest(url: components.url!)
                requestObject.httpMethod = "POST"
                requestObject.httpBody = body
                requestObject.setValue("application/json", forHTTPHeaderField: "Content-Type")
                requestObject.setValue("https://y.qq.com", forHTTPHeaderField: "Origin")
                requestObject.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
                requestObject.setValue("QQMusic 14090508(android 12)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: requestObject)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw AdditionalCatalogSearchError.invalidResponse
                }
                let songs = dictionaries(in: root["body"] ?? root["data"] ?? root)
                    .compactMap(qqCatalogSong)
                if !songs.isEmpty || attempt == 2 { return songs }
            } catch {
                if attempt == 2 { throw error }
            }
            try? await Task.sleep(nanoseconds: UInt64(220 * (attempt + 1)) * 1_000_000)
        }
        return []
    }

    static func searchCatalogKugou(keyword: String, limit: Int = 40) async throws -> [Song] {
        let variants: [(String, String, String)] = [
            ("https", "", "WebFilter"),
            ("http", "11089", "WebFilter"),
            ("http", "11409", "AndroidFilter"),
            ("https", "11089", "WebFilter"),
        ]
        for (scheme, clientVersion, platform) in variants {
            var components = URLComponents(string: "\(scheme)://songsearch.kugou.com/song_search_v2")!
            components.queryItems = [
                URLQueryItem(name: "keyword", value: keyword),
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "pagesize", value: String(min(max(limit, 1), 50))),
                URLQueryItem(name: "userid", value: "0"),
                URLQueryItem(name: "clientver", value: clientVersion),
                URLQueryItem(name: "platform", value: platform),
                URLQueryItem(name: "filter", value: "2"),
                URLQueryItem(name: "iscorrection", value: "1"),
                URLQueryItem(name: "privilege_filter", value: "0"),
                URLQueryItem(name: "area_code", value: "1"),
            ]
            guard let root = try? await fetchObject(components.url!),
                  int(root["error_code"]) == 0,
                  let data = root["data"] as? [String: Any] else { continue }
            let rows = dictionaries(in: data["lists"] ?? data["list"] ?? data["data"])
            let grouped = rows.flatMap { dictionaries(in: $0["Grp"]) }
            let songs = (rows + grouped).compactMap { kugouCatalogSong($0) }
            if !songs.isEmpty { return songs }
        }
        throw AdditionalCatalogSearchError.invalidResponse
    }

    static func searchKuwoPlaylists(keyword: String, limit: Int = 40) async throws -> [Playlist] {
        let root = try await kuwoSearch(keyword: keyword, limit: limit, type: "playlist")
        let items = dictionaries(in: root["abslist"] ?? root["playlist"] ?? root["list"] ?? root["data"])
        return items.compactMap { item in
            guard let id = int(item["playlistid"] ?? item["playlistId"] ?? item["id"]), id > 0 else { return nil }
            return Playlist(
                id: id,
                name: text(item["name"] ?? item["title"] ?? item["playlistname"]) ?? "未命名歌单",
                coverURL: kuwoImageURL(text(item["pic"] ?? item["img"] ?? item["cover"] ?? item["picurl"] ?? item["imgurl"] ?? item["PICPATH"] ?? item["image"])).flatMap(URL.init(string:)),
                trackCount: int(item["songnum"] ?? item["songcount"]) ?? 0,
                playCount: int(item["playcnt"] ?? item["playCount"]) ?? 0,
                creatorName: text(item["nickname"] ?? item["uname"] ?? item["creator"]) ?? "",
                playlistDescription: text(item["intro"] ?? item["desc"] ?? item["description"]) ?? "",
                source: .kuwo
            )
        }
    }

    static func searchKugouPlaylists(keyword: String, limit: Int = 40) async throws -> [Playlist] {
        var components = URLComponents(string: "https://msearchretry.kugou.com/api/v3/search/special")!
        components.queryItems = [
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pagesize", value: String(min(max(limit, 1), 60))),
            URLQueryItem(name: "showtype", value: "10"),
            URLQueryItem(name: "filter", value: "0"),
            URLQueryItem(name: "version", value: "7910"),
            URLQueryItem(name: "sver", value: "2"),
        ]
        let root = try await fetchObject(components.url!, headers: ["User-Agent": browserUserAgent])
        let items = dictionaries(in: root["info"] ?? root["special_list"] ?? root["list"] ?? root["data"])
        return items.compactMap { item in
            guard let id = int(item["specialid"] ?? item["specialId"]), id > 0 else { return nil }
            return Playlist(
                id: id,
                name: text(item["specialname"] ?? item["name"] ?? item["title"]) ?? "未命名歌单",
                coverURL: kugouImageURL(text(item["imgurl"] ?? item["img"] ?? item["cover"])).flatMap(URL.init(string:)),
                trackCount: int(item["songcount"] ?? item["songCount"]) ?? 0,
                playCount: int(item["playcount"] ?? item["playCount"]) ?? 0,
                creatorName: text(item["nickname"] ?? item["creator"]) ?? "",
                playlistDescription: text(item["intro"] ?? item["desc"] ?? item["description"]) ?? "",
                source: .kugou
            )
        }
    }

    static func searchMiguPlaylists(keyword: String, limit: Int = 40) async throws -> [Playlist] {
        let root = try await miguSearch(
            keyword: keyword,
            limit: limit,
            switchValue: "{\"song\":0,\"album\":0,\"singer\":0,\"tagSong\":0,\"mvSong\":0,\"bestShow\":0,\"songlist\":1,\"lyricSong\":0}"
        )
        let values = dictionaries(in: root["songListResultData"] ?? root["songlistResultData"] ?? root["result"] ?? root["data"])
        return values.compactMap { item in
            guard let id = int(item["id"] ?? item["playlistId"] ?? item["contentId"]), id > 0 else { return nil }
            return Playlist(
                id: id,
                name: text(item["name"] ?? item["title"] ?? item["listName"]) ?? "未命名歌单",
                coverURL: miguImageURL(text(item["musicListPicUrl"] ?? item["img"] ?? item["cover"])).flatMap(URL.init(string:)),
                trackCount: int(item["musicNum"] ?? item["songCount"]) ?? 0,
                playCount: int(item["playNum"] ?? item["playCount"]) ?? 0,
                creatorName: text(item["userName"] ?? item["nickname"]) ?? "",
                playlistDescription: text(item["description"] ?? item["summary"]) ?? "",
                source: .migu
            )
        }
    }

    static func playlistSongs(source: SongSource, id: Int) async throws -> [Song] {
        switch source {
        case .kuwo:
            var components = URLComponents(string: "https://nplserver.kuwo.cn/pl.svc")!
            components.queryItems = [
                URLQueryItem(name: "op", value: "getlistinfo"),
                URLQueryItem(name: "pid", value: String(id)),
                URLQueryItem(name: "pn", value: "0"),
                URLQueryItem(name: "rn", value: "1000"),
                URLQueryItem(name: "encode", value: "utf8"),
                URLQueryItem(name: "keyset", value: "pl2012"),
                URLQueryItem(name: "identity", value: "kuwo"),
                URLQueryItem(name: "pcmp4", value: "1"),
                URLQueryItem(name: "vipver", value: "MUSIC_9.0.5.0_W1"),
                URLQueryItem(name: "newver", value: "1"),
            ]
            let root = try await fetchObject(components.url!, headers: ["Referer": "https://www.kuwo.cn/", "User-Agent": browserUserAgent])
            return dictionaries(in: root["musiclist"] ?? root["songlist"] ?? root["tracks"] ?? root["list"] ?? root["data"]).compactMap(kuwoSong)
        case .migu:
            let url = URL(string: "https://app.c.nf.migu.cn/MIGUM3.0/resource/playlist/song/v2.0?pageNo=1&pageSize=1000&playlistId=\(id)")!
            let root = try await fetchObject(url, headers: ["Referer": "https://m.music.migu.cn/", "User-Agent": browserUserAgent])
            return dictionaries(in: root["songList"] ?? root["songlist"] ?? root["tracks"] ?? root["list"] ?? root["data"]).compactMap(miguSong)
        default:
            throw AdditionalCatalogSearchError.invalidResponse
        }
    }

    static func searchKuwoArtists(keyword: String, limit: Int = 40) async throws -> [Artist] {
        let root = try await kuwoSearch(keyword: keyword, limit: limit, type: "artist")
        return dictionaries(in: root["abslist"]).compactMap { item in
            guard let id = text(item["ARTISTID"] ?? item["id"]), let name = text(item["ARTIST"] ?? item["name"]), !name.isEmpty else { return nil }
            return Artist(id: id, name: name, coverURL: kuwoImageURL(text(item["PICPATH"])).flatMap(URL.init(string:)), source: .kuwo)
        }
    }

    static func searchKuwoAlbums(keyword: String, limit: Int = 40) async throws -> [Album] {
        let root = try await kuwoSearch(keyword: keyword, limit: limit, type: "album")
        return dictionaries(in: root["searchgroup"] ?? root["abslist"]).compactMap { item in
            guard let id = text(item["ALBUMID"] ?? item["id"] ?? item["albumid"]),
                  let name = text(item["ALBUM"] ?? item["album"] ?? item["name"]), !name.isEmpty else { return nil }
            return Album(id: id, name: name, artistName: text(item["ARTIST"] ?? item["artist"]) ?? "", coverURL: kuwoImageURL(text(item["PICPATH"] ?? item["albumpic"])).flatMap(URL.init(string:)), source: .kuwo)
        }
    }

    static func searchMiguArtists(keyword: String, limit: Int = 40) async throws -> [Artist] {
        let root = try await miguSearch(keyword: keyword, limit: limit, switchValue: "{\"song\":0,\"album\":0,\"singer\":1,\"tagSong\":0,\"mvSong\":0,\"songlist\":0,\"bestShow\":0}")
        return dictionaries(in: (root["singerResultData"] as? [String: Any])?["result"]).compactMap { item in
            guard let id = text(item["id"]), let name = text(item["name"]), !name.isEmpty else { return nil }
            return Artist(id: id, name: name, coverURL: miguImageURL(text(item["img"] ?? item["imgUrl"] ?? item["img1"] ?? item["img2"] ?? item["img3"] ?? item["singerPic"] ?? item["singerPicUrl"])).flatMap(URL.init(string:)), source: .migu)
        }
    }

    static func searchMiguAlbums(keyword: String, limit: Int = 40) async throws -> [Album] {
        let root = try await miguSearch(keyword: keyword, limit: limit, switchValue: "{\"song\":0,\"album\":1,\"singer\":0,\"tagSong\":0,\"mvSong\":0,\"songlist\":0,\"bestShow\":0}")
        return dictionaries(in: (root["albumResultData"] as? [String: Any])?["result"]).compactMap { item in
            guard let id = text(item["id"]), let name = text(item["name"]), !name.isEmpty else { return nil }
            return Album(id: id, name: name, artistName: text(item["singer"] ?? item["singerName"] ?? item["artist"] ?? item["artistName"]) ?? "", coverURL: miguImageURL(text(item["img"] ?? item["imgUrl"] ?? item["img1"] ?? item["img2"] ?? item["img3"] ?? item["albumPicUrl"] ?? item["albumPic"] ?? item["cover"])).flatMap(URL.init(string:)), source: .migu)
        }
    }

    static func hotKeywords(for source: SongSource) async throws -> [String] {
        switch source {
        case .kuwo:
            let url = URL(string: "https://hotword.kuwo.cn/hotword.s?prod=kwplayer_ar_9.3.0.1&corp=kuwo&newver=2&vipver=9.3.0.1&source=kwplayer_ar_9.3.0.1_40.apk&p2p=1&notrace=0&uid=0&plat=kwplayer_ar&rformat=json&encoding=utf8&tabid=1")!
            let root = try await fetchObject(url, headers: ["User-Agent": browserUserAgent])
            return ((root["tagvalue"] as? [[String: Any]]) ?? []).compactMap { text($0["key"]) }
        case .migu:
            let url = URL(string: "https://jadeite.migu.cn/music_search/v3/search/hotword")!
            let root = try await fetchObject(url, headers: ["Referer": "https://m.music.migu.cn/", "User-Agent": browserUserAgent])
            let groups = (((root["data"] as? [String: Any])?["hotwords"] as? [[String: Any]]) ?? [])
            return groups.flatMap { ($0["hotwordList"] as? [[String: Any]]) ?? [] }
                .filter { text($0["resourceType"]) == "song" }
                .compactMap { text($0["word"]) }
        default:
            return []
        }
    }

    /// 酷我和咪咕的目录搜索与歌词接口独立。播放地址仍由用户启用的音源解析，
    /// 这里仅返回同步歌词，避免播放页因没有官方歌词分支而长期为空。
    static func lyric(for song: Song) async throws -> String {
        switch song.source {
        case .kuwo:
            return try await kuwoLyric(songID: song.id)
        case .migu:
            return try await miguLyric(songID: song.id)
        default:
            throw AdditionalCatalogSearchError.invalidResponse
        }
    }

    private static func kuwoSong(_ item: [String: Any]) -> Song? {
        let rawID = text(item["MUSICRID"]) ?? text(item["id"]) ?? text(item["musicrid"])
        let idText = rawID?.replacingOccurrences(of: "MUSIC_", with: "") ?? ""
        guard let id = Int(idText), id > 0 else { return nil }
        let duration = seconds(item["DURATION"] ?? item["duration"])
        let image = kuwoImageURL(text(item["web_albumpic_short"]) ?? text(item["albumpic"]) ?? text(item["PICPATH"]) ?? text(item["hts_MVPIC"]))
        return Song(
            id: id,
            name: text(item["SONGNAME"]) ?? text(item["name"]) ?? "",
            artists: text(item["ARTIST"]) ?? text(item["artist"]) ?? "",
            album: text(item["ALBUM"]) ?? text(item["album"]) ?? "",
            coverURL: image.flatMap(URL.init(string:)),
            duration: duration,
            source: .kuwo,
            fee: int(item["PAY"]) ?? int(item["pay"]) ?? 0
        )
    }

    private static func qqCatalogSong(_ item: [String: Any]) -> Song? {
        guard let id = int(item["id"] ?? item["songid"] ?? item["songId"] ?? item["song_id"]), id > 0 else { return nil }
        let album = (item["album"] as? [String: Any]) ?? (item["album_info"] as? [String: Any])
        let file = (item["file"] as? [String: Any]) ?? (item["file_info"] as? [String: Any])
        let mid = text(item["mid"] ?? item["songmid"] ?? file?["media_mid"]) ?? ""
        let albumMid = text(album?["mid"] ?? album?["album_mid"] ?? item["albummid"]) ?? ""
        let cover = albumMid.isEmpty ? nil : URL(string: "https://y.gtimg.cn/music/photo_new/T002R500x500M000\(albumMid).jpg")
        let singers = dictionaries(in: item["singer"] ?? item["singers"] ?? item["artist"])
            .compactMap { text($0["name"] ?? $0["title"] ?? $0["singername"]) }
            .joined(separator: " / ")
        let fee = int(item["fee"]) ?? int((item["pay"] as? [String: Any])?["pay_play"]) ?? 0
        return Song(
            id: id,
            name: text(item["title"] ?? item["songname"] ?? item["songName"] ?? item["name"]) ?? "",
            artists: singers.isEmpty ? (text(item["singername"]) ?? "") : singers,
            album: text(album?["name"] ?? album?["title"] ?? item["albumname"]) ?? "",
            coverURL: cover,
            duration: seconds(item["interval"] ?? item["duration"]),
            source: .qq,
            qqMid: mid.isEmpty ? nil : mid,
            qqMediaMid: text(file?["media_mid"] ?? item["media_mid"]),
            fee: fee
        )
    }

    private static func kugouCatalogSong(_ item: [String: Any]) -> Song? {
        guard let id = int(item["Audioid"] ?? item["audio_id"] ?? item["audioid"] ?? item["songid"]), id > 0 else { return nil }
        let hash = text(item["FileHash"] ?? item["filehash"] ?? item["hash"]) ?? ""
        let albumID = text(item["AlbumID"] ?? item["album_id"] ?? item["albumid"]) ?? ""
        let cover = kugouImageURL(text(item["Image"] ?? item["image"] ?? item["AlbumImage"] ?? item["img"] ?? item["imgurl"])).flatMap(URL.init(string:))
        return Song(
            id: id,
            name: text(item["SongName"] ?? item["songname"] ?? item["filename"]) ?? "",
            artists: text(item["Singers"] ?? item["singername"] ?? item["artist"]) ?? "",
            album: text(item["AlbumName"] ?? item["album_name"] ?? item["albumname"]) ?? "",
            coverURL: cover,
            duration: seconds(item["Duration"] ?? item["duration"] ?? item["timelength"]),
            source: .kugou,
            kugouHash: hash.isEmpty ? nil : hash,
            kugouAlbumAudioId: text(item["audio_id"] ?? item["Audioid"]),
            kugouAlbumId: albumID.isEmpty ? nil : albumID,
            fee: int(item["Privilege"] ?? item["privilege"]) ?? 0
        )
    }

    private static func miguSong(_ item: [String: Any]) -> Song? {
        guard let id = int(item["songId"] ?? item["copyrightId"] ?? item["contentId"]), id > 0 else { return nil }
        let singers = dictionaries(in: item["singers"] ?? item["singerList"])
            .compactMap { text($0["name"] ?? $0["singerName"]) }
            .joined(separator: " / ")
        let album = dictionaries(in: item["albums"])
            .compactMap { text($0["name"]) }
            .first
        let imageItems = dictionaries(in: item["imgItems"])
        let image = miguImageURL(
            text(item["img3"]) ?? text(item["img2"]) ?? text(item["img1"])
                ?? text(item["albumPicUrl"]) ?? text(item["cover"])
                ?? text(imageItems.first?["img"] ?? imageItems.first?["imgUrl"])
        )
        return Song(
            id: id,
            name: text(item["name"]) ?? text(item["songName"]) ?? "",
            artists: singers.isEmpty ? (text(item["singerList"]) ?? text(item["singerName"]) ?? "") : singers,
            album: text(item["album"]) ?? text(item["albumName"]) ?? album ?? "",
            coverURL: image.flatMap(URL.init(string:)),
            duration: seconds(item["duration"] ?? item["length"]),
            source: .migu,
            fee: int(item["needPay"]) ?? int(item["payFlag"]) ?? 0
        )
    }

    private static func kuwoSearch(keyword: String, limit: Int, type: String) async throws -> [String: Any] {
        var components = URLComponents(string: "https://search.kuwo.cn/r.s")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "kt"),
            URLQueryItem(name: "all", value: keyword),
            URLQueryItem(name: "pn", value: "0"),
            URLQueryItem(name: "rn", value: String(min(max(limit, 1), 60))),
            URLQueryItem(name: "uid", value: "794762570"),
            URLQueryItem(name: "ver", value: "kwplayer_ar_9.2.2.1"),
            URLQueryItem(name: "vipver", value: "1"),
            URLQueryItem(name: "show_copyright_off", value: "1"),
            URLQueryItem(name: "newver", value: "1"),
            URLQueryItem(name: "ft", value: type),
            URLQueryItem(name: "cluster", value: "0"),
            URLQueryItem(name: "strategy", value: "2012"),
            URLQueryItem(name: "encoding", value: "utf8"),
            URLQueryItem(name: "rformat", value: "json"),
            URLQueryItem(name: "vermerge", value: "1"),
            URLQueryItem(name: "mobi", value: "1"),
            URLQueryItem(name: "issubtitle", value: "1"),
        ]
        return try await fetchObject(components.url!, headers: ["Referer": "https://www.kuwo.cn/", "User-Agent": browserUserAgent])
    }

    private static func miguSearch(keyword: String, limit: Int, switchValue: String) async throws -> [String: Any] {
        var components = URLComponents(string: "https://app.c.nf.migu.cn/MIGUM2.0/v1.0/content/search_all.do")!
        components.queryItems = [
            URLQueryItem(name: "isCopyright", value: "1"),
            URLQueryItem(name: "isCorrect", value: "1"),
            URLQueryItem(name: "pageNo", value: "1"),
            URLQueryItem(name: "pageSize", value: String(min(max(limit, 1), 50))),
            URLQueryItem(name: "searchSwitch", value: switchValue),
            URLQueryItem(name: "sort", value: "0"),
            URLQueryItem(name: "text", value: keyword),
        ]
        let root = try await fetchObject(components.url!, headers: ["Referer": "https://m.music.migu.cn/", "User-Agent": browserUserAgent])
        guard text(root["code"]) == "000000" else { throw AdditionalCatalogSearchError.invalidResponse }
        return root
    }

    private static func miguSongSearch(keyword: String, limit: Int) async throws -> [String: Any] {
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let deviceID = "963B7AA0D21511ED807EE5846EC87D20"
        let signatureSeed = "\(keyword)6cdc72a439cef99a3418d2a78aa28c73yyapp2d16148780a1dcc7408e06336b98cfd50\(deviceID)\(timestamp)"
        var components = URLComponents(string: "https://jadeite.migu.cn/music_search/v3/search/searchAll")!
        components.queryItems = [
            URLQueryItem(name: "isCorrect", value: "0"),
            URLQueryItem(name: "isCopyright", value: "1"),
            URLQueryItem(name: "searchSwitch", value: "{\"song\":1,\"album\":0,\"singer\":0,\"tagSong\":1,\"mvSong\":0,\"bestShow\":1,\"songlist\":0,\"lyricSong\":0}"),
            URLQueryItem(name: "pageSize", value: String(min(max(limit, 1), 50))),
            URLQueryItem(name: "text", value: keyword),
            URLQueryItem(name: "pageNo", value: "1"),
            URLQueryItem(name: "sort", value: "0"),
            URLQueryItem(name: "sid", value: "USS"),
        ]
        do {
            let root = try await fetchObject(
                components.url!,
                headers: [
                    "uiVersion": "A_music_3.6.1",
                    "deviceId": deviceID,
                    "timestamp": timestamp,
                    "sign": md5(signatureSeed),
                    "channel": "0146921",
                    "User-Agent": browserUserAgent,
                ]
            )
            guard text(root["code"]) == "000000" else { throw AdditionalCatalogSearchError.invalidResponse }
            return root
        } catch {
            return try await miguSearch(keyword: keyword, limit: limit, switchValue: "{\"song\":1,\"album\":0,\"singer\":0,\"tagSong\":0,\"mvSong\":0,\"songlist\":0,\"bestShow\":0}")
        }
    }

    private static func kuwoLyric(songID: Int) async throws -> String {
        guard songID > 0 else { throw AdditionalCatalogSearchError.invalidResponse }
        let params = "user=12345,web,web,web&requester=localhost&req=1&rid=MUSIC_\(songID)&lrcx=1"
        let key = Array("yeelion".utf8)
        let encoded = Data(params.utf8).enumerated().map { $0.element ^ key[$0.offset % key.count] }
        let query = Data(encoded).base64EncodedString()
        guard let url = URL(string: "https://newlyric.kuwo.cn/newlyric.lrc?\(query)") else {
            throw AdditionalCatalogSearchError.invalidResponse
        }
        let data = try await fetchData(url, headers: ["Referer": "https://www.kuwo.cn/", "User-Agent": browserUserAgent])
        guard let delimiter = data.range(of: Data("\r\n\r\n".utf8)),
              let inflated = inflateZlib(Data(data[delimiter.upperBound...])),
              let encodedLyric = String(data: inflated, encoding: .utf8),
              let lyricData = Data(base64Encoded: encodedLyric, options: .ignoreUnknownCharacters) else {
            throw AdditionalCatalogSearchError.invalidResponse
        }
        let decoded = lyricData.enumerated().map { $0.element ^ key[$0.offset % key.count] }
        guard let lyric = decodeGB18030(Data(decoded)), !lyric.isEmpty else {
            throw AdditionalCatalogSearchError.invalidResponse
        }
        return lyric
    }

    private static func miguLyric(songID: Int) async throws -> String {
        guard songID > 0,
              let url = URL(string: "https://c.musicapp.migu.cn/MIGUM2.0/v1.0/content/resourceinfo.do?resourceType=2") else {
            throw AdditionalCatalogSearchError.invalidResponse
        }
        let root = try await fetchObject(
            url,
            method: "POST",
            body: Data("resourceId=\(songID)".utf8),
            headers: [
                "Content-Type": "application/x-www-form-urlencoded",
                "Referer": "https://app.c.nf.migu.cn/",
                "User-Agent": browserUserAgent,
            ]
        )
        let resource = ((root["data"] as? [String: Any])?["resource"] as? [[String: Any]])?.first
        guard let rawURL = text(resource?["lrcUrl"] ?? resource?["lrc_url"]),
              let lyricURL = URL(string: rawURL) else {
            throw AdditionalCatalogSearchError.invalidResponse
        }
        let lyric = try await fetchText(lyricURL, headers: ["Referer": "https://m.music.migu.cn/", "User-Agent": browserUserAgent])
        guard !lyric.isEmpty else { throw AdditionalCatalogSearchError.invalidResponse }
        return lyric
    }

    private static func dictionaries(in value: Any?) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] {
            return [dictionary] + dictionary.values.flatMap { dictionaries(in: $0) }
        }
        if let values = value as? [Any] {
            return values.flatMap { dictionaries(in: $0) }
        }
        return []
    }

    private static func fetchObject(
        _ url: URL,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AdditionalCatalogSearchError.invalidResponse
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }
        guard let raw = String(data: data, encoding: .utf8),
              let start = raw.firstIndex(where: { $0 == "{" || $0 == "[" }),
              let end = raw.lastIndex(where: { $0 == "}" || $0 == "]" }),
              let object = try? JSONSerialization.jsonObject(with: Data(raw[start...end].utf8)) as? [String: Any] else {
            throw AdditionalCatalogSearchError.invalidResponse
        }
        return object
    }

    private static func fetchData(_ url: URL, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AdditionalCatalogSearchError.invalidResponse
        }
        return data
    }

    private static func fetchText(_ url: URL, headers: [String: String]) async throws -> String {
        let data = try await fetchData(url, headers: headers)
        guard let text = String(data: data, encoding: .utf8) else {
            throw AdditionalCatalogSearchError.invalidResponse
        }
        return text
    }

    private static func inflateZlib(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        var capacity = max(data.count * 8, 64 * 1024)
        while capacity <= 8 * 1024 * 1024 {
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            defer { buffer.deallocate() }
            let count = data.withUnsafeBytes { source in
                compression_decode_buffer(
                    buffer,
                    capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
            if count > 0 { return Data(bytes: buffer, count: count) }
            capacity *= 2
        }
        return nil
    }

    private static func decodeGB18030(_ data: Data) -> String? {
        let encoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        return String(data: data, encoding: String.Encoding(rawValue: encoding))
    }

    private static func md5(_ string: String) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        string.withCString { pointer in
            _ = CC_MD5(pointer, CC_LONG(string.lengthOfBytes(using: .utf8)), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func zzcSign(_ data: Data) -> String? {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA1(buffer.baseAddress, CC_LONG(data.count), &digest)
        }
        let hexDigits = Array("0123456789abcdef".utf8)
        let hash = digest.flatMap { byte in
            [hexDigits[Int(byte >> 4)], hexDigits[Int(byte & 0x0f)]]
        }
        guard hash.count == 40 else { return nil }
        let part1Indexes = [23, 14, 6, 36, 16, 40, 7, 19]
        let part2Indexes = [16, 1, 32, 12, 19, 27, 8, 5]
        let part1 = part1Indexes
            .filter { hash.indices.contains($0) }
            .map { String(decoding: [hash[$0]], as: UTF8.self) }
            .joined()
        let part2 = part2Indexes
            .filter { hash.indices.contains($0) }
            .map { String(decoding: [hash[$0]], as: UTF8.self) }
            .joined()
        let scramble = [89, 39, 179, 150, 218, 82, 58, 252, 177, 52, 186, 123, 120, 64, 242, 133, 143, 161, 121, 179]
        var bytes: [UInt8] = []
        for (index, value) in scramble.enumerated() {
            guard let high = hexNibble(hash[index * 2]), let low = hexNibble(hash[index * 2 + 1]) else { return nil }
            bytes.append(UInt8(value) ^ ((high << 4) | low))
        }
        let base64 = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "=", with: "")
        return "zzc\(part1)\(base64)\(part2)".lowercased()
    }

    private static func hexNibble(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: return byte - 48
        case 65...70: return byte - 55
        case 97...102: return byte - 87
        default: return nil
        }
    }

    private static func text(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value.replacingOccurrences(of: "&nbsp;", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = text(value) { return Int(value) }
        return nil
    }

    private static func seconds(_ value: Any?) -> TimeInterval {
        if let value = int(value) {
            return value > 10_000 ? TimeInterval(value) / 1000 : TimeInterval(value)
        }
        guard let value = text(value) else { return 0 }
        let parts = value.split(separator: ":").compactMap { Double($0) }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        return Double(value) ?? 0
    }

    private static func kuwoImageURL(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        value = value.replacingOccurrences(of: "{size}", with: "400")
        if value.hasPrefix("//") { value = "https:\(value)" }
        if value.hasPrefix("http") { return value.replacingOccurrences(of: "http://", with: "https://") }
        var path = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = path.split(separator: "/", maxSplits: 1).map(String.init)
        if parts.count == 2, Int(parts[0]) != nil {
            path = "500/\(parts[1])"
        }
        return "https://img1.kuwo.cn/star/albumcover/\(path)"
    }

    private static func miguImageURL(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if value.hasPrefix("//") { value = "https:\(value)" }
        if value.hasPrefix("/") { value = "https://d.musicapp.migu.cn\(value)" }
        return value.replacingOccurrences(of: "http://", with: "https://")
    }

    private static func kugouImageURL(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        value = value.replacingOccurrences(of: "{size}", with: "400")
        if value.hasPrefix("//") { value = "https:\(value)" }
        if value.hasPrefix("http://") { value = value.replacingOccurrences(of: "http://", with: "https://") }
        return value
    }

    private static let browserUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148"
}
