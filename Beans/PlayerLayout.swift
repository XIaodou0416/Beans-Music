import SwiftUI

// MARK: - 播放器 UI 自由调整（x / y / 大小 / 旋转 / 透明度）

/// 可自由调整的播放器组件
enum PlayerLayoutPart: String, CaseIterable, Identifiable {
    case topBack = "返回"
    case topTitle = "顶部标题"
    case topFavorite = "收藏"
    case cover = "封面"
    case title = "歌名"
    case previewLyric = "预览歌词"
    case vinylCover = "黑胶封面"
    case vinylTitle = "黑胶歌名歌手"
    case vinylPreviewLyric = "黑胶预览歌词"
    /// 保留旧的整体黑胶歌词布局键，用于兼容已保存的用户设置。
    case vinylLyric = "黑胶歌词"
    case vinylLyricsHeader = "黑胶歌词顶部"
    case vinylLyricsText = "黑胶歌词文字"
    case progress = "进度条"
    case controls = "控制行"
    case loop = "循环按钮"
    case previous = "上一首"
    case playPause = "播放暂停"
    case next = "下一首"
    case queue = "播放列表"
    case lyric = "歌词"
    case grabber = "指示线"

    var id: String { rawValue }

    static var classicEditableCases: [PlayerLayoutPart] {
        [
            .topBack, .topTitle, .topFavorite, .cover, .title, .previewLyric,
            .progress, .controls, .loop, .previous, .playPause, .next, .queue,
            .lyric, .grabber,
        ]
    }

    static var vinylEditableCases: [PlayerLayoutPart] {
        [
            .vinylCover, .vinylTitle, .vinylPreviewLyric, .vinylLyricsHeader, .vinylLyricsText,
            .progress, .controls, .loop, .previous, .playPause, .next, .queue,
        ]
    }

    static var editableCases: [PlayerLayoutPart] { classicEditableCases }
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

enum PlayerPreviewDevice: String, CaseIterable, Identifiable {
    case iPhone
    case iPad

    var id: String { rawValue }
}

struct PlayerPreviewDeviceFrame<Content: View>: View {
    let device: PlayerPreviewDevice
    let landscape: Bool
    let content: Content

