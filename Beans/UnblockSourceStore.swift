import Foundation

/// 内置第三方解锁源。
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

/// 内置音源管理：首次启动时写入三种插件格式对应的预设。
final class UnblockSourceStore: ObservableObject {
    static let shared = UnblockSourceStore()

    private static let paidAPIURL = "https://source.shiqianjiang.cn/api/music"
    private static let paidAPIKeys = [
        "CERU_KEY-51440644-C9AD-4E10-B593-258FF59CF259",
        "CERU_KEY-1C0F7359-2863-46F7-A63C-B0E0E744CDFE",
        "CERU_KEY-B2495961-F872-4F31-9893-F6E8F15B5D62",
        "CERU_KEY-51A42014-7122-4D7A-9964-51DEE617FDB5",
        "CERU_KEY-DCF912D8-1AF2-43E0-B5BE-1AE9ACB628CA",
    ]
    private static let paidURLTemplate = "\(paidAPIURL)/url?source={source}&songId={id}&quality={quality}"
    private static var paidHeaders: [String: String] {
        [
            "apiKey": paidAPIKeys[0],
            "apiKeys": paidAPIKeys.joined(separator: ","),
            "quality": "320k",
        ]
    }

    /// 来自用户提供的三个脚本：LX、CeruMusic CR、CeruMusic QT。
    /// 三个脚本最终调用同一个 API，播放时会按请求指纹去重，避免同一首歌重复请求三次。
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

    @Published var presetSources: [ThirdPartySource] {
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

        // 只保留当前支持的三个预设，清理旧版本保存的已移除音源。
        let supportedPresetIDs = Set(Self.paidPresetSources.map(\.id))
        let existingPresets = savedSources.filter {
            $0.isPreset && supportedPresetIDs.contains($0.id)
        }
        presetSources = Self.seedPaidPresets(into: existingPresets)
        defaults.removeObject(forKey: legacyCustomKey)
        defaults.removeObject(forKey: legacyLXKey)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(presetSources) {
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
