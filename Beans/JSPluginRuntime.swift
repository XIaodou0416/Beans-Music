import Foundation
import JavaScriptCore

/// 受限的 JavaScript 音源运行时。
///
/// 插件必须导出：
/// module.exports = {
///   getMediaSource: function(song, quality, apiKey) {
///     return { url: "https://example.com/" + song.id };
///   }
/// }
///
/// 运行时只读取播放地址，不向脚本暴露 UserDefaults、文件系统或 Swift 对象。
enum JSPluginRuntime {
    private final class JSResultBox {
        var value: JSValue?
    }

    static func resolve(
        script: String,
        id: String,
        name: String,
        artists: String,
        source: String,
        quality: String,
        apiKey: String?
    ) async -> URL? {
        await Task.detached(priority: .userInitiated) {
            resolveSync(
                script: script,
                id: id,
                name: name,
                artists: artists,
                source: source,
                quality: quality,
                apiKey: apiKey
            )
        }.value
    }

    private static func resolveSync(
        script: String,
        id: String,
        name: String,
        artists: String,
        source: String,
        quality: String,
        apiKey: String?
    ) -> URL? {
        let context = JSContext()
        var exceptionText = ""
        context?.exceptionHandler = { _, exception in
            exceptionText = exception?.toString() ?? "unknown JavaScript error"
        }
        guard let context else { return nil }

        let httpBridge: @convention(block) (String, String, String, String) -> String = { method, url, body, headersJSON in
            nativeHTTP(method: method, url: url, body: body, headersJSON: headersJSON)
        }
        context.setObject(httpBridge, forKeyedSubscript: "__beansHTTP" as NSString)

        // 提供 LX/Baka 插件最常用的 axios 兼容层。网络请求仍由 Swift 发起，
        // JS 只能得到 HTTP 响应，无法访问应用沙盒或账号存储。
        context.evaluateScript("""
        var UPDATE_URL = "";
        var __beansAxiosRequest = function(method, url, config, data) {
          config = config || {};
          var headers = config.headers || {};
          var body = data === undefined || data === null ? "" :
            (typeof data === "string" ? data : JSON.stringify(data));
          var response = JSON.parse(__beansHTTP(method, String(url), body, JSON.stringify(headers)));
          var value = response.body;
          try { value = JSON.parse(value); } catch (_) {}
          return { data: value, status: response.status, headers: {} };
        };
        var axios = function(config) {
          config = config || {};
          return __beansAxiosRequest(
            String(config.method || "GET").toUpperCase(),
            config.url || "",
            config,
            config.data
          );
        };
        axios.get = function(url, config) {
          return __beansAxiosRequest("GET", url, config, null);
        };
        axios.post = function(url, data, config) {
          return __beansAxiosRequest("POST", url, config, data);
        };
        var axios_1 = { default: axios };
        function require(name) {
          if (name === "axios") return axios_1;
          if (name === "he") return { decode: function(value) { return value; } };
          if (name === "buffer") return { Buffer: { from: function(value) { return value; } } };
          if (name === "crypto-js") return {};
          return {};
        }
        """)

        let module = JSValue(newObjectIn: context)
        let exports = JSValue(newObjectIn: context)
        module?.setValue(exports, forProperty: "exports")
        context.setObject(module, forKeyedSubscript: "module" as NSString)
        context.setObject(exports, forKeyedSubscript: "exports" as NSString)

        let wrapped = """
        (function(module, exports) {
        \(script)
        })(module, exports);
        """
        context.evaluateScript(wrapped)
        guard exceptionText.isEmpty else {
            BeansLogger.shared.log("JS 音源执行失败：\(exceptionText)", level: .debug)
            return nil
        }

        guard let plugin = module?.forProperty("exports"),
              let function = plugin.forProperty("getMediaSource"),
              !function.isUndefined else {
            BeansLogger.shared.log("JS 音源缺少 getMediaSource：\(name)", level: .debug)
            return nil
        }

        let song: [String: Any] = [
            "id": id,
            "name": name,
            "title": name,
            "artist": artists,
            "artists": artists,
            "source": source,
            "songmid": id,
            "media_mid": id,
            "apiKey": apiKey ?? "",
        ]
        guard let songValue = JSValue(object: song, in: context) else { return nil }
        let result = function.call(withArguments: [songValue, quality])
        guard exceptionText.isEmpty, let result else {
            BeansLogger.shared.log("JS 音源调用失败：\(name)", level: .debug)
            return nil
        }

        // 兼容同步返回和 async Promise 返回。
        let resultBox = JSResultBox()
        resultBox.value = result
        if result.isObject && result.forProperty("then")?.isUndefined == false {
            let semaphore = DispatchSemaphore(value: 0)
            let completion: @convention(block) (JSValue) -> Void = { value in
                resultBox.value = value
                semaphore.signal()
            }
            result.invokeMethod("then", withArguments: [completion])
            _ = semaphore.wait(timeout: .now() + 10)
        }

        // 兼容直接返回对象、{ url } 和直接返回字符串三种格式。
        let rawURL = resultBox.value?.isString == true
            ? resultBox.value?.toString()
            : resultBox.value?.forProperty("url")?.toString()
        guard let rawURL, let url = URL(string: rawURL),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            BeansLogger.shared.log("JS 音源未返回有效播放地址：\(name)", level: .debug)
            return nil
        }
        return url
    }

    private static func nativeHTTP(method: String, url: String, body: String, headersJSON: String) -> String {
        guard let requestURL = URL(string: url) else {
            return #"{"status":400,"body":""}"#
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.timeoutInterval = 10
        if let data = body.data(using: .utf8), !body.isEmpty {
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let data = headersJSON.data(using: .utf8),
           let headers = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        let semaphore = DispatchSemaphore(value: 0)
        var responseData = Data()
        var status = 0
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            responseData = data ?? Data()
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 10)
        let responseBody = String(data: responseData, encoding: .utf8) ?? ""
        let encoded = responseBody.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return #"{"status":"# + String(status) + #","body":""# + encoded + #""}"#
    }
}
