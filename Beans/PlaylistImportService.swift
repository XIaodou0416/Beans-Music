import Foundation

/// A playlist returned by the Moumusic-style import flow, adapted to Beans' Song model.
struct BeansImportedPlaylist {
    let name: String
    let coverURL: URL?
    let sourceName: String?
    let songs: [Song]
}

enum BeansPlaylistImportError: LocalizedError {
    case emptyInput
    case unsupportedLink
    case invalidFormat
    case noSongs

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "请输入歌单链接或歌单 JSON 文件内容"
        case .unsupportedLink:
            return "支持网易云歌单、哔哩哔哩视频/收藏夹链接，或其他平台导出的 JSON"
        case .invalidFormat:
            return "无法识别歌单格式"
        case .noSongs:
            return "歌单中没有可导入的歌曲"
        }
    }
}

/// Playlist import logic follows Moumusic's public-link and exported-JSON flow.
/// It deliberately only imports metadata; playback continues to use Beans' source resolver.
enum BeansPlaylistImportService {
    static func importPlaylist(from input: String) async throws -> BeansImportedPlaylist {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw BeansPlaylistImportError.emptyInput }

        if let url = URL(string: value), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            let resolved = (try? await resolveRedirect(from: url)) ?? url
            let host = resolved.host?.lowercased() ?? url.host?.lowercased() ?? ""
            if host == "b23.tv" || host.hasSuffix(".bilibili.com") || host == "bilibili.com" {
                return try await importBilibiliCollection(resolved.absoluteString)
            }
            return try await importNetEasePlaylist(from: url)
        }

        if BilibiliAPI.videoID(value) != nil || value.hasPrefix("fav:") {
            return try await importBilibiliCollection(value)
        }
        if value.allSatisfy(\.isNumber) {
            return try await importBilibiliCollection("fav:\(value)")
        }

        if let data = value.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) {
            return try importJSON(object)
        }

        throw BeansPlaylistImportError.invalidFormat
    }

    private static func importBilibiliCollection(_ input: String) async throws -> BeansImportedPlaylist {
        let collection = try await BilibiliAPI.shared.collection(input)
        guard !collection.songs.isEmpty else { throw BeansPlaylistImportError.noSongs }
        return BeansImportedPlaylist(
            name: collection.playlist.name,
            coverURL: collection.playlist.coverURL,
            sourceName: "哔哩哔哩",
            songs: collection.songs
        )
    }

    private static func importNetEasePlaylist(from url: URL) async throws -> BeansImportedPlaylist {
        let resolvedURL = (try? await resolveRedirect(from: url)) ?? url
        guard let host = resolvedURL.host?.lowercased(),
              host.contains("163cn.tv") || host.contains("music.163.com"),
              let playlistID = netEasePlaylistID(from: resolvedURL)
                ?? netEasePlaylistID(from: url) else {
            throw BeansPlaylistImportError.unsupportedLink
        }

        var components = URLComponents(string: "https://music.163.com/api/v6/playlist/detail")!
        components.queryItems = [
            URLQueryItem(name: "id", value: String(playlistID)),
            URLQueryItem(name: "n", value: "1000"),
        ]
        let root = try await fetchJSONObject(components.url!)
        if let code = integer(root["code"]), code != 200 {
            throw BeansPlaylistImportError.invalidFormat
        }

        guard let playlist = (root["playlist"] as? [String: Any])
                ?? ((root["result"] as? [String: Any])?["playlist"] as? [String: Any]) else {
            throw BeansPlaylistImportError.invalidFormat
        }

        let previewSongs = collectSongs(from: playlist["tracks"] ?? [], defaultSource: .netease)
        let ids = (playlist["trackIds"] as? [[String: Any]])?
            .compactMap { firstString($0["id"]) }
            .filter { !$0.isEmpty } ?? []

        // The detail endpoint can return only a preview in `tracks`; resolve all
        // trackIds so a shared playlist is not silently truncated. NetEase's
        // detail endpoint is unreliable when hundreds of IDs are packed into a
        // single URL; resolve bounded batches and merge the successful batches
        // back into the original playlist order.
        var songs = previewSongs
        if songs.count < ids.count, !ids.isEmpty {
            let detailedSongs = await fetchNetEaseSongs(for: ids)
            if !detailedSongs.isEmpty {
                songs = orderedNetEaseSongs(
                    previewSongs: previewSongs,
                    detailedSongs: detailedSongs,
                    ids: ids
                )
            }
        }

        guard !songs.isEmpty else { throw BeansPlaylistImportError.noSongs }
        let name = firstString(playlist["name"]) ?? "网易云歌单 \(playlistID)"
        let cover = firstURL(
            playlist["coverImgUrl"],
            playlist["picUrl"],
            playlist["cover"]
        )
        return BeansImportedPlaylist(
            name: name,
            coverURL: cover,
            sourceName: "网易云音乐",
            songs: deduplicated(songs)
        )
    }

    /// Resolve large public playlists without exceeding the detail endpoint's
    /// practical URL/request limit. A failed batch is ignored so the songs
    /// already returned by the playlist endpoint remain importable.
    private static func fetchNetEaseSongs(for ids: [String]) async -> [Song] {
        var uniqueIDs: [String] = []
        var seen = Set<String>()
        for id in ids where seen.insert(id).inserted {
            uniqueIDs.append(id)
        }

        let batchSize = 100
        var songs: [Song] = []
        for start in stride(from: 0, to: uniqueIDs.count, by: batchSize) {
            guard !Task.isCancelled else { break }
            let end = min(start + batchSize, uniqueIDs.count)
            let batch = Array(uniqueIDs[start..<end])
            guard !batch.isEmpty else { continue }

            var components = URLComponents(string: "https://music.163.com/api/song/detail")!
            components.queryItems = [
                URLQueryItem(name: "ids", value: "[\(batch.joined(separator: ","))]"),
            ]

            do {
                let details = try await fetchJSONObject(components.url!)
                let batchSongs = collectSongs(
                    from: details["songs"] ?? details["data"] ?? details,
                    defaultSource: .netease
                )
                songs.append(contentsOf: batchSongs)
            } catch {
                // Keep the preview and any other successful batches. One bad
                // request must not reduce a 600-song import back to 201 songs.
                continue
            }
        }
        return songs
    }

    private static func orderedNetEaseSongs(
        previewSongs: [Song],
        detailedSongs: [Song],
        ids: [String]
    ) -> [Song] {
        var songsByID: [String: Song] = [:]
        for song in previewSongs {
            songsByID[String(song.id)] = song
        }
        for song in detailedSongs {
            // Detailed responses contain the most complete metadata, so they
            // replace the preview entry for the same NetEase ID.
            songsByID[String(song.id)] = song
        }

        var ordered = ids.compactMap { songsByID[$0] }
        let orderedKeys = Set(ordered.map(\.identityKey))
        ordered.append(contentsOf: previewSongs.filter { !orderedKeys.contains($0.identityKey) })
        let finalKeys = Set(ordered.map(\.identityKey))
        ordered.append(contentsOf: detailedSongs.filter { !finalKeys.contains($0.identityKey) })
        return ordered
    }

    private static func resolveRedirect(from url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        let (_, response) = try await URLSession.shared.data(for: request)
        return response.url ?? url
    }

    private static func fetchJSONObject(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BeansPlaylistImportError.invalidFormat
        }
        return object
    }

    private static func netEasePlaylistID(from url: URL) -> Int? {
        func queryID(_ components: URLComponents?) -> Int? {
            components?.queryItems?
                .first(where: { $0.name.lowercased() == "id" })?
                .value
                .flatMap(Int.init)
        }

        if let id = queryID(URLComponents(url: url, resolvingAgainstBaseURL: false)) {
            return id
        }
        if let fragment = url.fragment, let id = queryID(URLComponents(string: fragment)) {
            return id
        }
        let parts = url.path.split(separator: "/").map(String.init)
        if let index = parts.firstIndex(where: { $0.lowercased() == "playlist" }),
           index + 1 < parts.count {
            return Int(parts[index + 1])
        }
        return nil
    }

    private static func importJSON(_ object: Any) throws -> BeansImportedPlaylist {
        let songs = deduplicated(collectSongs(from: object))
        guard !songs.isEmpty else { throw BeansPlaylistImportError.noSongs }

        let root = object as? [String: Any]
        let name = firstString(
            root?["name"],
            root?["title"],
            root?["playlistName"]
        ) ?? "导入歌单"
        let cover = firstURL(
            root?["coverURL"],
            root?["coverUrl"],
            root?["picUrl"],
            root?["coverImgUrl"],
            root?["cover"]
        )
        let sourceName = sourceTitle(for: firstString(root?["source"]))
        return BeansImportedPlaylist(
            name: name,
            coverURL: cover,
            sourceName: sourceName,
            songs: songs
        )
    }

    /// Recursively searches the same common keys accepted by Moumusic exports.
    private static func collectSongs(from object: Any, defaultSource: SongSource? = nil) -> [Song] {
        if let array = object as? [Any] {
            return array.flatMap { collectSongs(from: $0, defaultSource: defaultSource) }
        }
        guard let dictionary = object as? [String: Any] else { return [] }
        if let song = makeSong(dictionary, defaultSource: defaultSource) {
            return [song]
        }

        let keys = ["tracks", "songs", "musicList", "musiclist", "list", "playlist", "data", "result"]
        for key in keys {
            if let nested = dictionary[key] {
                let songs = collectSongs(from: nested, defaultSource: defaultSource)
                if !songs.isEmpty { return songs }
            }
        }
        return []
    }

    private static func makeSong(_ value: [String: Any], defaultSource: SongSource? = nil) -> Song? {
        let name = firstString(
            value["name"],
            value["songName"],
            value["SongName"],
            value["title"],
            value["songname"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return nil }

        let artistValue = value["artists"] ?? value["ar"]
        let artistNames: [String]
        if let array = artistValue as? [[String: Any]] {
            artistNames = array.compactMap { firstString($0["name"], $0["artistName"]) }
        } else if let array = artistValue as? [String] {
            artistNames = array
        } else if let dictionary = artistValue as? [String: Any],
                  let artist = firstString(dictionary["name"], dictionary["artistName"]) {
            artistNames = [artist]
        } else {
            let text = firstString(
                value["artist"],
                value["singer"],
                value["singername"],
                value["Singers"],
                value["artistNames"]
            ) ?? "未知歌手"
            artistNames = text
                .split(separator: "/")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        let albumValue = value["album"] ?? value["al"]
        let albumDictionary = albumValue as? [String: Any]
        let album = firstString(
            albumDictionary?["name"],
            albumDictionary?["title"],
            value["albumName"],
            value["albumname"]
        ) ?? ""
        let coverURL = firstURL(
            albumDictionary?["picUrl"],
            albumDictionary?["pic"],
            albumDictionary?["coverURL"],
            value["coverURL"],
            value["coverUrl"],
            value["picUrl"],
            value["img"],
            value["image"]
        )

        var metadata: [String: String] = [:]
        if let sourceMetadata = value["sourceMetadata"] as? [String: Any] {
            for (key, rawValue) in sourceMetadata {
                if let string = firstString(rawValue), !string.isEmpty {
                    metadata[key] = string
                }
            }
        }
        for key in [
            "songmid", "songMid", "songId", "hash", "FileHash", "copyrightId",
            "albumId", "strMediaMid", "albumMid", "id", "mid"
        ] {
            if let string = firstString(value[key]), !string.isEmpty {
                metadata[key] = string
            }
        }

        let rawID = firstString(
            value["id"],
            value["songid"],
            value["songId"],
            value["songmid"],
            value["bilibiliID"],
            value["bvid"],
            value["aid"],
            value["mid"],
            value["hash"],
            value["FileHash"],
            value["copyrightId"],
            metadata["songmid"],
            metadata["songId"],
            metadata["hash"]
        )
        guard let rawID, !rawID.isEmpty else { return nil }
        let id = Int(rawID) ?? stableID(rawID)
        guard id > 0 else { return nil }

        let source = sourceValue(
            firstString(value["source"], value["platform"], value["sourceName"])
                ?? defaultSource?.rawValue
        )
        let rawBilibiliID = firstString(value["bilibiliID"], value["bvid"], value["aid"], value["av"]) ?? rawID
        let bilibiliID = source == .bilibili ? rawBilibiliID.flatMap { raw -> String? in
            let videoID = BilibiliAPI.videoID(raw) ?? (raw.allSatisfy(\.isNumber) ? "av\(raw)" : nil)
            guard let videoID else { return nil }
            let cid = firstString(value["cid"], value["pageCid"])
            return cid.map { "\(videoID):\($0)" } ?? videoID
        } : nil
        let qqMid = firstString(value["qqMid"], value["songmid"], value["mid"], metadata["songmid"], metadata["songMid"])
        let qqMediaMid = firstString(value["qqMediaMid"], value["media_mid"], value["strMediaMid"], metadata["strMediaMid"])
        let kugouHash = firstString(value["kugouHash"], value["FileHash"], value["hash"], metadata["FileHash"], metadata["hash"])
        let kugouAlbumAudioID = firstString(value["kugouAlbumAudioId"], value["album_audio_id"])
        let kugouAlbumID = firstString(value["kugouAlbumId"], value["album_id"], metadata["albumId"])
        let miguCopyrightID = firstString(value["miguCopyrightId"], value["copyrightId"], metadata["copyrightId"])
        let miguLyricURL = firstURL(value["miguLyricURL"], value["lyricURL"], value["lyricUrl"])

        return Song(
            id: id,
            name: name,
            artists: artistNames.isEmpty ? "未知歌手" : artistNames.joined(separator: " / "),
            album: album,
            coverURL: coverURL,
            duration: duration(from: value),
            source: source,
            qqMid: qqMid,
            qqMediaMid: qqMediaMid,
            kugouHash: kugouHash,
            kugouAlbumAudioId: kugouAlbumAudioID,
            kugouAlbumId: kugouAlbumID,
            miguCopyrightId: miguCopyrightID,
            miguLyricURL: miguLyricURL,
            bilibiliID: bilibiliID,
            fee: integer(value["fee"] ?? value["pay"] ?? value["payplay"]) ?? 0
        )
    }

    private static func duration(from value: [String: Any]) -> TimeInterval {
        let raw = value["durationMS"] ?? value["dt"] ?? value["duration"]
            ?? value["interval"] ?? value["Duration"]
        if let number = raw as? NSNumber {
            let value = number.doubleValue
            return value < 1000 ? value : value / 1000
        }
        guard let text = firstString(raw) else { return 0 }
        if text.contains(":") {
            let parts = text.split(separator: ":").compactMap { Double($0) }
            if parts.count == 2 { return parts[0] * 60 + parts[1] }
        }
        let number = Double(text) ?? 0
        return number < 1000 ? number : number / 1000
    }

    private static func sourceValue(_ raw: String?) -> SongSource {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "wy", "netease", "neteasecloud", "163", "网易云", "网易云音乐": return .netease
        case "tx", "qq", "qqmusic", "qq音乐", "腾讯": return .qq
        case "kg", "kugou", "kugoumusic", "酷狗", "酷狗音乐": return .kugou
        case "kw", "kuwo", "kuwomusic", "酷我", "酷我音乐": return .kuwo
        case "mg", "migu", "migumusic", "咪咕", "咪咕音乐": return .migu
        case "qs", "qishui", "qishuimusic", "汽水", "汽水音乐": return .qishui
        case "bili", "bilibili", "哔哩哔哩", "b站": return .bilibili
        default: return .netease
        }
    }

    private static func sourceTitle(for raw: String?) -> String? {
        switch sourceValue(raw) {
        case .netease: return raw == nil ? nil : "网易云音乐"
        case .qq: return "QQ音乐"
        case .kugou: return "酷狗音乐"
        case .kuwo: return "酷我音乐"
        case .migu: return "咪咕音乐"
        case .qishui: return "汽水音乐"
        case .bilibili: return "哔哩哔哩"
        }
    }

    private static func deduplicated(_ songs: [Song]) -> [Song] {
        var seen = Set<String>()
        return songs.filter { seen.insert($0.identityKey).inserted }
    }

    private static func firstString(_ values: Any?...) -> String? {
        for value in values {
            if let string = value as? String { return string }
            if let number = value as? NSNumber { return number.stringValue }
        }
        return nil
    }

    private static func firstURL(_ values: Any?...) -> URL? {
        for value in values {
            if let url = value as? URL { return url }
            if let string = firstString(value), let url = URL(string: string), url.scheme != nil {
                return url
            }
        }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func stableID(_ value: String) -> Int {
        var hash: UInt64 = 2_166_136_261
        for byte in value.utf8 {
            hash = (hash ^ UInt64(byte)) &* 16_777_619
        }
        return max(1, Int(hash & 0x7fff_ffff))
    }
}
