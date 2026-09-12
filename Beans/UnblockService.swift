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

    private struct ResolutionCacheEntry {
        let resolved: Resolved
        let expiresAt: Date
    }

    private struct PersistentResolutionCacheEntry: Codable {
        let url: String
        let source: String
        let quality: String
        let expiresAt: Date
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        // 音源解析是切歌关键路径，缩短单个失效源的阻塞时间，让其它源更快接管。
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 8
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    private static let resolutionCacheLock = NSLock()
    private static var resolutionCache: [String: ResolutionCacheEntry] = [:]
    private static let resolutionCacheTTL: TimeInterval = 35
    private static let persistentResolutionCacheKey = "beans.thirdPartyPlaybackURLCache.v1"
    private static let persistentResolutionCacheTTL: TimeInterval = 30 * 60
    private static let persistentResolutionCacheLimit = 200
    private static var persistentResolutionCache: [String: PersistentResolutionCacheEntry] = [:]
    private static var persistentCacheLoaded = false

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
        let sources = UnblockSourceStore.shared.sources
            .filter { source in
                guard source.enabled else { return false }
                return isScriptSource(source)
                    || canUse(source: source, songSource: songSource, neteaseID: neteaseID, qqMid: qqMid, kugouID: kugouID)
            }
        guard !sources.isEmpty else {
            return nil
        }

        let cacheKey = resolutionCacheKey(
            name: name,
            artists: artists,
            neteaseID: neteaseID,
            songSource: songSource,
            qqMid: qqMid,
            qqMediaMid: qqMediaMid,
            kugouID: kugouID,
            quality: quality,
            strict: strict,
            sources: sources
        )
        if let cached = cachedResolution(for: cacheKey, excludedHosts: excludedHosts) {
            return cached
        }

        let resolved = await resolveSources(
            sources,
            name: name,
            artists: artists,
            neteaseID: neteaseID,
            songSource: songSource,
            qqMid: qqMid,
            qqMediaMid: qqMediaMid,
            kugouID: kugouID,
            quality: quality,
            excludedHosts: excludedHosts
        )
        if let resolved {
            storeResolution(resolved, for: cacheKey)
        }
        return resolved
    }

    private static func resolutionCacheKey(
        name: String,
        artists: String,
        neteaseID: Int,
        songSource: SongSource,
        qqMid: String?,
        qqMediaMid: String?,
        kugouID: String?,
        quality: ThirdPartyAudioQuality,
        strict: Bool,
        sources: [ThirdPartySource]
    ) -> String {
        let sourceFingerprint = sources.map { requestFingerprint(for: $0) }.joined(separator: "||")
        return [
            songSource.rawValue,
            String(neteaseID),
            qqMid ?? "",
            qqMediaMid ?? "",
            kugouID ?? "",
            name,
            artists,
            quality.rawValue,
            strict ? "strict" : "normal",
            sourceFingerprint
        ].joined(separator: "|")
    }

    private static func cachedResolution(for key: String, excludedHosts: Set<String>) -> Resolved? {
        resolutionCacheLock.lock()
        defer { resolutionCacheLock.unlock() }
        loadPersistentCacheIfNeededLocked()
        let now = Date()

        if let entry = resolutionCache[key] {
            if entry.expiresAt <= now {
                resolutionCache.removeValue(forKey: key)
            } else {
                guard let host = entry.resolved.url.host?.lowercased(), !excludedHosts.contains(host) else {
                    return nil
                }
                return entry.resolved
            }
        }

        guard let persistentEntry = persistentResolutionCache[key] else {
            return nil
        }
        guard persistentEntry.expiresAt > now else {
            persistentResolutionCache.removeValue(forKey: key)
            persistCacheLocked()
            return nil
        }
        guard let url = URL(string: persistentEntry.url),
              let quality = ThirdPartyAudioQuality(rawValue: persistentEntry.quality),
              let host = url.host?.lowercased(),
              !excludedHosts.contains(host) else {
            persistentResolutionCache.removeValue(forKey: key)
            persistCacheLocked()
            return nil
        }

        let resolved = Resolved(url: url, source: persistentEntry.source, quality: quality)
        resolutionCache[key] = ResolutionCacheEntry(
            resolved: resolved,
            expiresAt: now.addingTimeInterval(resolutionCacheTTL)
        )
        return resolved
    }

    private static func storeResolution(_ resolved: Resolved, for key: String) {
        resolutionCacheLock.lock()
        loadPersistentCacheIfNeededLocked()
        let now = Date()
        resolutionCache[key] = ResolutionCacheEntry(
            resolved: resolved,
            expiresAt: now.addingTimeInterval(resolutionCacheTTL)
        )
        // 避免长期运行的应用持续保留已经过期的地址。
        resolutionCache = resolutionCache.filter { $0.value.expiresAt > now }
        persistentResolutionCache[key] = PersistentResolutionCacheEntry(
            url: resolved.url.absoluteString,
            source: resolved.source,
            quality: resolved.quality.rawValue,
            expiresAt: now.addingTimeInterval(persistentResolutionCacheTTL)
        )
        persistentResolutionCache = persistentResolutionCache
            .filter { $0.value.expiresAt > now }
            .sorted { $0.value.expiresAt > $1.value.expiresAt }
            .prefix(persistentResolutionCacheLimit)
            .reduce(into: [String: PersistentResolutionCacheEntry]()) { result, item in
                result[item.key] = item.value
            }
        persistCacheLocked()
        resolutionCacheLock.unlock()
    }

    private static func loadPersistentCacheIfNeededLocked() {
        guard !persistentCacheLoaded else { return }
        persistentCacheLoaded = true
        guard let data = UserDefaults.standard.data(forKey: persistentResolutionCacheKey),
              let decoded = try? JSONDecoder().decode(
                [String: PersistentResolutionCacheEntry].self,
                from: data
              ) else {
            return
        }
        let now = Date()
        persistentResolutionCache = decoded.filter { $0.value.expiresAt > now }
        if persistentResolutionCache.count != decoded.count {
            persistCacheLocked()
        }
    }

    private static func persistCacheLocked() {
        guard let data = try? JSONEncoder().encode(persistentResolutionCache) else { return }
        UserDefaults.standard.set(data, forKey: persistentResolutionCacheKey)
    }

    private static func resolveSources(
        _ sources: [ThirdPartySource],
        name: String,
        artists: String,
        neteaseID: Int,
        songSource: SongSource,
        qqMid: String?,
        qqMediaMid: String?,
        kugouID: String?,
        quality: ThirdPartyAudioQuality,
        excludedHosts: Set<String>
    ) async -> Resolved? {
        guard !sources.isEmpty else { return nil }

        // 相同配置只保留每个请求指纹的第一个，避免重复请求同一个服务。
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
        let apiKeyPlaceholders = ["{apiKey}", "{apikey}", "{key}"]
        let requiresAPIKey = apiKeyPlaceholders.contains { source.template.contains($0) }
        if requiresAPIKey && apiKeys.isEmpty {
            return nil
        }
        for songID in songIDs {
            var baseURLString = source.template
            let idValues: [String: String] = [
                "{id}": songID,
                "{songId}": songID,
                "{songid}": songID,
                "{songID}": songID,
                "{songmid}": qqMid ?? songID,
                "{mid}": qqMid ?? songID,
                "{hash}": kugouID ?? songID
            ]
            for (placeholder, value) in idValues {
                baseURLString = baseURLString.replacingOccurrences(of: placeholder, with: value)
            }
            baseURLString = baseURLString.replacingOccurrences(of: "{source}", with: expectedProvider)
            baseURLString = baseURLString.replacingOccurrences(of: "{name}", with: urlEncoded(name))
            let keyword = ([name, artists].filter { !$0.isEmpty }).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            baseURLString = baseURLString.replacingOccurrences(of: "{keyword}", with: urlEncoded(keyword))
            baseURLString = baseURLString.replacingOccurrences(of: "{artist}", with: urlEncoded(artists))
            for quality in qualityCandidates(for: source, songSource: songSource, preferredQuality: preferredQuality) {
                let urlString = replacingQualityPlaceholders(in: baseURLString, with: quality)
                if !apiKeys.isEmpty {
                    for (originalIndex, apiKey) in apiKeys {
                        let keyedURLString = apiKeyPlaceholders.reduce(urlString) { result, placeholder in
                            result.replacingOccurrences(of: placeholder, with: urlEncoded(apiKey))
                        }
                        guard let url = URL(string: keyedURLString) else { continue }
                        if let resolved = await presetSourceRequestOnce(
                            source: source,
                            url: url,
                            apiKey: apiKey,
                            quality: quality,
                            excludedHosts: excludedHosts
                        ) {
                            rememberWorkingKey(originalIndex, for: source)
                            return resolved
                        }
                    }
                } else if !requiresAPIKey,
                          let url = URL(string: urlString),
                          let resolved = await presetSourceRequestOnce(
                    source: source,
                    url: url,
                    apiKey: nil,
                    quality: quality,
                    excludedHosts: excludedHosts
                ) {
                    return resolved
                }
            }
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
            var candidates: [String] = [qqMid]
            if let qqMediaMid, !qqMediaMid.isEmpty {
                candidates.append(qqMediaMid)
            }
            if neteaseID > 0 {
                candidates.append(String(neteaseID))
            }
            var seen = Set<String>()
            songIDs = candidates.filter { seen.insert($0).inserted }
        case .kugou:
            guard let kugouID, !kugouID.isEmpty else { return nil }
            songIDs = [kugouID]
        default:
            return nil
        }

        let qualities = qualityCandidates(for: source, songSource: songSource, preferredQuality: preferredQuality)
        for songID in songIDs {
            for quality in qualities {
                if let resolved = await LXScriptSourceRunner.shared.resolve(
                    source: source,
                    script: script,
                    songSource: songSource,
                    songID: songID,
                    qqMid: qqMid,
                    qqMediaMid: qqMediaMid,
                    kugouID: kugouID,
                    name: name,
                    artists: artists,
                    quality: quality,
                    excludedHosts: excludedHosts
                ) {
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
        let metadataKeys: Set<String> = [
            "source", "quality", "qualities", "qualityOptions", "qualitys",
            "br", "level", "apiKey", "apiKeys", "apiKeyQuery"
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
            return nil
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let code = responseCode(from: obj), code != 0 && code != 200 {
            return nil
        }
        guard let value = valueAtAnyPath(obj, source.urlPath),
              let resolvedURL = value as? String, !resolvedURL.isEmpty,
              let rawPlayURL = URL(string: resolvedURL),
              let playURL = playablePlaybackURL(from: rawPlayURL, excludedHosts: excludedHosts) else {
            return nil
        }
        return Resolved(
            url: playURL,
            source: source.name,
            quality: ThirdPartyAudioQuality(sourceValue: quality) ?? .kb320
        )
    }

    /// 部分第三方接口会固定返回不稳定的 QQ CDN 节点。
    /// 不在这里做 Range 探测：部分 QQ CDN 会拒绝探测请求，但 AVPlayer
    /// 带完整请求头后仍可正常播放。实际失败由 AVPlayer 反馈，再换下一个节点。
    private static func playablePlaybackURL(from rawURL: URL, excludedHosts: Set<String>) -> URL? {
        let candidates = qqPlaybackURLCandidates(for: rawURL)
        for candidate in candidates {
            guard let host = candidate.host?.lowercased() else { continue }
            if excludedHosts.contains(host) {
                continue
            }
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

    private static func requestFingerprint(for source: ThirdPartySource) -> String {
        let headers = source.headers
            .filter { $0.key != "source" }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        let scriptFingerprint = source.script?.hashValue.description ?? ""
        return "\(source.template)|\(source.urlPath)|\(headers)|\(source.quality)|\(scriptFingerprint)"
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
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
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
            if let dict = current as? [String: Any], let next = dict[String(key)] {
                current = next
            } else if let dict = current as? NSDictionary, let next = dict[String(key)] {
                current = next
            } else {
                return nil
            }
        }
        return current
    }

    private static func urlEncoded(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
    }

}