    init(
        device: PlayerPreviewDevice,
        landscape: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.device = device
        self.landscape = landscape
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            let aspect: CGFloat = device == .iPhone
                ? 1419.0 / 2796.0
                : (landscape ? 1.42 : 0.75)
            let availableWidth = max(1, geometry.size.width - 20)
            let availableHeight = max(1, geometry.size.height - 20)
            let height = min(availableHeight, availableWidth / aspect)
            let width = height * aspect
            let radius = device == .iPhone ? min(30, width * 0.09) : min(24, width * 0.055)

            ZStack {
                RoundedRectangle(cornerRadius: radius + 6, style: .continuous)
                    .fill(Color.black.opacity(0.92))
                content
                    .padding(6)
                    .frame(width: width - 12, height: height - 12)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                if device == .iPhone && !landscape {
                    Image("iPhonePreviewShell")
                        .resizable()
                        .scaledToFit()
                        .allowsHitTesting(false)
                }
            }
            .frame(width: width, height: height)
            .overlay {
                RoundedRectangle(cornerRadius: radius + 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// 单个组件的自定义位置（相对默认位置的偏移）、缩放、旋转和透明度
struct PlayerLayoutEntry: Codable, Equatable {
    var x: CGFloat = 0
    var y: CGFloat = 0
    /// 组件大小缩放（1 为原始大小）
    var scale: CGFloat = 1
    /// 组件旋转角度
    var rotation: CGFloat = 0
    /// 组件透明度
    var opacity: CGFloat = 1

    init(
        x: CGFloat = 0,
        y: CGFloat = 0,
        scale: CGFloat = 1,
        rotation: CGFloat = 0,
        opacity: CGFloat = 1
    ) {
        self.x = x
        self.y = y
        self.scale = scale
        self.rotation = rotation
        self.opacity = opacity
    }

    /// 兼容旧存档（老版本没有新增字段时使用默认值）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decodeIfPresent(CGFloat.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(CGFloat.self, forKey: .y) ?? 0
        scale = try c.decodeIfPresent(CGFloat.self, forKey: .scale) ?? 1
        rotation = try c.decodeIfPresent(CGFloat.self, forKey: .rotation) ?? 0
        opacity = try c.decodeIfPresent(CGFloat.self, forKey: .opacity) ?? 1
    }
}

/// 播放器底部布局调整存储（UserDefaults JSON，持久化）
enum PlayerLayoutStore {
    static let modeKey = "beans.playerLayoutMode"
    static let dataKey = "beans.playerLayoutData"
    private static var pendingSave: DispatchWorkItem?

    static func load() -> [String: PlayerLayoutEntry] {
        guard let raw = UserDefaults.standard.string(forKey: dataKey),
              let data = raw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: PlayerLayoutEntry].self, from: data) else {
            return [:]
        }
        var migrated = dict
        var needsSave = false

        let legacyVinylKey = "黑胶播放器"
        if migrated[legacyVinylKey] == PlayerLayoutEntry(x: 0, y: -8, scale: 1)
            || migrated[legacyVinylKey] == PlayerLayoutEntry(x: 0, y: -56, scale: 1)
            || migrated[legacyVinylKey] == PlayerLayoutEntry() {
            migrated[legacyVinylKey] = PlayerLayoutEntry(x: 0, y: 20, scale: 1)
            needsSave = true
        }
        if migrated[PlayerLayoutPart.vinylLyric.rawValue] == PlayerLayoutEntry(x: 0, y: -10, scale: 1)
            || migrated[PlayerLayoutPart.vinylLyric.rawValue] == PlayerLayoutEntry(x: -2, y: -56, scale: 1) {
            migrated[PlayerLayoutPart.vinylLyric.rawValue] = PlayerLayoutEntry()
            needsSave = true
        }

        // 将旧版“黑胶歌词”整体偏移迁移到新的顶部和歌词文字组件。
        if migrated[PlayerLayoutPart.vinylLyricsHeader.rawValue] == nil,
           migrated[PlayerLayoutPart.vinylLyricsText.rawValue] == nil {
            let legacy = migrated[PlayerLayoutPart.vinylLyric.rawValue] ?? PlayerLayoutEntry()
            migrated[PlayerLayoutPart.vinylLyricsHeader.rawValue] = legacy
            migrated[PlayerLayoutPart.vinylLyricsText.rawValue] = legacy
            migrated.removeValue(forKey: PlayerLayoutPart.vinylLyric.rawValue)
            needsSave = true
        }

        if needsSave {
            saveImmediately(migrated)
        }
        return migrated
    }

    static func save(_ dict: [String: PlayerLayoutEntry]) {
        pendingSave?.cancel()
        let snapshot = dict
        let work = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(snapshot),
                  let raw = String(data: data, encoding: .utf8) else { return }
            UserDefaults.standard.set(raw, forKey: dataKey)
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    static func saveImmediately(_ dict: [String: PlayerLayoutEntry]) {
        pendingSave?.cancel()
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
        case .topBack, .topTitle, .topFavorite, .cover, .title, .previewLyric,
             .vinylCover, .vinylTitle, .vinylPreviewLyric:
            return PlayerLayoutEntry(x: 0, y: 0, scale: 1)
        case .vinylLyric, .vinylLyricsHeader, .vinylLyricsText:
            return PlayerLayoutEntry()
        case .progress:
            return PlayerLayoutEntry(x: 0, y: 17, scale: 1)
        case .controls:
            return PlayerLayoutEntry(x: 0, y: 14, scale: 1.05)
        case .loop:
            return PlayerLayoutEntry(x: -5, y: 0, scale: 1.15)
        case .playPause:
            return PlayerLayoutEntry(x: 0, y: 0, scale: 1)
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

/// 黑胶播放器使用独立存储，避免经典播放器的偏移影响唱盘布局。
enum VinylPlayerLayoutStore {
    private static let dataKey = "beans.vinylPlayer.layoutData"
    private static var pendingSave: DispatchWorkItem?

    static func load() -> [String: PlayerLayoutEntry] {
        guard let raw = UserDefaults.standard.string(forKey: dataKey),
              let data = raw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: PlayerLayoutEntry].self, from: data) else {
            return [:]
        }
        return dict
    }

    static func save(_ dict: [String: PlayerLayoutEntry]) {
        pendingSave?.cancel()
        let snapshot = dict
        let work = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(snapshot),
                  let raw = String(data: data, encoding: .utf8) else { return }
            UserDefaults.standard.set(raw, forKey: dataKey)
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    static func reset() {
        pendingSave?.cancel()
        UserDefaults.standard.removeObject(forKey: dataKey)
    }

    static func defaultEntry(for part: PlayerLayoutPart) -> PlayerLayoutEntry {
        switch part {
        case .vinylCover:
            return PlayerLayoutEntry(y: 20)
        case .vinylTitle, .vinylPreviewLyric:
            return PlayerLayoutEntry()
        case .vinylLyricsHeader:
            return PlayerLayoutEntry(y: 30)
        case .vinylLyricsText:
            return PlayerLayoutEntry(y: -52)
        case .progress:
            return PlayerLayoutEntry(y: -20)
        case .controls:
            return PlayerLayoutEntry(y: 1, scale: 1.1)
        case .loop:
            return PlayerLayoutEntry(x: -5, scale: 1.08)
        case .queue:
            return PlayerLayoutEntry(x: 5, scale: 1.08)
        default:
            return PlayerLayoutEntry()
        }
    }
}

/// iPad 横屏布局与竖屏布局完全独立。
enum IPadLandscapeLayoutPart: String, CaseIterable, Identifiable {
    case header = "顶部区域"
    case artwork = "左侧封面"
    case lyrics = "右侧歌词"
    case progress = "进度条"
    case controls = "播放控件"

    var id: String { rawValue }
}

enum IPadLandscapeLayoutStore {
    typealias LayoutData = [String: [String: PlayerLayoutEntry]]

    private static let dataKey = "beans.player.iPadLandscapeLayoutData"
    private static var pendingSave: DispatchWorkItem?

    static func load() -> LayoutData {
        guard let raw = UserDefaults.standard.string(forKey: dataKey),
              let data = raw.data(using: .utf8),
              let stored = try? JSONDecoder().decode(LayoutData.self, from: data) else {
            return [:]
        }
        return stored
    }

    static func save(_ layouts: LayoutData) {
        pendingSave?.cancel()
        let snapshot = layouts
        let work = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(snapshot),
                  let raw = String(data: data, encoding: .utf8) else { return }
            UserDefaults.standard.set(raw, forKey: dataKey)
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    static func entry(
        for part: IPadLandscapeLayoutPart,
        style: BeansCoverPlayerStyle,
        in layouts: LayoutData
    ) -> PlayerLayoutEntry {
        layouts[style.rawValue]?[part.rawValue] ?? PlayerLayoutEntry()
    }

    static func reset() {
        pendingSave?.cancel()
        UserDefaults.standard.removeObject(forKey: dataKey)
    }
}

/// Apple Music 播放页布局存储。
final class AppleMusicLayoutStore: ObservableObject {
    static let shared = AppleMusicLayoutStore()

    private static let dataKey = "beans.appleMusic.layoutData"
    private let defaults = UserDefaults.standard

    @Published var entries: [String: PlayerLayoutEntry] {
            didSet { scheduleSave() }
    }

    private init() {
        if let raw = defaults.string(forKey: Self.dataKey),
           let data = raw.data(using: .utf8),
           let stored = try? JSONDecoder().decode([String: PlayerLayoutEntry].self, from: data) {
            var normalized = stored
            if normalized[AppleMusicLayoutPart.top.rawValue] == PlayerLayoutEntry() {
                normalized[AppleMusicLayoutPart.top.rawValue] = Self.defaultEntry(for: .top)
            }
            entries = normalized
            if normalized != stored {
                save(normalized)
            }
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

    private var pendingSave: DispatchWorkItem?

    private func scheduleSave() {
        pendingSave?.cancel()
        let snapshot = entries
        let work = DispatchWorkItem { [weak self] in
            self?.save(snapshot)
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func save(_ snapshot: [String: PlayerLayoutEntry]) {
        guard let data = try? JSONEncoder().encode(snapshot),
              let raw = String(data: data, encoding: .utf8) else {
            return
        }
        defaults.set(raw, forKey: Self.dataKey)
    }

    static func defaultEntry(for part: AppleMusicLayoutPart) -> PlayerLayoutEntry {
        switch part {
        case .top:
            return PlayerLayoutEntry(y: -63)
        case .cover, .title, .previewLyric, .progress, .previous, .play, .next, .volume, .actions:
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
            y: legacyDouble("beans.appleMusic.topY", defaultValue: -63)
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
            .rotationEffect(.degrees(entry.rotation))
            .opacity(entry.opacity)
            .offset(x: entry.x, y: entry.y)
    }
}

/// 让组件可自由拖动并应用自定义位置、大小、旋转和透明度
struct Layoutable: ViewModifier {
    let part: PlayerLayoutPart
    /// 编辑模式开关：开启时可拖动，未开启时完全无影响
    let enabled: Bool
    /// 布局数据（双向绑定，实时保存）
    @Binding var data: [String: PlayerLayoutEntry]
    let defaultEntry: PlayerLayoutEntry?
    let appliesTransform: Bool

    init(
        part: PlayerLayoutPart,
        enabled: Bool,
        data: Binding<[String: PlayerLayoutEntry]>,
        defaultEntry: PlayerLayoutEntry? = nil,
        appliesTransform: Bool = true
    ) {
        self.part = part
        self.enabled = enabled
        _data = data
        self.defaultEntry = defaultEntry
        self.appliesTransform = appliesTransform
    }

    func body(content: Content) -> some View {
        let fallback = defaultEntry ?? PlayerLayoutStore.defaultEntry(for: part)
        let entry = appliesTransform ? (data[part.rawValue] ?? fallback) : PlayerLayoutEntry()
        let displayEntry = normalizedEntry(entry)
        content
            .scaleEffect(displayEntry.scale)
            .rotationEffect(.degrees(displayEntry.rotation))
            .opacity(displayEntry.opacity)
            .offset(x: displayEntry.x, y: displayEntry.y)
            .simultaneousGesture(
                enabled && appliesTransform
                    ? DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            var e = data[part.rawValue] ?? fallback
                            e.x = normalizedX(value.translation.width)
                            e.y = value.translation.height
                            data[part.rawValue] = e
                        }
                    : nil
            )
    }

    private func normalizedEntry(_ entry: PlayerLayoutEntry) -> PlayerLayoutEntry {
        var normalized = entry
        normalized.x = normalizedX(entry.x)
        normalized.rotation = min(max(entry.rotation, -180), 180)
        normalized.opacity = min(max(entry.opacity, 0.15), 1)
        if part == .loop || part == .queue {
            normalized.scale = min(max(entry.scale, 0.82), 1.15)
        }
        return normalized
    }

    private func normalizedX(_ value: CGFloat) -> CGFloat {
        guard part == .loop || part == .queue else { return value }
        return min(max(value, -24), 24)
    }
}

/// iPad 横屏组件的位置与大小调整。
struct IPadLandscapeLayoutable: ViewModifier {
    let part: IPadLandscapeLayoutPart
    let style: BeansCoverPlayerStyle
    let enabled: Bool
    @Binding var data: IPadLandscapeLayoutStore.LayoutData
    let appliesTransform: Bool

    init(
        part: IPadLandscapeLayoutPart,
        style: BeansCoverPlayerStyle,
        enabled: Bool,
        data: Binding<IPadLandscapeLayoutStore.LayoutData>,
        appliesTransform: Bool = true
    ) {
        self.part = part
        self.style = style
        self.enabled = enabled
        _data = data
        self.appliesTransform = appliesTransform
    }

    func body(content: Content) -> some View {
        let entry = appliesTransform
            ? IPadLandscapeLayoutStore.entry(for: part, style: style, in: data)
            : PlayerLayoutEntry()
        let displayEntry = PlayerLayoutEntry(
            x: min(max(entry.x, -220), 220),
            y: min(max(entry.y, -180), 180),
            scale: min(max(entry.scale, 0.45), 1.6),
            rotation: min(max(entry.rotation, -180), 180),
            opacity: min(max(entry.opacity, 0.15), 1)
        )
        content
            .scaleEffect(displayEntry.scale)
            .rotationEffect(.degrees(displayEntry.rotation))
            .opacity(displayEntry.opacity)
            .offset(x: displayEntry.x, y: displayEntry.y)
            .simultaneousGesture(
                enabled && appliesTransform
                    ? DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            var styleData = data[style.rawValue] ?? [:]
                            var updated = styleData[part.rawValue] ?? PlayerLayoutEntry()
                            updated.x = value.translation.width
                            updated.y = value.translation.height
                            styleData[part.rawValue] = updated
                            data[style.rawValue] = styleData
                        }
                    : nil
            )
    }
}
