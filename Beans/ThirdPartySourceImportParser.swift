import Foundation

enum ThirdPartySourceImportError: LocalizedError {
    case empty
    case unsupported
    case invalidURL
    case network(String)
    case noValidSource

    var errorDescription: String? {
        switch self {
        case .empty: return beansLocalized("内容为空", "Content is empty")
        case .unsupported: return beansLocalized("无法识别该音源格式", "Unsupported source format")
        case .invalidURL: return beansLocalized("链接无效", "Invalid URL")
        case .network(let message): return message
        case .noValidSource: return beansLocalized("没有可导入的音源", "No importable sources found")
        }
    }
}

enum ThirdPartySourceImportParser {
    static func parse(text: String, fallbackName: String? = nil) throws -> [ThirdPartySource] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ThirdPartySourceImportError.empty }

        if let jsonSources = parseJSON(trimmed, fallbackName: fallbackName), !jsonSources.isEmpty {
            return unique(jsonSources)
        }
        if let scriptSources = parseScript(trimmed, fallbackName: fallbackName), !scriptSources.isEmpty {
            return unique(scriptSources)
        }
        if let headerSources = parseHeaderStyle(trimmed, fallbackName: fallbackName), !headerSources.isEmpty {
            return unique(headerSources)
        }
        throw ThirdPartySourceImportError.unsupported
    }

    static func parse(fileURL: URL) throws -> [ThirdPartySource] {
        let data = try Data(contentsOf: fileURL)
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .unicode)
        guard let text else { throw ThirdPartySourceImportError.unsupported }
        let fallbackName = fileURL.deletingPathExtension().lastPathComponent
        return try parse(text: text, fallbackName: fallbackName)
    }

    static func fetch(url: URL) async throws -> [ThirdPartySource] {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ThirdPartySourceImportError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ThirdPartySourceImportError.network("HTTP \(http.statusCode)")
        }
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .unicode)
        guard let text else { throw ThirdPartySourceImportError.unsupported }
        let fallbackName = url.deletingPathExtension().lastPathComponent
        return try parse(text: text, fallbackName: fallbackName)
    }

    // MARK: - JSON

    private static func parseJSON(_ text: String, fallbackName: String?) -> [ThirdPartySource]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let array = object as? [Any] {
            let sources = array.compactMap { parseDictionary($0 as? [String: Any], fallbackName: fallbackName) }
            return sources.isEmpty ? nil : sources
        }
        if let dict = object as? [String: Any] {
            if let nested = dict["sources"] as? [Any] {
                let sources = nested.compactMap { parseDictionary($0 as? [String: Any], fallbackName: fallbackName) }
                if !sources.isEmpty { return sources }
            }
            if let nested = dict["items"] as? [Any] {
                let sources = nested.compactMap { parseDictionary($0 as? [String: Any], fallbackName: fallbackName) }
                if !sources.isEmpty { return sources }
            }
            if let source = parseDictionary(dict, fallbackName: fallbackName) {
                return [source]
            }
        }
        return nil
    }

    private static func parseDictionary(_ dict: [String: Any]?, fallbackName: String?) -> ThirdPartySource? {
        guard let dict else { return nil }
        let name = string(in: dict, keys: ["name", "title", "sourceName"])
            ?? fallbackName
            ?? beansLocalized("未命名音源", "Untitled source")
        let kind = string(in: dict, keys: ["kind", "type"]) ?? "keyword"
        let urlPath = string(in: dict, keys: ["urlPath", "path"]) ?? "url"
        let template = templateString(from: dict)
        guard !template.isEmpty else { return nil }

        var headers = dictionary(in: dict, key: "headers")
        for key in ["source", "quality", "br", "apiKey", "apiKeys", "signSalt", "fingerprint", "cookie", "tx_cookie", "wy_cookie"] {
            if let value = string(in: dict, keys: [key]), !value.isEmpty {
                headers[key] = value
            }
        }

        if headers["source"] == nil, let platform = platformCode(from: dict) {
            headers["source"] = platform
        }

        let enabled = bool(in: dict, keys: ["enabled"], defaultValue: true)
        let isPreset = bool(in: dict, keys: ["isPreset"], defaultValue: false)
        return ThirdPartySource(
            name: name,
            kind: kind,
            template: template,
            urlPath: urlPath,
            headers: headers,
            enabled: enabled,
            isPreset: isPreset
        )
    }

    private static func templateString(from dict: [String: Any]) -> String {
        if let template = string(in: dict, keys: ["template"]), !template.isEmpty {
            return template
        }
        if let url = string(in: dict, keys: ["apiUrl", "baseURL", "baseUrl", "url", "endpoint"]), !url.isEmpty {
            if dict["apiKey"] != nil || dict["signSalt"] != nil || dict["fingerprint"] != nil {
                return url.hasSuffix("/url?source={source}&songId={id}&quality={quality}")
                    ? url
                    : url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        + "/url?source={source}&songId={id}&quality={quality}"
            }
            return url
        }
        return ""
    }

    // MARK: - Script / header blocks

    private static func parseScript(_ text: String, fallbackName: String?) -> [ThirdPartySource]? {
        let patterns = [
            #"SERVER_SCRIPT_CONFIG\s*=\s*(\{[\s\S]*?\})"#,
            #"globalThis\[['"]SERVER_SCRIPT_CONFIG['"]\]\s*=\s*(\{[\s\S]*?\})"#,
            #"module\.exports\s*=\s*(\{[\s\S]*?\})"#,
            #"export\s+default\s*(\{[\s\S]*?\})"#
        ]
        for pattern in patterns {
            if let json = extractFirstJSONObject(from: text, pattern: pattern),
               let data = json.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let source = parseDictionary(object, fallbackName: fallbackName) {
                return [source]
            }
        }
        return nil
    }

    private static func parseHeaderStyle(_ text: String, fallbackName: String?) -> [ThirdPartySource]? {
        guard let block = extractCommentBlock(text) else { return nil }
        var values: [String: String] = [:]
        for line in block.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleaned = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "* "))
            guard cleaned.hasPrefix("@") else { continue }
            let content = cleaned.dropFirst()
            let pieces = content.split(maxSplits: 1, omittingEmptySubsequences: false) { $0 == " " || $0 == "\t" || $0 == "=" }
            guard let keyPart = pieces.first else { continue }
            let valuePart = pieces.count > 1 ? String(pieces[1]).trimmingCharacters(in: .whitespaces) : ""
            values[String(keyPart).lowercased()] = valuePart
        }

        guard !values.isEmpty else { return nil }
        let name = values["name"]?.isEmpty == false ? values["name"]! : (fallbackName ?? beansLocalized("未命名音源", "Untitled source"))
        let kind = values["kind"].flatMap { $0.isEmpty ? nil : $0 } ?? "keyword"
        let template = values["template"].flatMap { $0.isEmpty ? nil : $0 }
            ?? values["apiurl"].flatMap { $0.isEmpty ? nil : $0 }
            ?? values["url"].flatMap { $0.isEmpty ? nil : $0 }
            ?? ""
        guard !template.isEmpty else { return nil }
        let urlPath = values["urlpath"].flatMap { $0.isEmpty ? nil : $0 } ?? "url"
        var headers: [String: String] = [:]
        if let headersValue = values["headers"], !headersValue.isEmpty {
            if let data = headersValue.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                headers = obj.compactMapValues { $0 as? String }
            } else {
                for pair in headersValue.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" }) {
                    let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    if parts.count == 2 {
                        headers[String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)] =
                            String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }
        for (key, value) in values where key != "name" && key != "kind" && key != "template" && key != "urlpath" && key != "headers" {
            if !value.isEmpty { headers[key] = value }
        }
        if headers["source"] == nil, let platform = values["source"], !platform.isEmpty {
            headers["source"] = platform
        }
        let enabled = boolString(values["enabled"], defaultValue: true)
        let isPreset = boolString(values["ispreset"], defaultValue: false)
        return [ThirdPartySource(
            name: name,
            kind: kind,
            template: template,
            urlPath: urlPath,
            headers: headers,
            enabled: enabled,
            isPreset: isPreset
        )]
    }

    private static func extractCommentBlock(_ text: String) -> String? {
        if let start = text.range(of: "/*!"),
           let end = text.range(of: "*/", range: start.upperBound..<text.endIndex) {
            return String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = text.range(of: "/*"),
           let end = text.range(of: "*/", range: start.upperBound..<text.endIndex) {
            return String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func extractFirstJSONObject(from text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    // MARK: - Helpers

    private static func unique(_ sources: [ThirdPartySource]) -> [ThirdPartySource] {
        var seen = Set<String>()
        return sources.filter { source in
            let fingerprint = "\(source.name)|\(source.kind)|\(source.template)|\(source.urlPath)|\(source.headers.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&"))"
            return seen.insert(fingerprint).inserted
        }
    }

    private static func string(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let value = dict[key] as? NSNumber {
                return value.stringValue
            }
        }
        return nil
    }

    private static func dictionary(in dict: [String: Any], key: String) -> [String: String] {
        guard let raw = dict[key] else { return [:] }
        if let stringDict = raw as? [String: String] { return stringDict }
        if let obj = raw as? [String: Any] {
            return obj.compactMapValues { $0 as? String }
        }
        return [:]
    }

    private static func bool(in dict: [String: Any], keys: [String], defaultValue: Bool) -> Bool {
        for key in keys {
            if let value = dict[key] as? Bool { return value }
            if let value = dict[key] as? NSNumber { return value.boolValue }
            if let value = dict[key] as? String { return boolString(value, defaultValue: defaultValue) }
        }
        return defaultValue
    }

    private static func boolString(_ value: String?, defaultValue: Bool) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !value.isEmpty else {
            return defaultValue
        }
        switch value {
        case "1", "true", "yes", "on", "enabled": return true
        case "0", "false", "no", "off", "disabled": return false
        default: return defaultValue
        }
    }

    private static func platformCode(from dict: [String: Any]) -> String? {
        let platform = string(in: dict, keys: ["source", "platform", "provider", "musicSource"])?.lowercased()
        switch platform {
        case "netease", "wy", "neteasecloudmusic", "cloud": return "wy"
        case "qq", "tx", "qqmusic": return "tx"
        case "kugou", "kg": return "kg"
        default: return nil
        }
    }
}
