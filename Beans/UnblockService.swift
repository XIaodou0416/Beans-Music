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
        qqMediaMid: String? = nil,
        kugouID: String? = nil,
        strict: Bool = false,
        excludedHosts: Set<String> = []
    ) async -> Resolved? {
        let hasSongIdentity = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !artists.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasSongIdentity else { return nil }
        let sources = UnblockSourceStore.shared.sources
            .filter { $0.enabled && canUse(source: $0, songSource: songSource, neteaseID: neteaseID, qqMid: qqMid, kugouID: kugouID) }
        guard !sources.isEmpty else { return nil }

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
                        qqMediaMid: qqMediaMid,
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
        qqMediaMid: String?,
        kugouID: String?,
        excludedHosts: Set<String>
    ) async -> Resolved? {
        guard !source.template.isEmpty else { return nil }
        let expectedProvider = providerCode(for: songSource)
        if let provider = source.headers["source"], !provider.isEmpty, provider != expectedProvider {
            return nil
        }
        let songIDs: [String]
        switch songSource {
        case .netease where neteaseID > 0:
            songIDs = [String(neteaseID)]
        case .qq:
            guard let qqMid, !qqMid.isEmpty else { return nil }
            songIDs = qqIDCandidates(songID: neteaseID, songMid: qqMid, mediaMid: qqMediaMid)
        case .kugou:
            guard let kugouID, !kugouID.isEmpty else { return nil }
            songIDs = [kugouID]
        default:
            return nil
        }
        let apiKeys = orderedAPIKeys(for: source)
        for (idIndex, songID) in songIDs.enumerated() {
            var baseURLString = source.template
            baseURLString = baseURLString.replacingOccurrences(of: "{id}", with: songID)
            baseURLString = baseURLString.replacingOccurrences(of: "{source}", with: expectedProvider)
            baseURLString = baseURLString.replacingOccurrences(of: "{name}", with: urlEncoded(name))
            let keyword = ([name, artists].filter { !$0.isEmpty }).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            baseURLString = baseURLString.replacingOccurrences(of: "{keyword}", with: urlEncoded(keyword))
            baseURLString = baseURLString.replacingOccurrences(of: "{artist}", with: urlEncoded(artists))
            for quality in qualityCandidates(for: source, songSource: songSource) {
                let urlString = baseURLString.replacingOccurrences(of: "{quality}", with: quality)
                guard let url = URL(string: urlString) else { continue }
                let idLabel = songSource == .qq && songIDs.count > 1 ? " ID=\(idIndex + 1)/\(songIDs.count)" : ""
                if !apiKeys.isEmpty {
                    for (originalIndex, apiKey) in apiKeys {
                        if let resolved = await presetSourceRequestOnce(
                            source: source,
                            url: url,
                            apiKey: apiKey,
                            keyIndex: originalIndex + 1,
                            keyTotal: apiKeys.count,
                            quality: quality,
                            idLabel: idLabel,
                            excludedHosts: excludedHosts
                        ) {
                            rememberWorkingKey(originalIndex, for: source)
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
                    idLabel: idLabel,
                    excludedHosts: excludedHosts
                ) {
                    return resolved
                }
            }
        }

        if !apiKeys.isEmpty {
            BeansLogger.shared.log("第三方音源全部密钥未命中：\(source.name) 共 \(apiKeys.count) 个", level: .debug)
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
        idLabel: String = "",
        excludedHosts: Set<String>
    ) async -> Resolved? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 7
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("BeansMusic-UserSource/1.0", forHTTPHeaderField: "User-Agent")
        if let apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        let keyLabel = idLabel + (keyTotal > 1 ? " 密钥=\(keyIndex)/\(keyTotal)" : "") + " 音质=\(quality)"
        BeansLogger.shared.log(
            "第三方音源请求开始：\(source.name)\(keyLabel) key=\(apiKey == nil ? "无" : "有") url=\(safeURLSummary(url))",
            level: .debug
        )
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
        let responseCodeValue = responseCode(from: obj).map { String($0) } ?? "无"
        let responseURLHost: String
        if let raw = valueAtAnyPath(obj, source.urlPath) as? String,
           let parsed = URL(string: raw) {
            responseURLHost = parsed.host ?? "无"
        } else {
            responseURLHost = "无"
        }
        BeansLogger.shared.log(
            "第三方音源响应：\(source.name)\(keyLabel) code=\(responseCodeValue) hasURL=\(responseURLHost == "无" ? "否" : "是") host=\(responseURLHost)",
            level: .debug
        )
        if let code = responseCode(from: obj), code != 0 && code != 200 {
            let message = obj["message"] as? String ?? obj["msg"] as? String ?? "code=\(code)"
            BeansLogger.shared.log("第三方音源返回失败：\(source.name)\(keyLabel) \(message)", level: .debug)
            return nil
        }
        guard let value = valueAtAnyPath(obj, source.urlPath),
              let resolvedURL = value as? String, !resolvedURL.isEmpty,
              let rawPlayURL = URL(string: resolvedURL),
              var playURL = playablePlaybackURL(from: rawPlayURL, source: source, keyLabel: keyLabel, excludedHosts: excludedHosts) else {
            BeansLogger.shared.log("第三方音源响应中没有播放地址：\(source.name)\(keyLabel)", level: .debug)
            return nil
        }
        // QQ 接口经常返回“接口成功但 CDN 403”的地址。先用轻量 Range 请求确认，
        // 若确认被拒绝，就在同一轮尝试其他 QQ 节点，仍失败则让上层继续换音质/密钥。
        if isQQPlaybackHost(playURL.host?.lowercased() ?? ""),
           await qqPlaybackURLIsForbidden(playURL) {
            BeansLogger.shared.log(
                "第三方音源播放地址被 QQ CDN 拒绝：\(source.name)\(keyLabel) 域名=\(playURL.host ?? "?")",
                level: .debug
            )
            let candidates = qqPlaybackURLCandidates(for: rawPlayURL)
            var replacement: URL?
            for candidate in candidates.dropFirst() {
                guard let host = candidate.host?.lowercased(),
                      !excludedHosts.contains(host) else { continue }
                if !(await qqPlaybackURLIsForbidden(candidate)) {
                    replacement = candidate
                    break
                }
            }
            guard let replacement else {
                BeansLogger.shared.log(
                    "第三方音源所有 QQ CDN 节点均被拒绝：\(source.name)\(keyLabel)",
                    level: .debug
                )
                return nil
            }
            BeansLogger.shared.log(
                "第三方音源改用可访问 QQ CDN 节点：\(playURL.host ?? "?") -> \(replacement.host ?? "?")",
                level: .debug
            )
            playURL = replacement
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

    /// 只把明确的 HTTP 403 判定为地址被拒绝；超时/网络错误不提前否定，
    /// 避免把本来可由 AVPlayer 播放的地址误判为失效。
    private static func qqPlaybackURLIsForbidden(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 403
        } catch {
            return false
        }
    }

    /// 部分第三方接口会固定返回不稳定的 QQ CDN 节点。
    /// 不在这里做 Range 探测：部分 QQ CDN 会拒绝探测请求，但 AVPlayer
    /// 带完整请求头后仍可正常播放。实际失败由 AVPlayer 反馈，再换下一个节点。
    private static func playablePlaybackURL(from rawURL: URL, source: ThirdPartySource, keyLabel: String, excludedHosts: Set<String>) -> URL? {
        let candidates = qqPlaybackURLCandidates(for: rawURL)
        for candidate in candidates {
            guard let host = candidate.host?.lowercased() else { continue }
            if excludedHosts.contains(host) {
                BeansLogger.shared.log(
                    "第三方音源跳过已失败节点：\(source.name)\(keyLabel) 域名=\(host)",
                    level: .debug
                )
                continue
            }
            if rawURL != candidate {
                BeansLogger.shared.log(
                    "第三方音源准备 QQ CDN 备用节点：\(rawURL.host ?? "?") -> \(host)",
                    level: .debug
                )
            }
            BeansLogger.shared.log("第三方音源选择播放地址：\(source.name)\(keyLabel) \(safeURLSummary(candidate))", level: .debug)
            return candidate
        }
        return nil
    }

    private static func qqPlaybackURLCandidates(for url: URL) -> [URL] {
        guard let host = url.host?.lowercased(), isQQPlaybackHost(host) else {
            return [url]
        }
        let hosts = [
            host,
            "isure6.ptqqmusic.gitv.tv",
            "isure.stream.qqmusic.qq.com",
            "dl.stream.qqmusic.qq.com",
            "ws.stream.qqmusic.qq.com",
            "streamoc.music.tc.qq.com"
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

    private static func qqIDCandidates(songID: Int, songMid: String, mediaMid: String?) -> [String] {
        var seen = Set<String>()
        let numericID = songID > 0 ? String(songID) : nil
        // LX/CR/QT 插件把 QQ 的 musicInfo.songmid 作为首选 ID；
        // 先传 songmid 可避免接口把数字歌曲 ID 误判成其他平台或返回不稳定地址。
        return [songMid, mediaMid, numericID].compactMap { raw in
            guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  seen.insert(value).inserted else { return nil }
            return value
        }
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

    private static func sourceAPIKeys(for source: ThirdPartySource) -> [String] {
        var keys: [String] = []
        if let raw = source.headers["apiKeys"], !raw.isEmpty {
            keys.append(contentsOf: raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty })
        }
        if let raw = source.headers["apiKey"]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            keys.append(raw)
        }
        keys.append(contentsOf: userAPIKeys())
        return keys
    }

    private static func orderedAPIKeys(for source: ThirdPartySource) -> [(Int, String)] {
        let keys = sourceAPIKeys(for: source)
        var seen = Set<String>()
        let unique = keys.enumerated().compactMap { index, key -> (Int, String)? in
            seen.insert(key).inserted ? (index, key) : nil
        }
        let preferred = UserDefaults.standard.integer(forKey: preferredKeyIndexDefaultsKey(for: source))
        guard let hit = unique.firstIndex(where: { $0.0 == preferred }), hit > 0 else {
            return unique
        }
        var reordered = unique
        let item = reordered.remove(at: hit)
        reordered.insert(item, at: 0)
        return reordered
    }

    private static func rememberWorkingKey(_ index: Int, for source: ThirdPartySource) {
        UserDefaults.standard.set(index, forKey: preferredKeyIndexDefaultsKey(for: source))
    }

    private static func preferredKeyIndexDefaultsKey(for source: ThirdPartySource) -> String {
        "beans.unblock.preferredKeyIndex.\(source.id)"
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
