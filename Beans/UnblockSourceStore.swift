import Foundation

/// 第三方解锁源配置。请求密钥由用户自己填写并保存在本机。
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
    var enabled: Bool = true
    var isPreset: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, kind, template, urlPath, headers, enabled, isPreset
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        kind: String = "keyword",
        template: String,
        urlPath: String = "url",
        headers: [String: String] = [:],
        enabled: Bool = true,
        isPreset: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.template = template
        self.urlPath = urlPath
        self.headers = headers
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
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        isPreset = try container.decodeIfPresent(Bool.self, forKey: .isPreset) ?? false
    }
}

/// 第三方音源管理：不内置任何密钥，用户输入自己的密钥后才会发起请求。
final class UnblockSourceStore: ObservableObject {
    static let shared = UnblockSourceStore()
    static let userAPIKeysKey = "beans.thirdPartyAPIKeys"
    static let defaultSource = ThirdPartySource(
        id: "beans.user.shiqianjiang",
        name: "第三方音源",
        kind: "paid",
        template: "https://source.shiqianjiang.cn/api/music/url?source={source}&songId={id}&quality={quality}",
        headers: ["quality": "320k"],
        isPreset: true
    )

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

        // 清理旧版本内置脚本、内置密钥和用户导入脚本，统一使用无密钥的请求配置。
        let enabled = savedSources.first(where: { $0.isPreset })?.enabled ?? true
        var source = Self.defaultSource
        source.enabled = enabled
        sources = [source]
        defaults.removeObject(forKey: "beans.unblock.preferredKeyIndex.beans.preset.shiqianjiang.lx.v7")
        defaults.removeObject(forKey: "beans.unblock.preferredKeyIndex.beans.preset.shiqianjiang.cr.v7")
        defaults.removeObject(forKey: "beans.unblock.preferredKeyIndex.beans.preset.shiqianjiang.qt.v7")
        defaults.removeObject(forKey: legacyCustomKey)
        defaults.removeObject(forKey: legacyLXKey)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sources) {
            defaults.set(data, forKey: presetsKey)
        }
    }

}
