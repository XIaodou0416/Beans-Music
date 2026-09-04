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
    func aesEncrypt(_ data: String, _ mode: String, _ key: String, _ iv: String) -> NSDictionary
}

@objc protocol BeansLXScriptBridgeExports: JSExport {
    func request(_ url: String, _ options: JSValue?, _ callback: JSValue?)
    func on(_ event: String, _ handler: JSValue)
    func send(_ event: String, _ payload: JSValue?)
    var EVENT_NAMES: NSDictionary { get }
    var env: NSDictionary { get }
    var utils: BeansLXScriptUtilsBridge { get }
    var version: String { get }
    var currentScriptInfo: NSDictionary { get }
}

@objc protocol BeansLXScriptDoneExports: JSExport {
    func resolve(_ value: JSValue?)
    func reject(_ value: JSValue?)
}

final class BeansLXScriptBufferBridge: NSObject, BeansLXScriptBufferExports {
    func from(_ text: String, _ encoding: String) -> NSDictionary {
        Self.dictionary(for: data(from: text, encoding: encoding))
    }

    func bufToString(_ buffer: JSValue?, _ encoding: String) -> String {
        guard let data = data(from: buffer) else {
            return buffer?.toString() ?? ""
        }
        switch encoding.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "base64":
            return data.base64EncodedString()
        case "hex":
            return data.map { String(format: "%02x", $0) }.joined()
        case "utf-8", "utf8":
            return String(data: data, encoding: .utf8) ?? ""
        default:
            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    static func dictionary(for data: Data) -> NSDictionary {
        [
            "__beansBuffer": true,
            "base64": data.base64EncodedString(),
            "hex": data.map { String(format: "%02x", $0) }.joined(),
            "text": String(data: data, encoding: .utf8) ?? ""
        ]
    }

    private func data(from text: String, encoding: String) -> Data {
        switch encoding.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "base64":
            return Data(base64Encoded: text, options: [.ignoreUnknownCharacters]) ?? Data()
        case "hex":
            var value = text
                .replacingOccurrences(of: "0x", with: "")
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
            if !value.count.isMultiple(of: 2) {
                value = "0" + value
            }
            var result = Data()
            var index = value.startIndex
            while index < value.endIndex {
                let next = value.index(index, offsetBy: 2)
                if let byte = UInt8(value[index..<next], radix: 16) {
                    result.append(byte)
                }
                index = next
            }
            return result
        default:
            return Data(text.utf8)
        }
    }

