import Foundation
import JavaScriptCore

@objc protocol BeansLXScriptBufferExports: JSExport {
    func from(_ text: String, _ encoding: String) -> NSDictionary
    func bufToString(_ buffer: JSValue?, _ encoding: String) -> String
}

@objc protocol BeansLXScriptUtilsExports: JSExport {
    var buffer: BeansLXScriptBufferBridge { get }
    var crypto: BeansLXScriptCryptoBridge { get }
}

@objc protocol BeansLXScriptCryptoExports: JSExport {
    func md5(_ value: String) -> String
}

@objc protocol BeansLXScriptBridgeExports: JSExport {
    func request(_ url: String, _ options: JSValue?, _ callback: JSValue?)
    func on(_ event: String, _ handler: JSValue)
    func send(_ event: String, _ payload: JSValue?)
    var EVENT_NAMES: NSDictionary { get }
    var env: NSDictionary { get }
    var utils: BeansLXScriptUtilsBridge { get }
}

@objc protocol BeansLXScriptDoneExports: JSExport {
    func resolve(_ value: JSValue?)
    func reject(_ value: JSValue?)
}

final class BeansLXScriptBufferBridge: NSObject, BeansLXScriptBufferExports {
    func from(_ text: String, _ encoding: String) -> NSDictionary {
        [
            "text": text,
            "encoding": encoding.lowercased()
        ]
    }

    func bufToString(_ buffer: JSValue?, _ encoding: String) -> String {
        let targetEncoding = encoding.lowercased()
        let text: String
        if let dict = buffer?.toObject() as? [String: Any] {
            text = dict["text"] as? String ?? String(describing: dict["text"] ?? "")
        } else {
            text = buffer?.toString() ?? ""
        }
        switch targetEncoding {
        case "base64":
            return Data(text.utf8).base64EncodedString()
        case "utf-8", "utf8":
            return text
        default:
            return text
        }
    }
}

final class BeansLXScriptUtilsBridge: NSObject, BeansLXScriptUtilsExports {
    let buffer = BeansLXScriptBufferBridge()
    let crypto = BeansLXScriptCryptoBridge()
}

final class BeansLXScriptCryptoBridge: NSObject, BeansLXScriptCryptoExports {
    func md5(_ value: String) -> String {
        Data(value.utf8).md5Hex()
    }
}

final class BeansLXScriptDoneBridge: NSObject, BeansLXScriptDoneExports {
    var onResolve: ((Any?) -> Void)?
    var onReject: ((String) -> Void)?
    private var finished = false

    func resolve(_ value: JSValue?) {
        guard !finished else { return }
        finished = true
        onResolve?(value?.toObject())
    }

    func reject(_ value: JSValue?) {
        guard !finished else { return }
        finished = true
        onReject?(value?.toString() ?? "Script rejected")
    }
}

final class BeansLXScriptBridge: NSObject, BeansLXScriptBridgeExports {
    private let runtimeQueue: DispatchQueue
    private let session: URLSession
    weak var runtime: BeansLXScriptRuntime?

    let EVENT_NAMES: NSDictionary = [
        "request": "request",
        "inited": "inited",
        "updateAlert": "updateAlert"
    ]

    let env: NSDictionary = [
        "platform": "ios",
        "os": "iOS",
        "device": "iPhone"
    ]

    let utils = BeansLXScriptUtilsBridge()

    init(runtimeQueue: DispatchQueue) {
        self.runtimeQueue = runtimeQueue
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    func request(_ url: String, _ options: JSValue?, _ callback: JSValue?) {
        guard let callback else { return }
        let requestOptions = options?.toObject() as? [String: Any] ?? [:]
        guard let requestURL = URL(string: url) else {
            runtimeQueue.async {
                callback.call(withArguments: [[ "message": "Invalid URL" ], NSNull()])
            }
            return
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = (requestOptions["method"] as? String)?.uppercased() ?? "GET"
        if let timeout = requestOptions["timeout"] as? NSNumber {
            request.timeoutInterval = timeout.doubleValue / 1000.0 > 0 ? timeout.doubleValue / 1000.0 : request.timeoutInterval
        } else if let timeout = requestOptions["timeout"] as? Double {
            request.timeoutInterval = timeout > 0 ? timeout / 1000.0 : request.timeoutInterval
        }

        if let headers = requestOptions["headers"] as? [String: Any] {
            for (key, value) in headers {
                request.setValue(String(describing: value), forHTTPHeaderField: key)
            }
        }
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue("lx-music", forHTTPHeaderField: "User-Agent")
        }
        if let body = requestOptions["body"] {
            if let bodyData = body as? Data {
                request.httpBody = bodyData
            } else if let string = body as? String {
                request.httpBody = string.data(using: .utf8)
            } else if JSONSerialization.isValidJSONObject(body),
                      let data = try? JSONSerialization.data(withJSONObject: body) {
                request.httpBody = data
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            } else if let dict = body as? [String: Any],
                      let data = try? JSONSerialization.data(withJSONObject: dict) {
                request.httpBody = data
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            }
        }

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            self.runtimeQueue.async {
                if let error {
                    callback.call(withArguments: [[ "message": error.localizedDescription ], NSNull()])
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    callback.call(withArguments: [[ "message": "No HTTP response" ], NSNull()])
                    return
                }
                let body: Any = self.parseBody(data)
                let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                    result[String(describing: pair.key)] = String(describing: pair.value)
                }
                let responseObject: [String: Any] = [
                    "statusCode": http.statusCode,
                    "headers": headers,
                    "body": body
                ]
                if http.statusCode >= 400 {
                    callback.call(withArguments: [[ "message": "HTTP \(http.statusCode)" ], responseObject])
                } else {
                    callback.call(withArguments: [NSNull(), responseObject])
                }
            }
        }.resume()
    }

    func on(_ event: String, _ handler: JSValue) {
        runtime?.register(handler: handler, for: event)
    }

    func send(_ event: String, _ payload: JSValue?) {
        runtime?.receive(event: event, payload: payload?.toObject())
    }

    private func parseBody(_ data: Data?) -> Any {
        guard let data else { return NSNull() }
        if let json = try? JSONSerialization.jsonObject(with: data) {
            return json
        }
        if let string = String(data: data, encoding: .utf8) {
            return string
        }
        if let string = String(data: data, encoding: .utf16) {
            return string
        }
        return data.base64EncodedString()
    }
}

