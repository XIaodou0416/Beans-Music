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

/// 第三方音源管理：保留内置预设，也兼容用户额外填写自己的密钥。
final class UnblockSourceStore: ObservableObject {
    static let shared = UnblockSourceStore()
    static let userAPIKeysKey = "beans.thirdPartyAPIKeys"

    private static let paidAPIURL = "https://source.shiqianjiang.cn/api/music"
    private static let paidAPIKeys = [
        "CERU_KEY-51440644-C9AD-4E10-B593-258FF59CF259",
        "CERU_KEY-1C0F7359-2863-46F7-A63C-B0E0E744CDFE",
        "CERU_KEY-B2495961-F872-4F31-9893-F6E8F15B5D62",
        "CERU_KEY-51A42014-7122-4D7A-9964-51DEE617FDB5",
        "CERU_KEY-DCF912D8-1AF2-43E0-B5BE-1AE9ACB628CA",
        "CERU_KEY-1AAA372F-0436-442B-A893-29F429F23A99",
        "CERU_KEY-27801580-D346-4ECC-8279-4A6E3DCE2A04",
        "CERU_KEY-6A7A61FC-69E3-4DA6-8BE7-4CC30C276155",
        "CERU_KEY-29C420FF-991A-4CDF-8AD7-80052193CC03",
        "CERU_KEY-E0BF635D-2866-4C35-A053-938636729CF3",
        "CERU_KEY-AFC06E87-AD81-49BD-9B70-738346B31DF9",
    ]
    private static let paidURLTemplate = "\(paidAPIURL)/url?source={source}&songId={id}&quality={quality}"
    private static var paidHeaders: [String: String] {
        [
            "apiKeys": paidAPIKeys.joined(separator: ","),
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

        // 只保留当前支持的预设，旧版导入脚本不再参与播放，避免重复请求。
        let supportedPresetIDs = Set(Self.paidPresetSources.map(\.id))
        let existingPresets = savedSources.filter {
            $0.isPreset && supportedPresetIDs.contains($0.id)
        }
        sources = Self.seedPaidPresets(into: existingPresets)
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

}
