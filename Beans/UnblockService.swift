import Foundation

/// 灰色歌曲 / VIP 试听解锁：使用用户填写密钥的第三方音源。
/// 由 PlayerManager 在网易云 / QQ 无完整 URL 时自动调用。
enum UnblockService {
    struct Resolved {
        let url: URL
        let source: String

        var sourceTitle: String { source }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 7
        config.timeoutIntervalForResource = 12
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// 入口：并发尝试用户导入且可用于当前平台的音源，返回第一个可用地址。
    static func resolve(
        name: String,
        artists: String,
        neteaseID: Int,
        songSource: SongSource = .netease,
        qqMid: String? = nil,
        kugouID: String? = nil,
        strict: Bool = false,
        excludedHosts: Set<String> = []
    ) async -> Resolved? {
        let hasSongIdentity = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !artists.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasSongIdentity else { return nil }
        let sources = UnblockSourceStore.shared.sources
            .filter { $0.enabled && canUse(source: $0, songSource: songSource, neteaseID: neteaseID, qqMid: qqMid, kugouID: kugouID) }
        guard !sources.isEmpty, !userAPIKeys().isEmpty else { return nil }

        // LX、CR、QT 三个预设最终访问同一个接口，只保留每个请求指纹的第一个，
        // 避免同一首歌重复请求同一个服务，尤其避免酷狗回退时触发请求风暴。
        var seen = Set<String>()
        let uniqueSources = sources.filter { seen.insert(requestFingerprint(for: $0)).inserted }

        // 慢源/失效源不要拖住播放：全部候选一起请求，最快命中的播放地址直接返回。
        return await withTaskGroup(of: Resolved?.self) { group in
            for source in uniqueSources {
                group.addTask {
                    return await presetSourceRequest(
                        source: source,
                        name: name,
                        artists: artists,
                        neteaseID: neteaseID,
                        songSource: songSource,
                        qqMid: qqMid,
                        kugouID: kugouID,
                        excludedHosts: excludedHosts
                    )
                }
            }
            for await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

    private static func canUse(source: ThirdPartySource, songSource: SongSource, neteaseID: Int, qqMid: String?, kugouID: String?) -> Bool {
        let expectedProvider = providerCode(for: songSource)
        if let provider = source.headers["source"], !provider.isEmpty, provider != expectedProvider {
            return false
        }
        if songSource == .qq {
            return qqMid?.isEmpty == false
        }
        if songSource == .kugou {
            return kugouID?.isEmpty == false
        }
        return neteaseID > 0
    }

    private static func presetSourceRequest(
        source: ThirdPartySource,
        name: String,
        artists: String,
        neteaseID: Int,
        songSource: SongSource,
        qqMid: String?,
        kugouID: String?,
        excludedHosts: Set<String>
    ) async -> Resolved? {
        guard !source.template.isEmpty else { return nil }
        let expectedProvider = providerCode(for: songSource)
        if let provider = source.headers["source"], !provider.isEmpty, provider != expectedProvider {
            return nil
        }
        let songID: String
        switch songSource {
        case .netease where neteaseID > 0:
            songID = String(neteaseID)
        case .qq:
            guard let qqMid, !qqMid.isEmpty else { return nil }
            songID = qqMid
        case .kugou:
            guard let kugouID, !kugouID.isEmpty else { return nil }
            songID = kugouID
        default:
            return nil
        }
        var baseURLString = source.template
        baseURLString = baseURLString.replacingOccurrences(of: "{id}", with: songID)
        baseURLString = baseURLString.replacingOccurrences(of: "{source}", with: expectedProvider)
        baseURLString = baseURLString.replacingOccurrences(of: "{name}", with: urlEncoded(name))
        let keyword = ([name, artists].filter { !$0.isEmpty }).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        baseURLString = baseURLString.replacingOccurrences(of: "{keyword}", with: urlEncoded(keyword))
        baseURLString = baseURLString.replacingOccurrences(of: "{artist}", with: urlEncoded(artists))
        let apiKeys = orderedAPIKeys()
        for quality in qualityCandidates(for: source, songSource: songSource) {
            let urlString = baseURLString.replacingOccurrences(of: "{quality}", with: quality)
            guard let url = URL(string: urlString) else { continue }
            if !apiKeys.isEmpty {
                for (originalIndex, apiKey) in apiKeys {
                    if let resolved = await presetSourceRequestOnce(
                        source: source,
                        url: url,
                        apiKey: apiKey,
                        keyIndex: originalIndex + 1,
                        keyTotal: apiKeys.count,
                        quality: quality,
                        excludedHosts: excludedHosts
                    ) {
                        rememberWorkingKey(originalIndex)
                        return resolved
                    }
                }
            } else if let resolved = await presetSourceRequestOnce(
                source: source,
                url: url,
                apiKey: nil,
                keyIndex: 0,
                keyTotal: 0,
                quality: quality,
                excludedHosts: excludedHosts
            ) {
                return resolved
            }
        }

        if !apiKeys.isEmpty {
            BeansLogger.shared.log("第三方音源用户密钥全部未命中：\(source.name) 共 \(apiKeys.count) 个", level: .debug)
        }
        return nil
    }

    private static func presetSourceRequestOnce(
        source: ThirdPartySource,
        url: URL,
        apiKey: String?,
        keyIndex: Int,
        keyTotal: Int,
        quality: String,
        excludedHosts: Set<String>
    ) async -> Resolved? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 7
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("BeansMusic-UserSource/1.0", forHTTPHeaderField: "User-Agent")
        if let apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        let keyLabel = (keyTotal > 1 ? " 密钥=\(keyIndex)/\(keyTotal)" : "") + " 音质=\(quality)"
        let metadataKeys: Set<String> = ["source", "quality", "br", "apiKey", "apiKeys"]
        for (key, value) in source.headers where !metadataKeys.contains(key) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            BeansLogger.shared.log("第三方音源请求失败：\(source.name)\(keyLabel) \(error.localizedDescription)", level: .debug)
            return nil
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            BeansLogger.shared.log("第三方音源 HTTP 失败：\(source.name)\(keyLabel) 状态=\(status)", level: .debug)
            return nil
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            BeansLogger.shared.log("第三方音源响应格式错误：\(source.name)\(keyLabel)", level: .debug)
            return nil
        }
        if let code = responseCode(from: obj), code != 0 && code != 200 {
            let message = obj["message"] as? String ?? obj["msg"] as? String ?? "code=\(code)"
            BeansLogger.shared.log("第三方音源返回失败：\(source.name)\(keyLabel) \(message)", level: .debug)
            return nil
        }
        guard let value = valueAtAnyPath(obj, source.urlPath),
              let resolvedURL = value as? String, !resolvedURL.isEmpty,
              let rawPlayURL = URL(string: resolvedURL),
              let playURL = await playablePlaybackURL(from: rawPlayURL, source: source, keyLabel: keyLabel, excludedHosts: excludedHosts) else {
            BeansLogger.shared.log("第三方音源响应中没有播放地址：\(source.name)\(keyLabel)", level: .debug)
            return nil
        }
        if rawPlayURL != playURL {
            BeansLogger.shared.log(
                "第三方音源切换 QQ CDN 节点：\(rawPlayURL.host ?? "?") -> \(playURL.host ?? "?")",
                level: .debug
            )
        }
        if let host = playURL.host?.lowercased(), excludedHosts.contains(host) {
            BeansLogger.shared.log(
                "第三方音源跳过已失败节点：\(source.name)\(keyLabel) 域名=\(host)",
                level: .debug
            )
            return nil
        }
        BeansLogger.shared.log("第三方音源命中：\(source.name)\(keyLabel)", level: .info)
        return Resolved(url: playURL, source: source.name)
    }