final class BeansLXScriptRuntime {
    private let sourceID: String
    private let queue = DispatchQueue(label: "Beans.LXScriptRuntime")
    private let context: JSContext
    private let bridge: BeansLXScriptBridge
    private var handlers: [String: JSValue] = [:]

    init?(source: ThirdPartySource, script: String) {
        sourceID = source.id
        guard let context = JSContext() else { return nil }
        self.context = context
        self.bridge = BeansLXScriptBridge(runtimeQueue: queue)
        self.bridge.runtime = self

        context.exceptionHandler = { _, exception in
            if let exception {
                BeansLogger.shared.log("第三方脚本执行异常：\(exception)", level: .debug)
            }
        }

        context.setObject(bridge, forKeyedSubscript: "lx" as NSString)
        var initialized = false
        queue.sync {
            context.evaluateScript("if (typeof globalThis === 'undefined') { var globalThis = this; }")
            context.evaluateScript("if (typeof globalThis.lx === 'undefined') { globalThis.lx = lx; }")
            context.evaluateScript("if (typeof console === 'undefined') { globalThis.console = { log: function() {}, info: function() {}, debug: function() {}, warn: function() {}, error: function() {} }; }")
            context.evaluateScript("if (typeof module === 'undefined') { var module = { exports: {} }; var exports = module.exports; }")
            let appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.6.4"
            context.evaluateScript("globalThis.cerumusic = { request: function(url, options) { return new Promise(function(resolve, reject) { lx.request(url, options, function(error, response) { if (error && error.message) { reject(error); } else { resolve(response); } }); }); }, utils: lx.utils, version: \(String(reflecting: appVersion)), NoticeCenter: function() {}, stopRequests: function() {} }; ")
            _ = context.evaluateScript(script)
            if context.exception == nil {
                _ = context.evaluateScript("globalThis.__beansPlugin = module.exports;")
                initialized = context.exception == nil
            }
        }
        if !initialized { return nil }
    }

    func register(handler: JSValue, for event: String) {
        handlers[event] = handler
    }

    func receive(event: String, payload: Any?) {
        guard event == "inited" else { return }
        if let dict = payload as? [String: Any], let sources = dict["sources"] as? [String: Any] {
            BeansLogger.shared.log("第三方脚本初始化：\(sourceID) sources=\(sources.keys.sorted().joined(separator: ","))", level: .debug)
        }
    }

    func invokeRequest(payload: [String: Any], timeout: TimeInterval = 12) -> Any? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Any?
        let resultLock = NSLock()
        let done = BeansLXScriptDoneBridge()
        done.onResolve = { value in
            resultLock.lock()
            result = value
            resultLock.unlock()
            semaphore.signal()
        }
        done.onReject = { _ in
            semaphore.signal()
        }

