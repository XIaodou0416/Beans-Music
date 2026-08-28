import SwiftUI

// MARK: - 播放器 UI 自由调整（x / y / 大小）

/// 可自由调整的播放器组件
enum PlayerLayoutPart: String, CaseIterable, Identifiable {
    case topBack = "返回"
    case topFavorite = "收藏"
    case topMore = "更多"
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
        case .topBack, .topFavorite, .topMore, .cover, .title, .previewLyric:
            return PlayerLayoutEntry(x: 0, y: 0, scale: 1)
        case .progress:
            return PlayerLayoutEntry(x: 0, y: 17, scale: 1)
        case .controls:
            return PlayerLayoutEntry(x: 0, y: 14, scale: 1.05)
        case .loop:
            return PlayerLayoutEntry(x: 5, y: 0, scale: 1.15)
        case .queue:
            return PlayerLayoutEntry(x: 0, y: -5, scale: 1.15)
        case .previous, .next:
            return PlayerLayoutEntry(x: 0, y: 0, scale: 1)
        case .grabber:
            return PlayerLayoutEntry(x: 0, y: 27, scale: 0.7)
        case .lyric:
            return PlayerLayoutEntry(x: 0, y: 0, scale: 1)
        }
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
