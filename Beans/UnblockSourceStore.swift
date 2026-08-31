import Foundation

/// 第三方解锁源配置。
/// kind：paid-lx、paid-cr、paid-qt 分别对应三种插件运行时格式。
/// template：请求 URL 模板，支持 {id}、{source}、{quality} 占位符。
/// headers：可选的请求头与内置元数据。
struct ThirdPartySource: Identifiable, Codable, Hashable, Sendable {
    var id = UUID().uuidString
    var name: String
    var kind: String = "keyword"
    var template: String
    var urlPath: String = "url"
    var headers: [String: String] = [:]
    var script: String? = nil
    var enabled: Bool = true
    var isPreset: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, kind, template, urlPath, headers, script, enabled, isPreset
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        kind: String = "keyword",
        template: String,
        urlPath: String = "url",
        headers: [String: String] = [:],
        script: String? = nil,
        enabled: Bool = true,
        isPreset: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.template = template
        self.urlPath = urlPath
        self.headers = headers
        self.script = script
        self.enabled = enabled
        self.isPreset = isPreset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名音源"
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "keyword"
        template = try container.decodeIfPresent(String.self, forKey: .template) ?? ""
        urlPath = try container.decodeIfPresent(String.self, forKey: .urlPath) ?? "url"
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        script = try container.decodeIfPresent(String.self, forKey: .script)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        isPreset = try container.decodeIfPresent(Bool.self, forKey: .isPreset) ?? false
    }
}

/// 第三方音源管理：保留内置预设接口，密钥只使用用户自己填写或导入的内容。
final class UnblockSourceStore: ObservableObject {
    static let shared = UnblockSourceStore()
    static let userAPIKeysKey = "beans.thirdPartyAPIKeys"

    private static let paidAPIURL = "https://source.shiqianjiang.cn/api/music"
    private static let paidURLTemplate = "\(paidAPIURL)/url?source={source}&songId={id}&quality={quality}"
    private static var paidHeaders: [String: String] {
        [
            "quality": "320k",
        ]
    }

    static let paidPresetSources: [ThirdPartySource] = [
        ThirdPartySource(
            id: "beans.preset.shiqianjiang.lx.v7",
            name: "聆澜音源 · LX",
            kind: "paid-lx",
            template: paidURLTemplate,
            headers: paidHeaders,
            isPreset: true
        ),
        ThirdPartySource(
            id: "beans.preset.shiqianjiang.cr.v7",
            name: "聆澜音源 · CR",
            kind: "paid-cr",
            template: paidURLTemplate,
            headers: paidHeaders,
            isPreset: true
        ),
        ThirdPartySource(
            id: "beans.preset.shiqianjiang.qt.v7",
            name: "聆澜音源 · QT",
            kind: "paid-qt",
            template: paidURLTemplate,
            headers: paidHeaders,
            isPreset: true
        ),
    ]

    @Published var sources: [ThirdPartySource] {
        didSet { save() }
    }

    private let defaults = UserDefaults.standard
    private let presetsKey = "beans.unblock.presets"
    private let legacyCustomKey = "beans.unblock.custom"
    private let legacyLXKey = "beans.unblock.lxScripts"

    private init() {
        let savedSources: [ThirdPartySource]
        if let data = defaults.data(forKey: presetsKey),
           let list = try? JSONDecoder().decode([ThirdPartySource].self, from: data) {
            savedSources = list
        } else if let data = defaults.data(forKey: legacyCustomKey),
                  let list = try? JSONDecoder().decode([ThirdPartySource].self, from: data) {
            savedSources = list
        } else {
            savedSources = []
        }

        // 保留预设和用户导入的 JSON 音源；旧版脚本仍不参与播放。
        let supportedPresetIDs = Set(Self.paidPresetSources.map(\.id))
        let existingPresets = savedSources.filter {
            $0.isPreset && supportedPresetIDs.contains($0.id)
        }
        let customSources = savedSources.filter { !$0.isPreset && Self.isValid($0) }
        sources = Self.seedPaidPresets(into: existingPresets) + customSources
        defaults.removeObject(forKey: legacyCustomKey)
        defaults.removeObject(forKey: legacyLXKey)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sources) {
            defaults.set(data, forKey: presetsKey)
        }
    }

    private static func seedPaidPresets(into savedSources: [ThirdPartySource]) -> [ThirdPartySource] {
        var seeded = savedSources
        for preset in paidPresetSources {
            if let index = seeded.firstIndex(where: { $0.id == preset.id }) {
                var updated = preset
                updated.enabled = seeded[index].enabled
                seeded[index] = updated
            } else {
                seeded.append(preset)
            }
        }
        return seeded
    }

    /// 导入一个或多个 JSON 音源配置。支持单个对象、数组，或 { "sources": [...] }。
    @discardableResult
    func importJSON(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        let imported: [ThirdPartySource]
        if let list = try? decoder.decode([ThirdPartySource].self, from: data) {
            imported = list
        } else if let wrapper = try? decoder.decode(SourceImportWrapper.self, from: data) {
            imported = wrapper.sources
        } else {
            imported = [try decoder.decode(ThirdPartySource.self, from: data)]
        }

        let valid = imported
            .filter { !$0.isPreset && Self.isValid($0) }
            .map { source -> ThirdPartySource in
                var normalized = source
                normalized.id = "custom.\(UUID().uuidString)"
                normalized.isPreset = false
                normalized.name = normalized.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return normalized
            }
        guard !valid.isEmpty else { throw SourceImportError.invalidConfiguration }

        var next = sources
        for item in valid {
            let fingerprint = "\(item.name)|\(item.template)|\(item.urlPath)"
            next.removeAll {
                !$0.isPreset && "\($0.name)|\($0.template)|\($0.urlPath)" == fingerprint
            }
            next.append(item)
        }
        sources = next
        return valid.count
    }

    @discardableResult
    func importJavaScript(_ data: Data, fileName: String) throws -> Int {
        guard let script = String(data: data, encoding: .utf8),
              !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SourceImportError.invalidConfiguration
        }
        let lowerName = fileName.lowercased()
        var inferredHeaders: [String: String] = [:]
        if lowerName.contains("qz2tx") || lowerName.contains("qq") || lowerName.contains("tencent") {
            inferredHeaders["source"] = "tx"
        } else if lowerName.contains("netease") || lowerName.contains("163") || lowerName.contains("wy") {
            inferredHeaders["source"] = "wy"
        } else if lowerName.contains("kugou") || lowerName.contains("kg") {
            inferredHeaders["source"] = "kg"
        }
        var source = ThirdPartySource(
            name: fileName.replacingOccurrences(of: ".js", with: ""),
            kind: "js-plugin",
            template: "https://local.beans.invalid/{id}",
            headers: inferredHeaders,
            script: script,
            isPreset: false
        )
        source.id = "custom.js.\(UUID().uuidString)"
        sources.append(source)
        return 1
    }

    func exportJSON() throws -> Data {
        let custom = sources.filter { !$0.isPreset }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(custom)
    }

    private static func isValid(_ source: ThirdPartySource) -> Bool {
        if source.kind == "js-plugin" {
            return !source.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !(source.script ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !source.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: source.template),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              !source.urlPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return source.template.contains("{id}")
            || source.template.contains("{name}")
            || source.template.contains("{keyword}")
    }

}

private struct SourceImportWrapper: Decodable {
    let sources: [ThirdPartySource]
}

enum SourceImportError: LocalizedError {
    case invalidConfiguration

    var errorDescription: String? {
        "没有找到有效的自定义音源配置"
    }
}
