import CommonCrypto
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
        let root = try await miguSearch(keyword: keyword, limit: limit, switchValue: "{\"song\":1,\"album\":0,\"singer\":0,\"tagSong\":0,\"mvSong\":0,\"songlist\":0,\"bestShow\":0}")
        return dictionaries(in: (root["songResultData"] as? [String: Any])?["resultList"]).compactMap(miguSong)
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
            return Artist(id: id, name: name, coverURL: miguImageURL(text(item["img"] ?? item["imgUrl"])).flatMap(URL.init(string:)), source: .migu)
        }
    }

    static func searchMiguAlbums(keyword: String, limit: Int = 40) async throws -> [Album] {
        let root = try await miguSearch(keyword: keyword, limit: limit, switchValue: "{\"song\":0,\"album\":1,\"singer\":0,\"tagSong\":0,\"mvSong\":0,\"songlist\":0,\"bestShow\":0}")
        return dictionaries(in: (root["albumResultData"] as? [String: Any])?["result"]).compactMap { item in
            guard let id = text(item["id"]), let name = text(item["name"]), !name.isEmpty else { return nil }
            return Album(id: id, name: name, artistName: text(item["singer"] ?? item["singerName"]) ?? "", coverURL: miguImageURL(text(item["img"] ?? item["imgUrl"])).flatMap(URL.init(string:)), source: .migu)
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

    private static func kuwoSong(_ item: [String: Any]) -> Song? {
        let rawID = text(item["MUSICRID"]) ?? text(item["id"]) ?? text(item["musicrid"])
        let idText = rawID?.replacingOccurrences(of: "MUSIC_", with: "") ?? ""
        guard let id = Int(idText), id > 0 else { return nil }
        let duration = seconds(item["DURATION"] ?? item["duration"])
        let image = kuwoImageURL(text(item["web_albumpic_short"]) ?? text(item["albumpic"]) ?? text(item["PICPATH"]))
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

    private static func miguSong(_ item: [String: Any]) -> Song? {
        guard let id = int(item["songId"] ?? item["copyrightId"] ?? item["contentId"]), id > 0 else { return nil }
        let singers = dictionaries(in: item["singers"] ?? item["singerList"])
            .compactMap { text($0["name"] ?? $0["singerName"]) }
            .joined(separator: " / ")
        let album = dictionaries(in: item["albums"])
            .compactMap { text($0["name"]) }
            .first
        let imageItems = dictionaries(in: item["imgItems"])
        let image = miguImageURL(text(item["img3"]) ?? text(item["img2"]) ?? text(item["img1"]) ?? text(item["albumPicUrl"]) ?? text(imageItems.first?["img"]))
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

    private static func dictionaries(in value: Any?) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] {
            return [dictionary] + dictionary.values.flatMap { dictionaries(in: $0) }
        }
        if let values = value as? [Any] {
            return values.flatMap { dictionaries(in: $0) }
        }
        return []
    }

    private static func fetchObject(_ url: URL, headers: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
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

    private static func md5(_ string: String) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        string.withCString { pointer in
            _ = CC_MD5(pointer, CC_LONG(string.lengthOfBytes(using: .utf8)), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
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
        guard let value, !value.isEmpty else { return nil }
        if value.hasPrefix("http") { return value.replacingOccurrences(of: "http://", with: "https://") }
        return "https://img1.kuwo.cn/star/albumcover/500/\(value.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
    }

    private static func miguImageURL(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value.hasPrefix("/") ? "https://d.musicapp.migu.cn\(value)" : value
    }

    private static let browserUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148"
}
