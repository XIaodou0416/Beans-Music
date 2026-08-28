import Foundation
import JavaScriptCore

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
                    } else if source.kind == "lx-raw-script" {
                        return await lxRawScript(source: source, name: name, artists: artists, durationMS: durationMS, songSource: songSource, neteaseID: neteaseID, qqMid: qqMid, kugouID: kugouID)
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

    /// 原生 LX 脚本兜底。仅在后台执行脚本的 musicUrl 事件，并提供同步 HTTP request 桥。
    private static func lxRawScript(source: ThirdPartySource, name: String, artists: String, durationMS: Int, songSource: SongSource, neteaseID: Int, qqMid: String?, kugouID: String?) async -> Resolved? {
        guard !source.template.isEmpty else { return nil }
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

        return await Task.detached(priority: .utility) {
            guard let context = JSContext() else { return nil }
            var contextRef: JSContext? = context
            context.exceptionHandler = { _, exception in
                if let message = exception?.toString(), !message.isEmpty {
                    BeansLogger.shared.log("LX脚本执行异常：\(source.name) \(message)", level: .debug)
                }
            }

            let requestBlock: @convention(block) (JSValue?, JSValue?, JSValue?) -> JSValue? = { urlValue, optionsValue, callbackValue in
                let urlString = urlValue?.toString() ?? ""
                let options = optionsValue?.toDictionary() as? [String: Any] ?? [:]
                let response = blockingScriptRequest(urlString: urlString, options: options)
                if let callbackValue, callbackValue.isObject {
                    callbackValue.call(withArguments: [NSNull(), response])
                }
                return JSValue(object: response, in: contextRef)
            }
            let logBlock: @convention(block) (String) -> Void = { message in
                BeansLogger.shared.log("LX脚本：\(message)", level: .debug)
            }
            context.setObject(requestBlock, forKeyedSubscript: "__beansRequest" as NSString)
            context.setObject(logBlock, forKeyedSubscript: "__beansLog" as NSString)
            context.evaluateScript("""
            var __beansHandler = null;
            var __beansDone = false;
            var __beansResult = null;
            var __beansError = null;
            globalThis.module = { exports: {} };
            globalThis.exports = globalThis.module.exports;
            globalThis.process = { env: {} };
            globalThis.require = function() { return {}; };
            globalThis.lx = {
              EVENT_NAMES: { inited: 'inited', request: 'request' },
              env: 'ios',
              version: '1.0.0',
              utils: {},
              request: function(url, options, callback) {
                if (url && typeof url === 'object') {
                  return __beansRequest(url.url || url.uri || url.href || '', url, options);
                }
                return __beansRequest(url, options || {}, callback);
              },
              on: function(name, handler) { if (name === 'request') __beansHandler = handler; },
              send: function() {}
            };
            globalThis.fetch = function(url, options) {
              var resp = globalThis.lx.request(url, options || {});
              return Promise.resolve({
                ok: resp && resp.statusCode >= 200 && resp.statusCode < 300,
                status: resp ? resp.statusCode : 0,
                statusText: '',
                headers: {},
                json: function() { return Promise.resolve(resp ? resp.body : null); },
                text: function() {
                  var body = resp ? resp.body : '';
                  return Promise.resolve(typeof body === 'string' ? body : JSON.stringify(body || {}));
                }
              });
            };
            globalThis.console = { log: function(msg) { __beansLog(String(msg)); }, warn: function(msg) { __beansLog(String(msg)); }, error: function(msg) { __beansLog(String(msg)); } };
            """)
            context.evaluateScript(source.template)
            guard context.objectForKeyedSubscript("__beansHandler")?.isUndefined == false else {
                BeansLogger.shared.log("LX脚本未注册 musicUrl 处理器：\(source.name)", level: .debug)
                contextRef = nil
                return nil
            }

            let info: [String: Any] = [
                "id": songID,
                "hash": provider == "kg" ? songID : "",
                "songmid": provider == "tx" ? songID : "",
                "mid": provider == "tx" ? songID : "",
                "name": name,
                "songName": name,
                "singer": artists,
                "artist": artists,
                "artists": artists,
                "interval": durationMS / 1000,
                "duration": durationMS,
                "quality": source.headers["quality"] ?? "flac",
                "type": source.headers["quality"] ?? "flac"
            ]
            let args: [String: Any] = [
                "source": provider,
                "action": "musicUrl",
                "quality": source.headers["quality"] ?? "flac",
                "info": info,
                "musicInfo": info
            ]
            guard let argsData = try? JSONSerialization.data(withJSONObject: args),
                  let argsJSON = String(data: argsData, encoding: .utf8) else {
                contextRef = nil
                return nil
            }
            context.evaluateScript("""
            Promise.resolve(__beansHandler(\(argsJSON))).then(function(value) {
              __beansResult = value;
              __beansDone = true;
            }).catch(function(error) {
              __beansError = error && error.message ? error.message : String(error);
              __beansDone = true;
            });
            """)

            let deadline = Date().addingTimeInterval(7)
            while Date() < deadline {
                if context.objectForKeyedSubscript("__beansDone")?.toBool() == true {
                    break
                }
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
                context.evaluateScript("void 0")
            }
            if let error = context.objectForKeyedSubscript("__beansError")?.toString(), !error.isEmpty, error != "undefined" {
                BeansLogger.shared.log("LX脚本返回失败：\(source.name) \(error)", level: .debug)
            }
            let result = context.objectForKeyedSubscript("__beansResult")
            let urlString = scriptResultURL(result, urlPath: source.urlPath)
            contextRef = nil
            guard let urlString, let url = URL(string: urlString) else { return nil }
            BeansLogger.shared.log("导入音源命中：\(source.name) 平台=\(provider)", level: .info)
            return Resolved(url: url, source: source.name)
        }.value
    }

    private static func blockingScriptRequest(urlString: String, options: [String: Any]) -> [String: Any] {
        guard let url = URL(string: urlString) else {
            return ["statusCode": -1, "body": ["code": -1, "msg": "bad url"]]
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 7
        request.httpMethod = (options["method"] as? String ?? "GET").uppercased()
        if let headers = options["headers"] as? [String: Any] {
            for (key, value) in headers {
                request.setValue("\(value)", forHTTPHeaderField: key)
            }
        }
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue("lx-music-mobile/1.0", forHTTPHeaderField: "User-Agent")
        }
        if let body = options["body"] {
            if let text = body as? String {
                request.httpBody = text.data(using: .utf8)
            } else if JSONSerialization.isValidJSONObject(body) {
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            }
        }
        let semaphore = DispatchSemaphore(value: 0)
        var responseData = Data()
        var statusCode = -1
        var responseError: String?
        URLSession.shared.dataTask(with: request) { data, response, error in
            responseData = data ?? Data()
            statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            responseError = error?.localizedDescription
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 8)
        let body: Any
        if let json = try? JSONSerialization.jsonObject(with: responseData) {
            body = json
        } else {
            body = String(data: responseData, encoding: .utf8) ?? ""
        }
        if let responseError {
            return ["statusCode": statusCode, "body": ["code": -1, "msg": responseError]]
        }
        return ["statusCode": statusCode, "body": body]
    }

    private static func scriptResultURL(_ result: JSValue?, urlPath: String) -> String? {
        guard let result, !result.isUndefined, !result.isNull else { return nil }
        if let text = result.toString(), text.hasPrefix("http") {
            return text
        }
        if let dict = result.toDictionary() {
            if let value = valueAtAnyPath(dict, urlPath) as? String, value.hasPrefix("http") {
                return value
            }
            if let body = dict["body"] as? [String: Any],
               let value = valueAtAnyPath(body, urlPath) as? String, value.hasPrefix("http") {
                return value
            }
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