    /// 部分第三方接口会固定返回不稳定的 QQ CDN 节点。先替换为同路径候选并做
    /// 小范围探测，避免把明显不可用的地址直接交给 AVPlayer。
    private static func playablePlaybackURL(from rawURL: URL, source: ThirdPartySource, keyLabel: String, excludedHosts: Set<String>) async -> URL? {
        let candidates = qqPlaybackURLCandidates(for: rawURL)
        var firstAllowed: URL?
        for candidate in candidates {
            guard let host = candidate.host?.lowercased() else { continue }
            if excludedHosts.contains(host) {
                BeansLogger.shared.log(
                    "第三方音源跳过已失败节点：\(source.name)\(keyLabel) 域名=\(host)",
                    level: .debug
                )
                continue
            }
            if firstAllowed == nil { firstAllowed = candidate }
            guard isQQPlaybackHost(host) else {
                return candidate
            }
            if rawURL != candidate {
                BeansLogger.shared.log(
                    "第三方音源切换 QQ CDN 节点：\(rawURL.host ?? "?") -> \(host)",
                    level: .debug
                )
            }
            if await probePlaybackURL(candidate) {
                BeansLogger.shared.log(
                    "第三方音源 QQ CDN 探测成功：\(source.name)\(keyLabel) \(safeURLSummary(candidate))",
                    level: .debug
                )
                return candidate
            }
            BeansLogger.shared.log(
                "第三方音源 QQ CDN 探测失败：\(source.name)\(keyLabel) \(safeURLSummary(candidate))",
                level: .debug
            )
        }
        if firstAllowed != nil {
            BeansLogger.shared.log(
                "第三方音源 QQ CDN 候选均未通过探测，尝试下一档音质：\(source.name)\(keyLabel)",
                level: .debug
            )
        }
        return nil
    }