    private func data(from buffer: JSValue?) -> Data? {
        guard let object = buffer?.toObject() else { return nil }
        let dictionary: [String: Any]
        if let value = object as? [String: Any] {
            dictionary = value
        } else if let value = object as? NSDictionary {
            dictionary = value.reduce(into: [String: Any]()) { result, pair in
                if let key = pair.key as? String {
                    result[key] = pair.value
                }
            }
        } else if let text = object as? String {
            return Data(text.utf8)
        } else {
            return nil
        }

        if let base64 = dictionary["base64"] as? String,
           let data = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters]) {
            return data
        }
        if let hex = dictionary["hex"] as? String {
            return data(from: hex, encoding: "hex")
        }
        if let text = dictionary["text"] as? String {
            return Data(text.utf8)
        }
        return nil
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

    func aesEncrypt(_ data: String, _ mode: String, _ key: String, _ iv: String) -> NSDictionary {
        let input = Data(data.utf8)
        let keyData = normalize(Data(key.utf8))
        let ivData = normalize(Data(iv.utf8))
        let usesECB = mode.lowercased().contains("ecb")
        let options = usesECB
            ? CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode)
            : CCOptions(kCCOptionPKCS7Padding)

        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var outputLength: size_t = 0
        let status = keyData.withUnsafeBytes { keyBytes in
            ivData.withUnsafeBytes { ivBytes in
                input.withUnsafeBytes { inputBytes in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        options,
                        keyBytes.baseAddress,
                        keyData.count,
                        usesECB ? nil : ivBytes.baseAddress,
                        inputBytes.baseAddress,
                        input.count,
                        &output,
                        output.count,
                        &outputLength
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            return BeansLXScriptBufferBridge.dictionary(for: Data())
        }
        return BeansLXScriptBufferBridge.dictionary(for: Data(output.prefix(outputLength)))
    }

    private func normalize(_ data: Data) -> Data {
        if data.count == kCCKeySizeAES128 {
            return data
        }
        if data.count > kCCKeySizeAES128 {
            return data.prefix(kCCKeySizeAES128)
        }
        return data + Data(repeating: 0, count: kCCKeySizeAES128 - data.count)
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
        "device": "iPhone",
        "isMobile": true
    ]

    let utils = BeansLXScriptUtilsBridge()
    let version: String
    let currentScriptInfo: NSDictionary

    init(runtimeQueue: DispatchQueue, source: ThirdPartySource, script: String) {
        self.runtimeQueue = runtimeQueue
        self.version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.6.4"
        self.currentScriptInfo = [
            "name": source.name,
            "version": source.headers["version"] ?? "",
            "rawScript": script
        ]
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    func request(_ url: String, _ options: JSValue?, _ callback: JSValue?) {
        guard let callback else { return }
        let requestOptions = dictionary(from: options?.toObject())
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

        let headers = dictionary(from: requestOptions["headers"])
        if !headers.isEmpty {
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
            } else if let dict = dictionary(from: body),
                      dict["__beansBuffer"] as? Bool == true,
                      let base64 = dict["base64"] as? String {
                request.httpBody = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters])
            } else if let dict = dictionary(from: body),
                      JSONSerialization.isValidJSONObject(dict),
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
                let parsed = self.parseBody(data)
                let responseType = requestOptions["responseType"] as? String
                let body: Any = responseType?.lowercased() == "text" ? parsed.text : parsed.value
                let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                    result[String(describing: pair.key)] = String(describing: pair.value)
                }
                let responseObject: [String: Any] = [
                    "statusCode": http.statusCode,
                    "headers": headers,
                    "body": body,
                    "bodyText": parsed.text,
                    "ok": (200..<300).contains(http.statusCode)
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

    private func parseBody(_ data: Data?) -> (value: Any, text: String) {
        guard let data else { return (NSNull(), "") }
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? data.base64EncodedString()
        if let json = try? JSONSerialization.jsonObject(with: data) {
            return (json, text)
        }
        return (text, text)
    }

    private func dictionary(from raw: Any?) -> [String: Any] {
        if let value = raw as? [String: Any] {
            return value
        }
        if let value = raw as? NSDictionary {
            return value.reduce(into: [String: Any]()) { result, pair in
                if let key = pair.key as? String {
                    result[key] = pair.value
                }
            }
        }
        return [:]
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
        self.bridge = BeansLXScriptBridge(runtimeQueue: queue, source: source, script: script)
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
            context.evaluateScript("if (typeof global === 'undefined') { globalThis.global = globalThis; }")
            context.evaluateScript("if (typeof self === 'undefined') { globalThis.self = globalThis; }")
            context.evaluateScript("if (typeof globalThis.lx === 'undefined') { globalThis.lx = lx; }")
            context.evaluateScript("if (typeof console === 'undefined') { globalThis.console = { log: function() {}, info: function() {}, debug: function() {}, warn: function() {}, error: function() {} }; }")
            context.evaluateScript("if (typeof module === 'undefined') { var module = { exports: {} }; var exports = module.exports; }")
            context.evaluateScript("""
            (function() {
                var nativeLX = globalThis.lx || lx;
                var beansEnv = {
                    platform: nativeLX.env && nativeLX.env.platform ? nativeLX.env.platform : 'ios',
                    os: nativeLX.env && nativeLX.env.os ? nativeLX.env.os : 'iOS',
                    device: nativeLX.env && nativeLX.env.device ? nativeLX.env.device : 'iPhone',
                    isMobile: true
                };
                beansEnv.toString = function() {
                    return String(this.platform || 'ios');
                };
                globalThis.lx = {
                    EVENT_NAMES: nativeLX.EVENT_NAMES,
                    env: beansEnv,
                    utils: nativeLX.utils,
                    version: nativeLX.version,
                    currentScriptInfo: nativeLX.currentScriptInfo,
                    on: function(event, handler) {
                        return nativeLX.on(event, handler);
                    },
                    send: function(event, payload) {
                        return nativeLX.send(event, payload);
                    },
                    request: function(url, options, callback) {
                        if (typeof options === 'function') {
                            callback = options;
                            options = {};
                        }
                        if (typeof callback === 'function') {
                            return nativeLX.request(url, options || {}, callback);
                        }
                        return new Promise(function(resolve, reject) {
                            nativeLX.request(url, options || {}, function(error, response) {
                                if (error && error.message) reject(error);
                                else resolve(response);
                            });
                        });
                    }
                };
                if (typeof globalThis.fetch !== 'function') {
                    globalThis.fetch = function(url, options) {
                        return globalThis.lx.request(url, options || {}).then(function(response) {
                            return {
                                ok: response.ok,
                                status: response.statusCode,
                                statusCode: response.statusCode,
                                headers: response.headers,
                                text: function() {
                                    return Promise.resolve(response.bodyText || String(response.body || ''));
                                },
                                json: function() {
                                    return Promise.resolve(
                                        typeof response.body === 'string'
                                            ? JSON.parse(response.body)
                                            : response.body
                                    );
                                }
                            };
                        });
                    };
                }
                if (typeof globalThis.customFetch !== 'function') {
                    globalThis.customFetch = function(url, options) {
                        return globalThis.lx.request(url, options || {}).then(function(response) {
                            if (response && typeof response.bodyText === 'string') {
                                return response.bodyText;
                            }
                            if (response && typeof response.body === 'string') {
                                return response.body;
                            }
                            return JSON.stringify(response && response.body ? response.body : {});
                        });
                    };
                }
                if (typeof globalThis.Buffer === 'undefined') {
                    var makeBeansBuffer = function(value, encoding) {
                        if (value && value.__beansBuffer) {
                            return value;
                        }
                        var text = value === null || typeof value === 'undefined'
                            ? ''
                            : String(value);
                        var buffer = nativeLX.utils.buffer.from(text, encoding || 'utf8');
                        buffer.toString = function(outputEncoding) {
                            return nativeLX.utils.buffer.bufToString(buffer, outputEncoding || 'utf8');
                        };
                        return buffer;
                    };
                    globalThis.Buffer = {
                        from: makeBeansBuffer,
                        isBuffer: function(value) {
                            return !!(value && value.__beansBuffer);
                        }
                    };
                }
                if (typeof Promise.any !== 'function') {
                    Promise.any = function(iterable) {
                        return new Promise(function(resolve, reject) {
                            var values = Array.prototype.slice.call(iterable || []);
                            if (!values.length) {
                                reject(new Error('All promises were rejected'));
                                return;
                            }
                            var pending = values.length;
                            var errors = [];
                            values.forEach(function(value, index) {
                                Promise.resolve(value).then(resolve, function(error) {
                                    errors[index] = error;
                                    pending -= 1;
                                    if (pending === 0) {
                                        reject(new Error('All promises were rejected'));
                                    }
                                });
                            });
                        });
                    };
                }
                if (!JSON.__beansOriginalParse) {
                    JSON.__beansOriginalParse = JSON.parse;
                    JSON.parse = function(value) {
                        return value !== null && typeof value === 'object'
                            ? value
                            : JSON.__beansOriginalParse(value);
                    };
                }
            })();
            """)
            context.evaluateScript("globalThis.cerumusic = { request: function(url, options, callback) { return globalThis.lx.request(url, options, callback); }, utils: globalThis.lx.utils, env: globalThis.lx.env, version: globalThis.lx.version, currentScriptInfo: globalThis.lx.currentScriptInfo, NoticeCenter: function() {}, stopRequests: function() {} }; ")
            _ = context.evaluateScript(script)
            if context.exception == nil {
                _ = context.evaluateScript("globalThis.__beansPlugin = module.exports;")
                _ = context.evaluateScript("globalThis.__beansMusicPlugin = globalThis.MusicPlugin || {};")
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
        } else if let dict = payload as? NSDictionary,
                  let sources = dict["sources"] as? NSDictionary {
            let names = sources.allKeys.compactMap { $0 as? String }.sorted().joined(separator: ",")
            BeansLogger.shared.log("第三方脚本初始化：\(sourceID) sources=\(names)", level: .debug)
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
            let resolverKind = self.context.evaluateScript("""
            (function() {
                if (typeof __beansPlugin !== 'undefined' && typeof __beansPlugin.musicUrl === 'function') {
                    return 'musicUrl';
                }
                if (typeof __beansMusicPlugin !== 'undefined' && typeof __beansMusicPlugin.getMusicUrl === 'function') {
                    return 'musicPluginGetMusicUrl';
                }
                if (typeof __beansPlugin !== 'undefined' && typeof __beansPlugin.getMusicUrl === 'function') {
                    return 'pluginGetMusicUrl';
                }
                return '';
            })()
            """)?.toString() ?? ""
            guard handler != nil || !resolverKind.isEmpty else {
                BeansLogger.shared.log("第三方脚本没有可用的音乐地址解析入口：\(self.sourceID)", level: .debug)
                semaphore.signal()
                return
            }
            if let handler {
                self.context.setObject(handler, forKeyedSubscript: "__beansHandler" as NSString)
            }
            self.context.setObject(payload as NSDictionary, forKeyedSubscript: "__beansPayload" as NSString)
            self.context.setObject(done, forKeyedSubscript: "__beansDone" as NSString)
            let invocation: String
            if handler != nil {
                invocation = "__beansHandler(__beansPayload)"
            } else {
                switch resolverKind {
                case "musicPluginGetMusicUrl":
                    invocation = "__beansMusicPlugin.getMusicUrl(__beansPayload.source, __beansPayload.info.musicInfo.musicId || __beansPayload.info.musicInfo.songmid || __beansPayload.info.musicInfo.id, __beansPayload.info.type)"
                case "pluginGetMusicUrl":
                    invocation = "__beansPlugin.getMusicUrl(__beansPayload.source, __beansPayload.info.musicInfo.musicId || __beansPayload.info.musicInfo.songmid || __beansPayload.info.musicInfo.id, __beansPayload.info.type)"
                default:
                    invocation = "__beansPlugin.musicUrl(__beansPayload.source, __beansPayload.info.musicInfo, __beansPayload.info.type)"
                }
            }
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
                BeansLogger.shared.log("第三方脚本调用异常：\(self.sourceID)", level: .debug)
                semaphore.signal()
            }
        }

        let deadline = DispatchTime.now() + timeout
        if semaphore.wait(timeout: deadline) == .timedOut {
            BeansLogger.shared.log("第三方脚本调用超时：\(sourceID) \(Int(timeout))s", level: .debug)
        }
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
        qqMid: String? = nil,
        qqMediaMid: String? = nil,
        kugouID: String? = nil,
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
                    qqMid: qqMid,
                    qqMediaMid: qqMediaMid,
                    kugouID: kugouID,
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
        qqMid: String?,
        qqMediaMid: String?,
        kugouID: String?,
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
                    qqMid: qqMid,
                    qqMediaMid: qqMediaMid,
                    kugouID: kugouID,
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

    private func musicInfoPayload(
        songSource: SongSource,
        songID: String,
        qqMid: String?,
        qqMediaMid: String?,
        kugouID: String?,
        name: String,
        artists: String
    ) -> [String: Any] {
        let qqSongMid = qqMid?.trimmingCharacters(in: .whitespacesAndNewlines)
        let qqSongMediaMid = qqMediaMid?.trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryID = (songSource == .qq ? qqSongMid : nil) ?? songID
        let resolvedHash = (songSource == .kugou ? kugouID : nil) ?? songID
        let artistList = artists
            .split(whereSeparator: { $0 == "/" || $0 == "&" || $0 == "," })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var payload: [String: Any] = [
            "id": songID,
            "songId": songID,
            "musicId": primaryID,
            "musicrid": songID,
            "mid": qqSongMid ?? primaryID,
            "songmid": qqSongMid ?? primaryID,
            "mediaId": qqSongMediaMid ?? primaryID,
            "media_mid": qqSongMediaMid ?? primaryID,
            "mediaMid": qqSongMediaMid ?? primaryID,
            "strMediaMid": qqSongMediaMid ?? primaryID,
            "copyrightId": songID,
            "contentId": songID,
            "hash": resolvedHash,
            "rid": songID,
            "name": name,
            "songName": name,
            "singer": artists,
            "artist": artists,
            "artists": artistList,
            "source": providerCode(for: songSource),
            "album": "",
            "albumName": "",
            "albumId": "",
            "albumAudioId": "",
            "interval": "",
            "_types": [String: Any](),
            "meta": [String: Any]()
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
        if let string = raw as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                return trimmed
            }
            if trimmed.hasPrefix("//") {
                return "https:" + trimmed
            }
            if (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")),
               let data = trimmed.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) {
                return extractURLString(from: object)
            }
            return nil
        }
        if let array = raw as? [Any] {
            for item in array {
                if let url = extractURLString(from: item) {
                    return url
                }
            }
            return nil
        }
        if let nsArray = raw as? NSArray {
            for item in nsArray {
                if let url = extractURLString(from: item) {
                    return url
                }
            }
            return nil
        }
        if let dict = raw as? [String: Any] {
            let paths = [
                "musicUrl",
                "musicurl",
                "music",
                "url",
                "play_url",
                "playUrl",
                "src",
                "audioUrl",
                "audio_url",
                "link",
                "purl",
                "data.url",
                "data.musicUrl",
                "data.musicurl",
                "data.music",
                "data.play_url",
                "data.playUrl",
                "data.src",
                "data.audioUrl",
                "data.audio_url",
                "data.link",
                "result.url",
                "result.musicUrl",
                "result.musicurl",
                "result.music",
                "result.play_url",
                "result.playUrl",
                "result.src",
                "result.audioUrl",
                "result.link"
            ]
            for path in paths {
                if let value = valueAtPath(dict, path),
                   let url = extractURLString(from: value) {
                    return url
                }
            }
            // Some sources return a wrapper with a provider-specific key.
            // Recurse only through likely payload containers to avoid picking a cover URL.
            for key in ["data", "result", "response", "body", "payload", "musicInfo"] {
                if let value = dict[key],
                   let url = extractURLString(from: value) {
                    return url
                }
            }
        }
        if let nsDict = raw as? NSDictionary {
            let dict = nsDict.reduce(into: [String: Any]()) { result, pair in
                if let key = pair.key as? String {
                    result[key] = pair.value
                }
            }
            return extractURLString(from: dict)
        }
        return nil
    }

    private func valueAtPath(_ obj: Any, _ path: String) -> Any? {
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

    private func playableURL(_ url: URL, excludedHosts: Set<String>) -> URL? {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return url }
        if excludedHosts.contains(host) { return nil }
        if host.contains("qq.com") || host.contains("qqmusic") || host.contains("gitv.tv") {
            return url
        }
        return url
    }
}
