import Foundation

enum UnblockService {
    struct Resolved {
        let url: URL
        let source: String
        let quality: ThirdPartyAudioQuality

        var sourceTitle: String { source }

        init(url: URL, source: String, quality: ThirdPartyAudioQuality = .kb320) {
            self.url = url
            self.source = source
            self.quality = quality
        }
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
        quality: ThirdPartyAudioQuality = .current,
        strict: Bool = false,
        excludedHosts: Set<String> = []
    ) async -> Resolved? {
        let hasSongIdentity = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !artists.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasSongIdentity else { return nil }
        let useFreeAudioSource = UserDefaults.standard.object(forKey: "beans.useFreeAudioSource") as? Bool ?? false
        let sources = UnblockSourceStore.shared.sources
            .filter { source in
                guard source.enabled else { return false }
                if UnblockSourceStore.singleSourceMode {
                    return source.id == UnblockSourceStore.singleSourceID
                }
                return source.isFree == useFreeAudioSource && (
                    isScriptSource(source) ||
                    canUse(source: source, songSource: songSource, neteaseID: neteaseID, qqMid: qqMid, kugouID: kugouID)
                )
            }
        guard !sources.isEmpty else {
            let mode = UnblockSourceStore.singleSourceMode
                ? "CR专用"
                : (useFreeAudioSource ? "免费" : "付费")
            BeansLogger.shared.log(
                "第三方音源未启用可用源：模式=\(mode) 平台=\(songSource.rawValue)",
                level: .debug
            )
            return nil
        }

        // LX、CR、QT 三个预设最终访问同一个接口，只保留每个请求指纹的第一个，
        // 避免同一首歌重复请求同一个服务，尤其避免酷狗回退时触发请求风暴。
        var seen = Set<String>()
        let uniqueSources = sources.filter { seen.insert(requestFingerprint(for: $0)).inserted }

        // 慢源/失效源不要拖住播放：全部候选一起请求，最快命中的播放地址直接返回。
        return await withTaskGroup(of: Resolved?.self) { group in
            for source in uniqueSources {
                group.addTask {
                    if isScriptSource(source) {
                        return await scriptSourceRequest(
                            source: source,
                            name: name,
                            artists: artists,
                            neteaseID: neteaseID,
                            songSource: songSource,
                            qqMid: qqMid,
                            qqMediaMid: qqMediaMid,
                            kugouID: kugouID,
                            preferredQuality: quality,
                            excludedHosts: excludedHosts
                        )
                    }
                    return await presetSourceRequest(
                        source: source,
                        name: name,
                        artists: artists,
                        neteaseID: neteaseID,
                        songSource: songSource,
                        qqMid: qqMid,
                        qqMediaMid: qqMediaMid,
                        kugouID: kugouID,
                        preferredQuality: quality,
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

    private static func isScriptSource(_ source: ThirdPartySource) -> Bool {
        let kind = source.kind.lowercased()
        return kind.contains("script") || source.script?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
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
        preferredQuality: ThirdPartyAudioQuality,
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
            for (qualityIndex, quality) in qualityCandidates(for: source, songSource: songSource, preferredQuality: preferredQuality).enumerated() {
                if qualityIndex > 0 {
                    BeansLogger.shared.log("第三方音源自动降级：\(source.name) 音质=\(quality)", level: .debug)
                }
                let urlString = replacingQualityPlaceholders(in: baseURLString, with: quality)
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

    private static func scriptSourceRequest(
        source: ThirdPartySource,
        name: String,
        artists: String,
        neteaseID: Int,
        songSource: SongSource,
        qqMid: String?,
        qqMediaMid: String?,
        kugouID: String?,
        preferredQuality: ThirdPartyAudioQuality,
        excludedHosts: Set<String>
    ) async -> Resolved? {
        guard let script = source.script?.trimmingCharacters(in: .whitespacesAndNewlines), !script.isEmpty else { return nil }
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

        let qualities = qualityCandidates(for: source, songSource: songSource, preferredQuality: preferredQuality)
        for songID in songIDs {
            for (qualityIndex, quality) in qualities.enumerated() {
                if qualityIndex > 0 {
                    BeansLogger.shared.log("脚本音源自动降级：\(source.name) 音质=\(quality)", level: .debug)
                }
                if let resolved = await LXScriptSourceRunner.shared.resolve(
                    source: source,
                    script: script,
                    songSource: songSource,
                    songID: songID,
                    name: name,
                    artists: artists,
                    quality: quality,
                    excludedHosts: excludedHosts
                ) {
                    BeansLogger.shared.log("脚本音源命中：\(source.name) 音质=\(quality)", level: .info)
                    return resolved
                }
            }
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
        let metadataKeys: Set<String> = [
            "source", "quality", "qualities", "qualityOptions", "qualitys",
            "br", "level", "apiKey", "apiKeys"
        ]
        for (key, value) in source.headers where !metadataKeys.contains(key) {
            let resolvedValue = value
                .replacingOccurrences(of: "{quality}", with: quality)
                .replacingOccurrences(of: "{source}", with: source.headers["source"] ?? "")
            request.setValue(resolvedValue, forHTTPHeaderField: key)
        }
        request.setValue(quality, forHTTPHeaderField: "quality")
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
              let playURL = playablePlaybackURL(from: rawPlayURL, source: source, keyLabel: keyLabel, excludedHosts: excludedHosts) else {
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
        return Resolved(
            url: playURL,
            source: source.name,
            quality: ThirdPartyAudioQuality(sourceValue: quality) ?? .kb320
        )
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

    private static func replacingQualityPlaceholders(in template: String, with quality: String) -> String {
        ["{quality}", "{br}", "{level}"].reduce(template) { result, placeholder in
            result.replacingOccurrences(of: placeholder, with: quality)
        }
    }

    private static func qualityCandidates(for source: ThirdPartySource, songSource: SongSource, preferredQuality: ThirdPartyAudioQuality) -> [String] {
        let provider = providerCode(for: songSource)
        let supported = Set(UnblockSourceStore.supportedQualities(for: source, providerCode: provider))
        let platformSupported = Set(ThirdPartyAudioQuality.supported(providerCode: provider))
        let sourceDefault = ThirdPartyAudioQuality(sourceValue: source.quality)
        let platformDefault: ThirdPartyAudioQuality = {
            switch songSource {
            case .netease, .qq, .kugou:
                return .kb320
            }
        }()

        var ordered: [ThirdPartyAudioQuality] = []
        ordered.append(contentsOf: preferredQuality.fallbackChain)
        if let sourceDefault, sourceDefault != preferredQuality {
            ordered.append(contentsOf: sourceDefault.fallbackChain)
        }
        if platformDefault != preferredQuality && platformDefault != sourceDefault {
            ordered.append(contentsOf: platformDefault.fallbackChain)
        }

        let filtered = ordered.filter {
            platformSupported.contains($0) && (supported.isEmpty || supported.contains($0))
        }
        var seen = Set<String>()
        let result = filtered.compactMap { quality -> String? in
            let trimmed = quality.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || !seen.insert(trimmed).inserted ? nil : trimmed
        }
        if !result.isEmpty { return result }

        // 若源只声明了非标准档位，至少尝试它声明过的档位，不能越过能力表强行请求未知音质。
        if !supported.isEmpty {
            return UnblockSourceStore
                .supportedQualities(for: source, providerCode: provider)
                .map(\.rawValue)
        }

        var fallbackSeen = Set<String>()
        return ordered.compactMap { quality -> String? in
            let trimmed = quality.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || !fallbackSeen.insert(trimmed).inserted ? nil : trimmed
        }
    }

    private static func qqIDCandidates(songID: Int, songMid: String, mediaMid: String?) -> [String] {
        var seen = Set<String>()
        let numericID = songID > 0 ? String(songID) : nil
        return [numericID, mediaMid, songMid].compactMap { raw in
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
        let scriptFingerprint = source.script?.hashValue.description ?? ""
        return "\(source.template)|\(source.urlPath)|\(headers)|\(source.quality)|\(scriptFingerprint)"
    }

    private static func userAPIKeys() -> [String] {
        UserDefaults.standard.string(forKey: UnblockSourceStore.userAPIKeysKey)?
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private static func sourceAPIKeys(for source: ThirdPartySource) -> [String] {
        if isScriptSource(source) { return userAPIKeys() }
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
