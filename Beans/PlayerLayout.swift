import SwiftUI

// MARK: - 播放器 UI 自由调整（x / y / 大小）

/// 可自由调整的播放器组件
enum PlayerLayoutPart: String, CaseIterable, Identifiable {
    case topBack = "返回"
    case topTitle = "顶部标题"
    case topFavorite = "收藏"
    case cover = "封面"
    case title = "歌名"
    case previewLyric = "预览歌词"
    case progress = "进度条"
    case controls = "控制行"
    case loop = "循环按钮"
    case previous = "上一首"
    case next = "下一首"
    case queue = "播放列表"
    case lyric = "歌词"
    case grabber = "指示线"

    var id: String { rawValue }
}

/// Apple Music 播放页实时调试组件。
enum AppleMusicLayoutPart: String, CaseIterable, Identifiable {
    case top = "顶部指示线"
    case cover = "封面"
    case title = "歌名歌手"
    case previewLyric = "预览歌词"
    case progress = "进度条"
    case previous = "上一首"
    case play = "播放按钮"
    case next = "下一首"
    case volume = "音量条"
    case actions = "底部按钮"

    var id: String { rawValue }
}

/// 单个组件的自定义位置（相对默认位置的偏移）与缩放
struct PlayerLayoutEntry: Codable, Equatable {
    var x: CGFloat = 0
    var y: CGFloat = 0
    /// 组件大小缩放（1 为原始大小）
    var scale: CGFloat = 1

    init(x: CGFloat = 0, y: CGFloat = 0, scale: CGFloat = 1) {
        self.x = x
        self.y = y
        self.scale = scale
    }

    /// 兼容旧存档（老版本没有 scale 字段，缺省为 1）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decodeIfPresent(CGFloat.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(CGFloat.self, forKey: .y) ?? 0
        scale = try c.decodeIfPresent(CGFloat.self, forKey: .scale) ?? 1
    }
}

/// 播放器底部布局调整存储（UserDefaults JSON，持久化）
enum PlayerLayoutStore {
    static let modeKey = "beans.playerLayoutMode"
    static let dataKey = "beans.playerLayoutData"

    static func load() -> [String: PlayerLayoutEntry] {
        guard let raw = UserDefaults.standard.string(forKey: dataKey),
              let data = raw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: PlayerLayoutEntry].self, from: data) else {
            return [:]
        }
        return dict
    }

    static func save(_ dict: [String: PlayerLayoutEntry]) {
        if let data = try? JSONEncoder().encode(dict),
           let raw = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(raw, forKey: dataKey)
        }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: dataKey)
    }

    /// 各组件默认位置 / 大小（相对原始布局的偏移与缩放）
    static func defaultEntry(for part: PlayerLayoutPart) -> PlayerLayoutEntry {
        switch part {
        case .topBack, .topTitle, .topFavorite, .cover, .title, .previewLyric:
            return PlayerLayoutEntry(x: 0, y: 0, scale: 1)
        case .progress:
            return PlayerLayoutEntry(x: 0, y: 17, scale: 1)
        case .controls:
            return PlayerLayoutEntry(x: 0, y: 14, scale: 1.05)
        case .loop:
            return PlayerLayoutEntry(x: -5, y: 0, scale: 1.15)
        case .queue:
            return PlayerLayoutEntry(x: 5, y: 0, scale: 1.15)
        case .previous, .next:
            return PlayerLayoutEntry(x: 0, y: 0, scale: 1)
        case .grabber:
            return PlayerLayoutEntry(x: 0, y: 27, scale: 0.7)
        case .lyric:
            return PlayerLayoutEntry(x: 0, y: 0, scale: 1)
        }
    }
}

/// Apple Music 播放页布局存储。
final class AppleMusicLayoutStore: ObservableObject {
    static let shared = AppleMusicLayoutStore()

    private static let dataKey = "beans.appleMusic.layoutData"
    private let defaults = UserDefaults.standard

    @Published var entries: [String: PlayerLayoutEntry] {
        didSet { save() }
    }

