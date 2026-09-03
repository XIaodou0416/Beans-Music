import Foundation

/// 第三方解锁源配置。
/// kind：paid-lx、paid-cr、paid-qt 分别对应三种插件运行时格式。
/// template：请求 URL 模板，支持 {id}、{source}、{quality} 占位符。
/// headers：可选的请求头与内置元数据。
/// quality：默认音质选择。
/// script：LX / Baka 风格 JS 脚本内容。
struct ThirdPartySource: Identifiable, Codable, Hashable, Sendable {
    var id = UUID().uuidString
    var name: String
    var kind: String = "keyword"
    var template: String
    var urlPath: String = "url"
    var headers: [String: String] = [:]
    var quality: String = "320k"
    var script: String?
    var enabled: Bool = true
    var isPreset: Bool = false
    var isFree: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, kind, template, urlPath, headers, quality, script, enabled, isPreset, isFree
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        kind: String = "keyword",
        template: String,
        urlPath: String = "url",
        headers: [String: String] = [:],
        quality: String = "320k",
        script: String? = nil,
        enabled: Bool = true,
        isPreset: Bool = false,
        isFree: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.template = template
        self.urlPath = urlPath
        self.headers = headers
        self.quality = quality
        self.script = script
        self.enabled = enabled
        self.isPreset = isPreset
        self.isFree = isFree
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名音源"
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "keyword"
        template = try container.decodeIfPresent(String.self, forKey: .template) ?? ""
        urlPath = try container.decodeIfPresent(String.self, forKey: .urlPath) ?? "url"
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        quality = try container.decodeIfPresent(String.self, forKey: .quality) ?? headers["quality"] ?? "320k"
        script = try container.decodeIfPresent(String.self, forKey: .script)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        isPreset = try container.decodeIfPresent(Bool.self, forKey: .isPreset) ?? false
        isFree = try container.decodeIfPresent(Bool.self, forKey: .isFree) ?? false
    }
}