        queue.async {
            let handler = self.handlers["request"]
            let hasPluginResolver = self.context.evaluateScript("typeof __beansPlugin.musicUrl === 'function'")?.toBool() == true
            guard handler != nil || hasPluginResolver else {
                semaphore.signal()
                return
            }
            if let handler {
                self.context.setObject(handler, forKeyedSubscript: "__beansHandler" as NSString)
            }
            self.context.setObject(payload as NSDictionary, forKeyedSubscript: "__beansPayload" as NSString)
            self.context.setObject(done, forKeyedSubscript: "__beansDone" as NSString)
            let invocation = handler != nil
                ? "__beansHandler(__beansPayload)"
                : "__beansPlugin.musicUrl(__beansPayload.source, __beansPayload.info.musicInfo, __beansPayload.info.type)"
            _ = self.context.evaluateScript("""
            (function() {
                try {
                    Promise.resolve(
                        \(invocation)
                    ).then(
                        function(value) { __beansDone.resolve(value); },
                        function(error) { __beansDone.reject(error && error.message ? error.message : String(error)); }
                    );
                } catch (error) {
                    __beansDone.reject(error && error.message ? error.message : String(error));
                }
            })();
            """)
            if self.context.exception != nil {
                semaphore.signal()
            }
        }

        let deadline = DispatchTime.now() + timeout
        _ = semaphore.wait(timeout: deadline)
        resultLock.lock()
        let finalResult = result
        resultLock.unlock()
        return finalResult
    }
}

final class LXScriptSourceRunner {
    static let shared = LXScriptSourceRunner()

    private let runtimeQueue = DispatchQueue(label: "Beans.LXScriptSourceRunner")
    private var cache: [String: BeansLXScriptRuntime] = [:]

    func resolve(
        source: ThirdPartySource,
        script: String,
        songSource: SongSource,
        songID: String,
        name: String,
        artists: String,
        quality: String,
        excludedHosts: Set<String>
    ) async -> UnblockService.Resolved? {
        await withCheckedContinuation { continuation in
            runtimeQueue.async {
                continuation.resume(returning: self.resolveSync(
                    source: source,
                    script: script,
                    songSource: songSource,
                    songID: songID,
                    name: name,
                    artists: artists,
                    quality: quality,
                    excludedHosts: excludedHosts
                ))
            }
        }
    }

    private func resolveSync(
        source: ThirdPartySource,
        script: String,
        songSource: SongSource,
        songID: String,
        name: String,
        artists: String,
        quality: String,
        excludedHosts: Set<String>
    ) -> UnblockService.Resolved? {
        let runtime = runtime(for: source, script: script)
        let payload: [String: Any] = [
            "action": "musicUrl",
            "source": providerCode(for: songSource),
            "info": [
                "type": quality,
                "musicInfo": musicInfoPayload(
                    songSource: songSource,
                    songID: songID,
                    name: name,
                    artists: artists
                )
            ]
        ]
        guard let raw = runtime?.invokeRequest(payload: payload) else { return nil }
        guard let urlString = extractURLString(from: raw),
              let url = URL(string: urlString),
              let playable = playableURL(url, excludedHosts: excludedHosts) else {
            return nil
        }
        return UnblockService.Resolved(
            url: playable,
            source: source.name,
            quality: ThirdPartyAudioQuality(sourceValue: quality) ?? .kb320
        )
    }

    private func runtime(for source: ThirdPartySource, script: String) -> BeansLXScriptRuntime? {
        let key = "\(source.id)|\(script.hashValue)"
        if let cached = cache[key] { return cached }
        guard let runtime = BeansLXScriptRuntime(source: source, script: script) else { return nil }
        cache[key] = runtime
        return runtime
    }

    private func musicInfoPayload(songSource: SongSource, songID: String, name: String, artists: String) -> [String: Any] {
        var payload: [String: Any] = [
            "id": songID,
            "songId": songID,
            "songmid": songID,
            "mediaMid": songID,
            "strMediaMid": songID,
            "hash": songID,
            "rid": songID,
            "name": name,
            "singer": artists,
            "artist": artists,
            "album": "",
            "albumName": "",
            "albumId": "",
            "albumAudioId": "",
            "interval": ""
        ]
        return payload
    }

    private func providerCode(for source: SongSource) -> String {
        switch source {
        case .netease: return "wy"
        case .qq: return "tx"
        case .kugou: return "kg"
        }
    }

    private func extractURLString(from raw: Any) -> String? {
        if let string = raw as? String, !string.isEmpty {
            return string
        }
        if let dict = raw as? [String: Any] {
            let paths = [
                "url",
                "play_url",
                "playUrl",
                "src",
                "audioUrl",
                "data.url",
                "data.play_url",
                "data.playUrl",
                "data.src",
                "data.audioUrl",
                "result.url",
                "result.play_url",
                "result.playUrl",
                "result.src"
            ]
            for path in paths {
                if let value = valueAtPath(dict, path) as? String, !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private func valueAtPath(_ obj: Any, _ path: String) -> Any? {
        var current: Any = obj
        for key in path.split(separator: ".") {
            guard let dict = current as? [String: Any], let next = dict[String(key)] else { return nil }
            current = next
        }
        return current
    }

    private func playableURL(_ url: URL, excludedHosts: Set<String>) -> URL? {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return url }
        if excludedHosts.contains(host) { return nil }
        if host.contains("qq.com") || host.contains("qqmusic") || host.contains("gitv.tv") {
            return url
        }
        return url
    }
}
