import Foundation

/// 灰色歌曲 / VIP 试听解锁：仅使用用户导入的自定义音源（JSON 配置 / 落雪 API 服务器）
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

    /// 统一的 GET 请求（带移动端 UA，提升第三方接口可用性）
    private static func get(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 7
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await session.data(for: request),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return data
    }

    /// 入口：并发尝试可用于当前平台的音源，返回第一个可用地址。
    static func resolve(
        name: String,
        artists: String,
        durationMS: Int,
        neteaseID: Int,
        songSource: SongSource = .netease,
        qqMid: String? = nil,
        kugouID: String? = nil,
        strict: Bool = false
    ) async -> Resolved? {
        let keyword = ([name, artists].filter { !$0.isEmpty })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return nil }
        let sources = UnblockSourceStore.shared.customSources
            .filter { $0.enabled && canUse(source: $0, songSource: songSource, neteaseID: neteaseID, qqMid: qqMid, kugouID: kugouID) }
        guard !sources.isEmpty else { return nil }

        // 慢源/失效源不要拖住播放：全部候选一起请求，最快命中的播放地址直接返回。
        return await withTaskGroup(of: Resolved?.self) { group in
            for source in sources {
                group.addTask {
                    if source.kind == "lx-script" {
                        return await lxScript(source: source, songSource: songSource, neteaseID: neteaseID, qqMid: qqMid, kugouID: kugouID)
                    } else if source.kind == "lx-post-json" {
                        return await lxPostJSON(source: source, songSource: songSource, neteaseID: neteaseID, qqMid: qqMid, kugouID: kugouID)
                    } else if source.kind == "lx" {
                        return await lx(source: source, keyword: keyword)
                    } else {
                        return await custom(
                            source: source,
                            name: name,
                            artists: artists,
                            neteaseID: neteaseID,
                            songSource: songSource,
                            qqMid: qqMid,
                            kugouID: kugouID
                        )
                    }
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

    // MARK: - 洛雪音源脚本转换配置

    /// Huibq keep-alive 等洛雪脚本的 musicUrl 协议：GET /url/{source}/{songId}/{quality}。
    private static func lxScript(source: ThirdPartySource, songSource: SongSource, neteaseID: Int, qqMid: String?, kugouID: String?) async -> Resolved? {
        let provider = source.headers["source"] ?? ""
        let songID: String
        switch (songSource, provider) {
        case (.netease, "wy") where neteaseID > 0:
            songID = String(neteaseID)
        case (.qq, "tx"):
            guard let qqMid, !qqMid.isEmpty else { return nil }
            songID = qqMid
        case (.kugou, "kg"):
            guard let kugouID, !kugouID.isEmpty else { return nil }
            songID = kugouID
        default:
            return nil
        }

        let base = source.template.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let preferred = source.headers["quality"] ?? source.headers["br"] ?? "320k"
        let qualities = preferred == "128k" ? ["128k"] : [preferred, "128k"]
        for quality in qualities {
            guard let url = URL(string: "\(base)/url/\(provider)/\(songID)/\(quality)") else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 7
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("lx-music-mobile/1.0", forHTTPHeaderField: "User-Agent")
            if let apiKey = source.headers["apiKey"], !apiKey.isEmpty {
                request.setValue(apiKey, forHTTPHeaderField: "X-Request-Key")
            }
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse else {
                BeansLogger.shared.log("导入音源请求失败：\(source.name) 平台=\(provider) 音质=\(quality)", level: .debug)
                continue
            }
            guard http.statusCode == 200 else {
                BeansLogger.shared.log("导入音源 HTTP 失败：\(source.name) 状态=\(http.statusCode) 平台=\(provider) 音质=\(quality)", level: .debug)
                continue
            }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                BeansLogger.shared.log("导入音源响应格式错误：\(source.name)", level: .debug)
                continue
            }
            let code = object["code"] as? Int ?? Int(object["code"] as? String ?? "") ?? -1
            guard code == 0,
                  let urlString = object["url"] as? String,
                  !urlString.isEmpty,
                  let playURL = URL(string: urlString) else {
                let message = object["msg"] as? String ?? "code=\(code)"
                BeansLogger.shared.log("导入音源返回失败：\(source.name) \(message)", level: .debug)
                continue
            }
            BeansLogger.shared.log("导入音源命中：\(source.name) 平台=\(provider) 音质=\(quality)", level: .info)
            return Resolved(url: playURL, source: source.name)
        }
        return nil
    }

    /// 新式 LX 脚本协议：POST /music/url，body = source/musicId/quality。
    private static func lxPostJSON(source: ThirdPartySource, songSource: SongSource, neteaseID: Int, qqMid: String?, kugouID: String?) async -> Resolved? {
        let provider = source.headers["source"] ?? providerCode(for: songSource)
        let songID: String
        switch (songSource, provider) {
        case (.netease, "wy") where neteaseID > 0:
            songID = String(neteaseID)
        case (.qq, "tx"):
            guard let qqMid, !qqMid.isEmpty else { return nil }
            songID = qqMid
        case (.kugou, "kg"):
            guard let kugouID, !kugouID.isEmpty else { return nil }
            songID = kugouID
        default:
            return nil
        }

        let base = source.template.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let endpoint = base.hasSuffix("/music/url") ? base : "\(base)/music/url"
        let preferred = source.headers["quality"] ?? source.headers["br"] ?? "flac"
        for quality in lxPostQualities(preferred) {
            guard let url = URL(string: endpoint) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 7
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("lx-music-mobile/1.0", forHTTPHeaderField: "User-Agent")
            if let apiKey = source.headers["apiKey"], !apiKey.isEmpty {
                request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
                request.setValue(apiKey, forHTTPHeaderField: "X-Request-Key")
            }
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "source": provider,
                "musicId": songID,
                "quality": quality
            ])

            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse else {
                BeansLogger.shared.log("导入音源请求失败：\(source.name) 平台=\(provider) 音质=\(quality)", level: .debug)
                continue
            }
            guard http.statusCode == 200 else {
                BeansLogger.shared.log("导入音源 HTTP 失败：\(source.name) 状态=\(http.statusCode) 平台=\(provider) 音质=\(quality)", level: .debug)
                continue
            }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                BeansLogger.shared.log("导入音源响应格式错误：\(source.name)", level: .debug)
                continue
            }
            let code = object["code"] as? Int ?? Int(object["code"] as? String ?? "") ?? 200
            guard code == 0 || code == 200,
                  let value = valueAtAnyPath(object, source.urlPath),
                  let urlString = value as? String,
                  !urlString.isEmpty,
                  let playURL = URL(string: urlString) else {
                let message = object["msg"] as? String ?? object["message"] as? String ?? "code=\(code)"
                BeansLogger.shared.log("导入音源返回失败：\(source.name) \(message)", level: .debug)
                continue
            }
            BeansLogger.shared.log("导入音源命中：\(source.name) 平台=\(provider) 音质=\(quality)", level: .info)
            return Resolved(url: playURL, source: source.name)
        }
        return nil
    }

    private static func custom(
        source: ThirdPartySource,
        name: String,
        artists: String,
        neteaseID: Int,
        songSource: SongSource,
        qqMid: String?,
        kugouID: String?
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
        var urlString = source.template
        urlString = urlString.replacingOccurrences(of: "{id}", with: songID)
        urlString = urlString.replacingOccurrences(of: "{name}", with: urlEncoded(name))
        let keyword = ([name, artists].filter { !$0.isEmpty }).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        urlString = urlString.replacingOccurrences(of: "{keyword}", with: urlEncoded(keyword))
        urlString = urlString.replacingOccurrences(of: "{artist}", with: urlEncoded(artists))
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 7
        let metadataKeys: Set<String> = ["source", "quality", "br", "apiKey"]
        for (key, value) in source.headers where !metadataKeys.contains(key) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            BeansLogger.shared.log("导入音源请求失败：\(source.name) \(error.localizedDescription)", level: .debug)
            return nil
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            BeansLogger.shared.log("导入音源 HTTP 失败：\(source.name) 状态=\(status)", level: .debug)
            return nil
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = valueAtAnyPath(obj, source.urlPath),
              let resolvedURL = value as? String, !resolvedURL.isEmpty,
              let playURL = URL(string: resolvedURL) else {
            BeansLogger.shared.log("导入音源响应中没有播放地址：\(source.name)", level: .debug)
            return nil
        }
        BeansLogger.shared.log("导入音源命中：\(source.name) 平台=\(expectedProvider)", level: .info)
        return Resolved(url: playURL, source: source.name)
    }

    private static func providerCode(for source: SongSource) -> String {
        switch source {
        case .netease: return "wy"
        case .qq: return "tx"
        case .kugou: return "kg"
        }
    }

    private static func lxPostQualities(_ preferred: String) -> [String] {
        let normalized = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = ["flac24bit", "hires", "flac", "320k", "128k"]
        guard !normalized.isEmpty else { return fallback }
        return [normalized] + fallback.filter { $0 != normalized }
    }

    // MARK: - 落雪音乐源（lx-music-api-server 风格 HTTP API）
    /// 兼容落雪 API 服务器（如 lx-music-api-server）：先按关键词搜索拿到歌曲 id，
    /// 再请求播放地址。headers 里可配置 source（wy/tx）与 br（默认 320）。
    private static func lx(source: ThirdPartySource, keyword: String) async -> Resolved? {
        guard source.kind == "lx", !source.template.isEmpty else { return nil }
        let base = source.template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: base) else { return nil }
        let lxSource = source.headers["source"] ?? "wy"
        let br = source.headers["br"] ?? "320"
        // 1) 搜索：GET /music/search?source=&query=&page=1&limit=5
        var searchComps = URLComponents(url: baseURL.appendingPathComponent("music/search"), resolvingAgainstBaseURL: false)
        searchComps?.queryItems = [
            URLQueryItem(name: "source", value: lxSource),
            URLQueryItem(name: "query", value: keyword),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let searchURL = searchComps?.url, let data = await get(searchURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = obj["data"] as? [String: Any],
              let list = dataObj["list"] as? [[String: Any]],
              let first = list.first,
              let id = first["id"] as? String ?? (first["id"] as? Int).map(String.init)
        else { return nil }
        // 2) 取播放地址：GET /music/url?source=&id=&br=
        var urlComps = URLComponents(url: baseURL.appendingPathComponent("music/url"), resolvingAgainstBaseURL: false)
        urlComps?.queryItems = [
            URLQueryItem(name: "source", value: lxSource),
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "br", value: br)
        ]
        guard let urlURL = urlComps?.url, let data2 = await get(urlURL),
              let obj2 = try? JSONSerialization.jsonObject(with: data2) as? [String: Any],
              let d2 = obj2["data"] as? [String: Any],
              let urlStr = d2["url"] as? String, !urlStr.isEmpty,
              let playURL = URL(string: urlStr)
        else { return nil }
        return Resolved(url: playURL, source: "落雪 (\(lxSource))")
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
