import Foundation

/// 第三方解锁源配置。
/// kind：音源类型标识，用于兼容不同导入格式。
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

    enum CodingKeys: String, CodingKey {
        case id, name, kind, template, urlPath, headers, quality, script, enabled
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
        enabled: Bool = true
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
    }
}

/// 第三方音源管理：只保存用户导入的音源配置。
final class UnblockSourceStore: ObservableObject {
    static let shared = UnblockSourceStore()
    private static let removedBuiltInSourceIDs: Set<String> = [
        "beans.preset.shiqianjiang.lx.v7",
        "beans.preset.shiqianjiang.cr.v7",
        "beans.preset.shiqianjiang.qt.v7",
        "beans.preset.legacy.guoyue.qq.v1",
        "beans.preset.legacy.guoyue.netease.v1",
        "beans.preset.cerumusic.free.v1",
        "beans.preset.quandouyao.free.v1",
        "beans.special.cr.v1"
    ]
    @Published var sources: [ThirdPartySource] {
        didSet { save() }
    }

    var managementVisibleSources: [ThirdPartySource] {
        sources
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

        // 旧版本的内置预设全部丢弃，只保留用户导入的配置。
        var seen = Set<String>()
        sources = savedSources.compactMap { source in
            guard !Self.removedBuiltInSourceIDs.contains(source.id),
                  seen.insert(source.id).inserted else { return nil }
            return source
        }
        defaults.removeObject(forKey: legacyCustomKey)
        defaults.removeObject(forKey: legacyLXKey)
        defaults.removeObject(forKey: "beans.thirdPartyAPIKeys")
        defaults.removeObject(forKey: "beans.paidAudioSource.usageRecorded")
        defaults.removeObject(forKey: "beans.enableUnblock")
        defaults.removeObject(forKey: "beans.useFreeAudioSource")
        defaults.removeObject(forKey: "beans.showThirdPartyKeys")
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sources) {
            defaults.set(data, forKey: presetsKey)
        }
    }

    func addSource(_ source: ThirdPartySource) {
        upsert(source)
    }

    func addSources(_ newSources: [ThirdPartySource]) {
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
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(0, index + offset), max(0, sources.count - 1))
        guard target != index else { return }
        var reordered = sources
        let item = reordered.remove(at: index)
        reordered.insert(item, at: target)
        sources = reordered
        save()
    }

    func moveManagementSource(id: String, by offset: Int) {
        let visibleIDs = managementVisibleSources.map(\.id)
        guard let visibleIndex = visibleIDs.firstIndex(of: id) else { return }
        let targetVisibleIndex = visibleIndex + offset
        guard visibleIDs.indices.contains(targetVisibleIndex) else { return }
        let targetID = visibleIDs[targetVisibleIndex]
        guard let sourceIndex = sources.firstIndex(where: { $0.id == id }) else { return }

        var reordered = sources
        let item = reordered.remove(at: sourceIndex)
        guard let adjustedTargetIndex = reordered.firstIndex(where: { $0.id == targetID }) else { return }
        let insertionIndex = targetVisibleIndex > visibleIndex
            ? adjustedTargetIndex + 1
            : adjustedTargetIndex
        reordered.insert(item, at: min(insertionIndex, reordered.count))
        sources = reordered
        save()
    }

    func updateEnabled(id: String, enabled: Bool) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        var updated = sources
        updated[index].enabled = enabled
        sources = updated
        save()
    }

    @discardableResult
    func removeSource(id: String) -> Bool {
        let originalCount = sources.count
        sources.removeAll { $0.id == id }
        save()
        return sources.count != originalCount
    }

}

extension UnblockSourceStore {
    func availableThirdPartyQualities() -> [ThirdPartyAudioQuality] {
        let options = sources
            .filter(\.enabled)
            .flatMap { Self.supportedQualities(for: $0) }
            .uniquePreservingOrder()
        return options.isEmpty ? ThirdPartyAudioQuality.allCases : options
    }

    static func supportedQualities(
        for source: ThirdPartySource,
        providerCode: String? = nil
    ) -> [ThirdPartyAudioQuality] {
        let explicit = explicitQualities(
            from: source.headers["qualities"] ?? source.headers["qualityOptions"] ?? source.headers["qualitys"]
        )
        if !explicit.isEmpty {
            if let providerCode {
                let platform = Set(ThirdPartyAudioQuality.supported(providerCode: providerCode))
                return explicit.filter { platform.contains($0) }
            }
            return explicit
        }

        if let script = source.script,
           let explicit = scriptQualities(from: script),
           !explicit.isEmpty {
            if let providerCode {
                let platform = Set(ThirdPartyAudioQuality.supported(providerCode: providerCode))
                return explicit.filter { platform.contains($0) }
            }
            return explicit
        }

        if let providerCode {
            return ThirdPartyAudioQuality.supported(providerCode: providerCode)
        }

        if let sourceProvider = source.headers["source"] ?? source.headers["platform"] {
            return ThirdPartyAudioQuality.supported(providerCode: sourceProvider)
        }

        return ThirdPartyAudioQuality.allCases
    }

    private static func explicitQualities(from raw: String?) -> [ThirdPartyAudioQuality] {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return [] }
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;|/[]\"'"))
        return raw
            .components(separatedBy: separators)
            .compactMap { ThirdPartyAudioQuality(sourceValue: $0) }
            .uniquePreservingOrder()
    }

    private static func scriptQualities(from script: String) -> [ThirdPartyAudioQuality]? {
        let pattern = #"(?i)(?:qualitys?|qualityOptions)\s*[:=]\s*\[([^\]]*)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: script,
                options: [],
                range: NSRange(script.startIndex..<script.endIndex, in: script)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: script) else {
            return nil
        }
        return explicitQualities(from: String(script[range]))
    }
}

private extension Array where Element: Hashable {
    func uniquePreservingOrder() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