/// 第三方音源管理：保留内置预设接口，密钥只使用用户自己填写或导入的内容。
final class UnblockSourceStore: ObservableObject {
    static let shared = UnblockSourceStore()
    static let userAPIKeysKey = "beans.thirdPartyAPIKeys"
    /// 普通版本使用平台原生播放，并按用户设置启用第三方兜底。
    static let singleSourceMode = false
    static let singleSourceID = "beans.special.cr.v1"

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
            quality: "320k",
            isPreset: true
        ),
        ThirdPartySource(
            id: "beans.preset.shiqianjiang.cr.v7",
            name: "聆澜音源 · CR",
            kind: "paid-cr",
            template: paidURLTemplate,
            headers: paidHeaders,
            quality: "320k",
            isPreset: true
        ),
        ThirdPartySource(
            id: "beans.preset.shiqianjiang.qt.v7",
            name: "聆澜音源 · QT",
            kind: "paid-qt",
            template: paidURLTemplate,
            headers: paidHeaders,
            quality: "320k",
            isPreset: true
        ),
    ]

    static let freePresetSources: [ThirdPartySource] = [
        ThirdPartySource(
            id: "beans.preset.cerumusic.free.v1",
            name: "CeruMusic · 免费音源",
            kind: "script-free",
            template: "",
            quality: "320k",
            script: CeruMusicBuiltinSource.script,
            isPreset: true,
            isFree: true
        ),
        ThirdPartySource(
            id: "beans.preset.quandouyao.free.v1",
            name: "全豆要 · 免费音源",
            kind: "script-free",
            template: "",
            quality: "320k",
            script: QuanDouYaoBuiltinSource.script,
            isPreset: true,
            isFree: true
        )
    ]

    static let singlePresetSource = ThirdPartySource(
        id: singleSourceID,
        name: "CR 专属音源",
        kind: "script-exclusive",
        template: "",
        quality: "hires",
        script: CRMusicSpecialBuiltinSource.script,
        isPreset: true,
        isFree: false
    )

    static let presetSources: [ThirdPartySource] = singleSourceMode
        ? [singlePresetSource]
        : paidPresetSources + freePresetSources
    static let protectedPresetSourceIDs = Set(presetSources.map(\.id))

    @Published var sources: [ThirdPartySource] {
        didSet { save() }
    }

    private let defaults = UserDefaults.standard
    private let presetsKey = "beans.unblock.presets"
    private let legacyCustomKey = "beans.unblock.custom"
    private let legacyLXKey = "beans.unblock.lxScripts"

    private init() {
        if Self.singleSourceMode {
            sources = [Self.singlePresetSource]
            defaults.removeObject(forKey: legacyCustomKey)
            defaults.removeObject(forKey: legacyLXKey)
            save()
            return
        }

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

        // 既保留当前支持的预设，也保留用户导入/创建的自定义音源。
        // 预设项按内置模板更新字段，自定义项保持原样。
        let supportedPresetIDs = Set(Self.presetSources.map(\.id))
        var normalized: [ThirdPartySource] = []
        var seen = Set<String>()
        for source in savedSources {
            if source.isPreset {
                guard supportedPresetIDs.contains(source.id) else { continue }
                guard let preset = Self.presetSources.first(where: { $0.id == source.id }) else { continue }
                var updated = preset
                updated.name = source.name.isEmpty ? preset.name : source.name
                updated.kind = source.kind.isEmpty ? preset.kind : source.kind
                updated.template = source.template.isEmpty ? preset.template : source.template
                updated.urlPath = source.urlPath.isEmpty ? preset.urlPath : source.urlPath
                updated.headers = source.headers.isEmpty ? preset.headers : source.headers
                updated.enabled = source.enabled
                updated.isPreset = true
                updated.isFree = preset.isFree
                if seen.insert(updated.id).inserted {
                    normalized.append(updated)
                }
            } else if seen.insert(source.id).inserted {
                normalized.append(source)
            }
        }
        for preset in Self.presetSources where !seen.contains(preset.id) {
            normalized.append(preset)
        }
        sources = normalized
        defaults.removeObject(forKey: legacyCustomKey)
        defaults.removeObject(forKey: legacyLXKey)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sources) {
            defaults.set(data, forKey: presetsKey)
        }
    }

    func isProtectedPreset(_ source: ThirdPartySource) -> Bool {
        source.isPreset || Self.protectedPresetSourceIDs.contains(source.id)
    }

    func addSource(_ source: ThirdPartySource) {
        guard !Self.singleSourceMode else { return }
        upsert(source)
    }

    func addSources(_ newSources: [ThirdPartySource]) {
        guard !Self.singleSourceMode else { return }
        guard !newSources.isEmpty else { return }
        var merged = sources
        for source in newSources {
            if let index = merged.firstIndex(where: { $0.id == source.id }) {
                merged[index] = source
            } else {
                merged.append(source)
            }
        }
        sources = merged
        save()
    }

    func upsert(_ source: ThirdPartySource) {
        guard !Self.singleSourceMode else { return }
        var merged = sources
        if let index = merged.firstIndex(where: { $0.id == source.id }) {
            merged[index] = source
        } else {
            merged.append(source)
        }
        sources = merged
        save()
    }

    func moveSource(id: String, by offset: Int) {
        guard !Self.singleSourceMode else { return }
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(0, index + offset), max(0, sources.count - 1))
        guard target != index else { return }
        var reordered = sources
        let item = reordered.remove(at: index)
        reordered.insert(item, at: target)
        sources = reordered
        save()
    }

    func updateEnabled(id: String, enabled: Bool) {
        guard !Self.singleSourceMode else { return }
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        var updated = sources
        updated[index].enabled = enabled
        sources = updated
        save()
    }

    @discardableResult
    func removeSource(id: String) -> Bool {
        guard !Self.singleSourceMode else { return false }
        guard !Self.protectedPresetSourceIDs.contains(id) else { return false }
        let originalCount = sources.count
        sources.removeAll { $0.id == id }
        save()
        return sources.count != originalCount
    }

}