    private static func qqPlaybackURLCandidates(for url: URL) -> [URL] {
        guard let host = url.host?.lowercased(), isQQPlaybackHost(host) else {
            return [url]
        }
        let hosts = [
            "isure6.ptqqmusic.gitv.tv",
            "isure.stream.qqmusic.qq.com",
            "dl.stream.qqmusic.qq.com",
            "ws.stream.qqmusic.qq.com",
            "streamoc.music.tc.qq.com",
            host
        ]
        var seen = Set<String>()
        return hosts.compactMap { replacement in
            guard seen.insert(replacement).inserted else { return nil }
            return replacingHost(of: url, with: replacement)
        }
    }

    private static func replacingHost(of url: URL, with replacementHost: String) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.host = replacementHost
        return components?.url ?? url
    }

    private static func isQQPlaybackHost(_ host: String) -> Bool {
        host.contains("qq.com") || host.contains("qqmusic") || host.contains("ptqqmusic") || host.contains("gitv.tv")
    }

    private static func qualityCandidates(for source: ThirdPartySource, songSource: SongSource) -> [String] {
        let configured = source.headers["quality"] ?? "320k"
        let fallback: [String]
        switch songSource {
        case .qq:
            fallback = ["320k", "128k", "flac"]
        case .netease:
            fallback = [configured, "exhigh", "higher", "standard"]
        case .kugou:
            fallback = [configured, "320k", "128k"]
        }
        var seen = Set<String>()
        return ([configured] + fallback).filter { quality in
            let trimmed = quality.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && seen.insert(trimmed).inserted
        }
    }

    private static func probePlaybackURL(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("bytes=0-2047", forHTTPHeaderField: "Range")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:80.0) Gecko/20100101 Firefox/80.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("https://y.qq.com", forHTTPHeaderField: "Origin")
        let cookie = QQMusicAuth.shared.cookieHeader
        request.setValue(cookie.isEmpty ? "uin=0; qqmusic_fromtag=66" : cookie, forHTTPHeaderField: "Cookie")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 || http.statusCode == 206,
              !data.isEmpty else { return false }
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        return !contentType.contains("text/html") && !contentType.contains("application/json")
    }

    private static func safeURLSummary(_ url: URL) -> String {
        let host = url.host ?? "?"
        let path = url.path.isEmpty ? "/" : url.path
        let shortPath = path.count > 72 ? String(path.prefix(72)) + "..." : path
        return "\(host)\(shortPath)"
    }

    private static func requestFingerprint(for source: ThirdPartySource) -> String {
        let headers = source.headers
            .filter { $0.key != "source" }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        return "\(source.template)|\(source.urlPath)|\(headers)"
    }

    private static func userAPIKeys() -> [String] {
        UserDefaults.standard.string(forKey: UnblockSourceStore.userAPIKeysKey)?
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private static func orderedAPIKeys() -> [(Int, String)] {
        let keys = userAPIKeys()
        var seen = Set<String>()
        let unique = keys.enumerated().compactMap { index, key -> (Int, String)? in
            seen.insert(key).inserted ? (index, key) : nil
        }
        let preferred = UserDefaults.standard.integer(forKey: preferredKeyIndexDefaultsKey())
        guard let hit = unique.firstIndex(where: { $0.0 == preferred }), hit > 0 else {
            return unique
        }
        var reordered = unique
        let item = reordered.remove(at: hit)
        reordered.insert(item, at: 0)
        return reordered
    }

    private static func rememberWorkingKey(_ index: Int) {
        UserDefaults.standard.set(index, forKey: preferredKeyIndexDefaultsKey())
    }

    private static func preferredKeyIndexDefaultsKey() -> String {
        "beans.unblock.preferredKeyIndex.user"
    }

    private static func responseCode(from object: [String: Any]) -> Int? {
        if let code = object["code"] as? Int {
            return code
        }
        if let code = object["code"] as? NSNumber {
            return code.intValue
        }
        if let code = object["code"] as? String {
            return Int(code)
        }
        return nil
    }

    private static func providerCode(for source: SongSource) -> String {
        switch source {
        case .netease: return "wy"
        case .qq: return "tx"
        case .kugou: return "kg"
        }
    }

    /// 多个点分路径取值：data.music|data.url|url。
    private static func valueAtAnyPath(_ obj: Any, _ paths: String) -> Any? {
        for path in paths.split(separator: "|") {
            if let value = valueAtPath(obj, String(path)) {
                return value
            }
        }
        return nil
    }

    /// 点分路径取值：url / data.url / data.audioUrl ...
    private static func valueAtPath(_ obj: Any, _ path: String) -> Any? {
        var current: Any = obj
        for key in path.split(separator: ".") {
            guard let dict = current as? [String: Any], let next = dict[String(key)] else { return nil }
            current = next
        }
        return current
    }

    private static func urlEncoded(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
    }

}