    private init() {
        if let raw = defaults.string(forKey: Self.dataKey),
           let data = raw.data(using: .utf8),
           let stored = try? JSONDecoder().decode([String: PlayerLayoutEntry].self, from: data) {
            entries = stored
        } else {
            entries = Self.migrateLegacyEntries(from: defaults)
        }
    }

    func entry(for part: AppleMusicLayoutPart) -> PlayerLayoutEntry {
        entries[part.rawValue] ?? Self.defaultEntry(for: part)
    }

    func set(_ entry: PlayerLayoutEntry, for part: AppleMusicLayoutPart) {
        entries[part.rawValue] = entry
    }

    func reset(_ part: AppleMusicLayoutPart) {
        entries[part.rawValue] = nil
    }

    func resetAll() {
        entries = [:]
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries),
              let raw = String(data: data, encoding: .utf8) else {
            return
        }
        defaults.set(raw, forKey: Self.dataKey)
    }

    static func defaultEntry(for part: AppleMusicLayoutPart) -> PlayerLayoutEntry {
        switch part {
        case .top, .cover, .title, .previewLyric, .progress, .previous, .play, .next, .volume, .actions:
            return PlayerLayoutEntry()
        }
    }

    private static func migrateLegacyEntries(from defaults: UserDefaults) -> [String: PlayerLayoutEntry] {
        var migrated: [String: PlayerLayoutEntry] = [:]

        func legacyDouble(_ key: String, defaultValue: Double) -> CGFloat {
            guard defaults.object(forKey: key) != nil else { return CGFloat(defaultValue) }
            return CGFloat(defaults.double(forKey: key))
        }

        migrated[AppleMusicLayoutPart.top.rawValue] = PlayerLayoutEntry(
            y: legacyDouble("beans.appleMusic.topY", defaultValue: 0)
        )
        migrated[AppleMusicLayoutPart.cover.rawValue] = PlayerLayoutEntry(
            scale: legacyDouble("beans.appleMusic.coverScale", defaultValue: 1)
        )
        migrated[AppleMusicLayoutPart.title.rawValue] = PlayerLayoutEntry(
            y: legacyDouble("beans.appleMusic.titleY", defaultValue: 0)
        )
        migrated[AppleMusicLayoutPart.previewLyric.rawValue] = PlayerLayoutEntry(
            y: legacyDouble("beans.appleMusic.lyricY", defaultValue: 0)
        )
        let legacyControls = PlayerLayoutEntry(
            y: legacyDouble("beans.appleMusic.controlsY", defaultValue: 0)
        )
        migrated[AppleMusicLayoutPart.previous.rawValue] = legacyControls
        migrated[AppleMusicLayoutPart.play.rawValue] = legacyControls
        migrated[AppleMusicLayoutPart.next.rawValue] = legacyControls
        migrated[AppleMusicLayoutPart.actions.rawValue] = PlayerLayoutEntry(
            y: legacyDouble("beans.appleMusic.actionsY", defaultValue: 0)
        )
        return migrated
    }
}

/// 仅负责应用 Apple Music 组件的实时位置和大小。
struct AppleMusicLayoutTransform: ViewModifier {
    let entry: PlayerLayoutEntry

    func body(content: Content) -> some View {
        content
            .scaleEffect(entry.scale)
            .offset(x: entry.x, y: entry.y)
    }
}

/// 让组件可自由拖动并应用自定义位置与大小（x / y 偏移 + scale 缩放）
struct Layoutable: ViewModifier {
    let part: PlayerLayoutPart
    /// 编辑模式开关：开启时可拖动，未开启时完全无影响
    let enabled: Bool
    /// 布局数据（双向绑定，实时保存）
    @Binding var data: [String: PlayerLayoutEntry]

    func body(content: Content) -> some View {
        let entry = data[part.rawValue] ?? PlayerLayoutStore.defaultEntry(for: part)
        content
            .scaleEffect(entry.scale)
            .offset(x: entry.x, y: entry.y)
            .gesture(
                enabled
                    ? DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            var e = data[part.rawValue] ?? PlayerLayoutStore.defaultEntry(for: part)
                            e.x = value.translation.width
                            e.y = value.translation.height
                            data[part.rawValue] = e
                        }
                    : nil
            )
    }
}
