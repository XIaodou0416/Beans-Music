import SwiftUI
import UIKit
import CoreImage

// MARK: - 动态主题色（跟随系统外观或手动切换）

extension UIColor {
    static func beansDynamic(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }

    static let beansBackground = beansDynamic(
        light: UIColor(red: 0.949, green: 0.949, blue: 0.961, alpha: 1),  // #F2F2F7
        dark: UIColor(red: 0.039, green: 0.039, blue: 0.047, alpha: 1)    // #0A0A0C
    )
    static let beansCard = beansDynamic(
        light: UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1),
        dark: UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1)    // #1C1C1E
    )
    private static let beansDefaultLabel = beansDynamic(
        light: UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1),
        dark: UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)
    )
    static var beansLabel: UIColor {
        if let raw = UserDefaults.standard.string(forKey: "beans.labelColorHex"),
           let custom = UIColor(hex: raw) {
            return custom
        }
        return beansDefaultLabel
    }
    static let beansSecondary = beansDynamic(
        light: UIColor(red: 0.424, green: 0.424, blue: 0.439, alpha: 1),  // #6C6C70
        dark: UIColor(red: 0.596, green: 0.596, blue: 0.624, alpha: 1)    // #98989F
    )
    /// 全局着色（跟随配色主题：浅色用深色调保证对比度，深色用亮色调保证可读性）
    static var beansAmber: UIColor {
        if let custom = ThemeStore.shared.customAccentHex, let c = UIColor(hex: custom) {
            return beansDynamic(light: c.shaded(0.25), dark: c)
        }
        let accent = ThemeStore.shared.accent
        return beansDynamic(light: accent.tintLight, dark: accent.tintDark)
    }
    static let beansSage = beansDynamic(
        light: UIColor(red: 0.384, green: 0.482, blue: 0.310, alpha: 1),
        dark: UIColor(red: 0.560, green: 0.650, blue: 0.480, alpha: 1)
    )
    /// 液态玻璃基底填充：修复 `.glassEffect` 配 `Color.clear` 时玻璃无内容可采样、
    /// 渲染成灰糊块/模糊失效的问题（玻璃效果需要一个非透明基底色）。
    static let beansGlassFill = beansDynamic(
        light: UIColor(white: 0.96, alpha: 0.55),
        dark: UIColor(white: 0.07, alpha: 0.55)
    )
}

extension Color {
    static let beansBackground = Color(uiColor: .beansBackground)
    static let beansCard = Color(uiColor: .beansCard)
    static var beansLabel: Color { Color(uiColor: .beansLabel) }
    static let beansSecondary = Color(uiColor: .beansSecondary)

    /// 全局说明文字（注释）颜色：可在「我的 → 外观」中自定义；默认跟随次要文字色
    static var beansComment: Color {
        if let raw = UserDefaults.standard.string(forKey: "beans.commentColorHex"),
           let c = Color(hex: raw) { return c }
        return .beansSecondary
    }
    /// 全局着色：跟随当前配色主题即时变化（所有页面统一生效）
    static var beansAmber: Color { Color(uiColor: .beansAmber) }
    static let beansSage = Color(uiColor: .beansSage)
    static let beansGlassFill = Color(uiColor: .beansGlassFill)
    /// 当前配色主题的高亮色（播放器进度点 / 光斑 / 歌词高亮等）
    static var beansHighlight: Color {
        ThemeStore.shared.customAccent ?? AccentTheme.current.highlight
    }
}

// MARK: - 主题偏好

enum BeansThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }
}

// MARK: - 配色主题（多套配色，可在「我的 → 外观」中切换；全局统一生效）

enum BeansAccent: String, CaseIterable, Identifiable {
    case amber = "琥珀暖金"
    case mint = "青碧湖绿"
    case pink = "樱粉"
    case sky = "星蓝"
    case violet = "罗兰紫"
    case cyber = "赛博青"
    case peach = "蜜桃粉"
    case gold = "鎏金黑"
    case emerald = "翡翠绿"

    var id: String { rawValue }

    /// 渐变强调色（播放键 / 进度条 / 玻璃光晕）
    var gradientColors: [Color] {
        switch self {
        case .amber:
            return [Color(red: 0.949, green: 0.639, blue: 0.235), Color(red: 0.753, green: 0.478, blue: 0.039)]
        case .mint:
            return [Color(red: 0.42, green: 0.78, blue: 0.62), Color(red: 0.16, green: 0.55, blue: 0.42)]
        case .pink:
            return [Color(red: 0.96, green: 0.56, blue: 0.70), Color(red: 0.82, green: 0.37, blue: 0.56)]
        case .sky:
            return [Color(red: 0.39, green: 0.71, blue: 0.96), Color(red: 0.23, green: 0.48, blue: 0.84)]
        case .violet:
            return [Color(red: 0.70, green: 0.62, blue: 0.86), Color(red: 0.49, green: 0.34, blue: 0.76)]
        case .cyber:
            return [Color(red: 0.25, green: 0.90, blue: 0.85), Color(red: 0.05, green: 0.55, blue: 0.65)]
        case .peach:
            return [Color(red: 1.00, green: 0.62, blue: 0.52), Color(red: 0.95, green: 0.38, blue: 0.55)]
        case .gold:
            return [Color(red: 0.92, green: 0.75, blue: 0.35), Color(red: 0.45, green: 0.33, blue: 0.10)]
        case .emerald:
            return [Color(red: 0.30, green: 0.85, blue: 0.55), Color(red: 0.05, green: 0.50, blue: 0.35)]
        }
    }

    /// 高亮色（渐变首色，用于光斑 / 进度点 / 歌词高亮）
    var highlight: Color {
        gradientColors[0]
    }

    /// 常规着色（图标 / 文字）浅色模式版本：深色调保证浅色背景对比度
    var tintLight: UIColor {
        switch self {
        case .amber: return UIColor(red: 0.72, green: 0.44, blue: 0.03, alpha: 1)   // 深琥珀
        case .mint: return UIColor(red: 0.15, green: 0.53, blue: 0.39, alpha: 1)    // 深湖绿
        case .pink: return UIColor(red: 0.78, green: 0.33, blue: 0.53, alpha: 1)    // 深樱粉
        case .sky: return UIColor(red: 0.20, green: 0.48, blue: 0.84, alpha: 1)     // 深星蓝
        case .violet: return UIColor(red: 0.46, green: 0.34, blue: 0.77, alpha: 1)  // 深罗兰
        case .cyber: return UIColor(red: 0.05, green: 0.48, blue: 0.55, alpha: 1)     // 深赛博青
        case .peach: return UIColor(red: 0.82, green: 0.32, blue: 0.45, alpha: 1)     // 深蜜桃
        case .gold: return UIColor(red: 0.55, green: 0.40, blue: 0.08, alpha: 1)      // 深鎏金
        case .emerald: return UIColor(red: 0.08, green: 0.45, blue: 0.30, alpha: 1)   // 深翡翠
        }
    }

    /// 常规着色（图标 / 文字）深色模式版本：亮色调保证深色背景对比度
    var tintDark: UIColor {
        switch self {
        case .amber: return UIColor(red: 0.96, green: 0.70, blue: 0.35, alpha: 1)
        case .mint: return UIColor(red: 0.45, green: 0.80, blue: 0.64, alpha: 1)
        case .pink: return UIColor(red: 0.97, green: 0.60, blue: 0.74, alpha: 1)
        case .sky: return UIColor(red: 0.45, green: 0.72, blue: 0.98, alpha: 1)
        case .violet: return UIColor(red: 0.71, green: 0.62, blue: 0.92, alpha: 1)
        case .cyber: return UIColor(red: 0.35, green: 0.95, blue: 0.88, alpha: 1)
        case .peach: return UIColor(red: 1.00, green: 0.68, blue: 0.58, alpha: 1)
        case .gold: return UIColor(red: 0.94, green: 0.80, blue: 0.45, alpha: 1)
        case .emerald: return UIColor(red: 0.42, green: 0.92, blue: 0.62, alpha: 1)
        }
    }
}

// MARK: - 全局 UI 风格

enum BeansUIStyle: String, CaseIterable {
    case liquid = "liquid"
    case clear = "clear"
    case compact = "compact"

    var title: String {
        switch self {
        case .liquid: return "默认液态"
        case .clear: return "磨砂玻璃"
        case .compact: return "紧凑淡雅"
        }
    }
}

// MARK: - 播放器按钮样式

enum BeansPlayerButtonStyle: String, CaseIterable, Identifiable {
    case glass
    case outline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: return "经典圆形"
        case .outline: return "线框图标"
        }
    }

    var previewIcon: String {
        switch self {
        case .glass: return "circle"
        case .outline: return "circle.dashed"
        }
    }

    var subtitle: String {
        switch self {
        case .glass: return "保留原来的圆形玻璃按钮"
        case .outline: return "细线描边，适合极简布局"
        }
    }
}

// MARK: - 播放器浮尘样式

enum BeansPlayerDustMode: String, CaseIterable, Identifiable {
    case off
    case snow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "关闭"
        case .snow: return "动态浮尘"
        }
    }

    var icon: String {
        switch self {
        case .off: return "circle.slash"
        case .snow: return "sparkles"
        }
    }
}

// MARK: - 播放器封面页样式

enum BeansCoverPlayerStyle: String, CaseIterable, Identifiable {
    case classic
    case controlPanel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "经典封面"
        case .controlPanel: return "控制面板"
        }
    }

    var subtitle: String {
        switch self {
        case .classic: return "封面、歌名和预览歌词分层显示"
        case .controlPanel: return "封面、歌词和快捷操作聚合成高级面板"
        }
    }

    var icon: String {
        switch self {
        case .classic: return "square.stack"
        case .controlPanel: return "slider.horizontal.3"
        }
    }
}

// MARK: - 全局主题（ObservableObject：一处修改，全 App 即时联动）

final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    /// 当前配色主题（@Published：切换后所有观察视图立即重绘）
    @Published var accent: BeansAccent
    /// 自定义全局强调色（色盘任选，nil 表示使用预设主题）
    @Published var customAccentHex: String?
    /// 自定义背景色（色盘任选，空串表示默认渐变背景）
    @Published var backgroundHex: String = ""
    /// 自定义背景是否同步到搜索 / 音乐库 / 我的等全部页面
    @Published var backgroundSyncAll = true
    /// 当前使用的背景图片文件路径（空串表示未上传图片）
    @Published var backgroundImagePath: String = ""
    /// 壁纸库：所有已上传壁纸的文件路径
    @Published var wallpaperPaths: [String] = []
    /// 全局 UI 风格：影响玻璃容器、卡片透明度与边框质感
    @Published var uiStyle: BeansUIStyle = .liquid

    private let customAccentKey = "beans.accent.custom"
    private let backgroundKey = "beans.background.custom"
    private let syncAllKey = "beans.background.syncAll"
    private let backgroundImageKey = "beans.background.image"
    private let wallpaperListKey = "beans.wallpapers.list"
    private let wallpaperDataKey = "beans.wallpapers.data"
    private let deletedKey = "beans.wallpapers.deleted"
    private let uiStyleKey = "beans.uiStyle"
    private var wallpapersRestored = false

    private init() {
        accent = BeansAccent(rawValue: UserDefaults.standard.string(forKey: AccentTheme.key) ?? "") ?? .amber
        let savedAccent = UserDefaults.standard.string(forKey: customAccentKey)
        customAccentHex = (savedAccent?.isEmpty ?? true) ? nil : savedAccent
        backgroundHex = UserDefaults.standard.string(forKey: backgroundKey) ?? ""
        backgroundSyncAll = UserDefaults.standard.object(forKey: syncAllKey) as? Bool ?? true
        backgroundImagePath = UserDefaults.standard.string(forKey: backgroundImageKey) ?? ""
        wallpaperPaths = UserDefaults.standard.stringArray(forKey: wallpaperListKey) ?? []
        let savedUIStyle = UserDefaults.standard.string(forKey: uiStyleKey) ?? ""
        uiStyle = savedUIStyle == "outline" ? .clear : (BeansUIStyle(rawValue: savedUIStyle) ?? .liquid)
    }

    /// 在首帧之后恢复壁纸，避免覆盖安装后同步读写大图备份阻塞应用启动。
    func restoreWallpapersIfNeeded() {
        guard !wallpapersRestored else { return }
        wallpapersRestored = true
        restoreWallpapers()
    }

    /// 壁纸自动恢复：
    /// 1. 列表中文件仍在→直接保留；文件丢失但有 base64 备份→重建文件。
    /// 2. 扫描壁纸目录，把残留的 jpg 重新登记。
    /// 3. 当前背景图丢失时优先从备份重建，失败则回退到壁纸库第一张。
    /// 注：已彻底移除旧版“重置即删除背景图”的逻辑（它会导致更新后壁纸消失）。
    private func restoreWallpapers() {
        let dir = Self.wallpaperDirectory()
        var backup = UserDefaults.standard.dictionary(forKey: wallpaperDataKey) as? [String: String] ?? [:]
        let deleted = deletedWallpaperPaths()
        var restored: [String] = []
        for path in wallpaperPaths {
            if deleted.contains(path) { continue }
            if FileManager.default.fileExists(atPath: path) {
                restored.append(path)
                continue
            }
            // 覆盖安装后沙盒容器路径会变：备份重建必须写到当前沙盒的有效路径
            guard let b64 = Self.wallpaperBackupValue(for: path, in: backup),
                  let data = Data(base64Encoded: b64) else { continue }
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            let newPath = Self.wallpaperDirectory().appendingPathComponent(fileName).path
            if (try? data.write(to: URL(fileURLWithPath: newPath), options: .atomic)) != nil {
                restored.append(newPath)
                backup[newPath] = b64
            }
        }
        if let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for name in names where name.hasSuffix(".jpg") {
                let full = dir.appendingPathComponent(name).path
                if deleted.contains(full) { continue }
                if !restored.contains(full) { restored.append(full) }
            }
        }
        wallpaperPaths = restored
        saveWallpaperList()
        if !backgroundImagePath.isEmpty, !deleted.contains(backgroundImagePath) {
            if !FileManager.default.fileExists(atPath: backgroundImagePath),
               let b64 = Self.wallpaperBackupValue(for: backgroundImagePath, in: backup),
               let data = Data(base64Encoded: b64) {
                let fileName = URL(fileURLWithPath: backgroundImagePath).lastPathComponent
                let newPath = Self.wallpaperDirectory().appendingPathComponent(fileName).path
                if (try? data.write(to: URL(fileURLWithPath: newPath), options: .atomic)) != nil {
                    backgroundImagePath = newPath
                    UserDefaults.standard.set(newPath, forKey: backgroundImageKey)
                    backup[newPath] = b64
                }
            }
            if !FileManager.default.fileExists(atPath: backgroundImagePath) {
                backgroundImagePath = wallpaperPaths.first ?? ""
                UserDefaults.standard.set(backgroundImagePath, forKey: backgroundImageKey)
            }
        }
        if !backgroundImagePath.isEmpty,
           FileManager.default.fileExists(atPath: backgroundImagePath),
           !wallpaperPaths.contains(backgroundImagePath),
           !deleted.contains(backgroundImagePath) {
            wallpaperPaths.insert(backgroundImagePath, at: 0)
            saveWallpaperList()
        }
        UserDefaults.standard.set(backup, forKey: wallpaperDataKey)
        invalidateBackgroundCache()
    }

    /// 配置备份恢复后调用：按 UserDefaults 中的壁纸列表与 base64 备份重建壁纸文件
    func reloadWallpapersFromBackup() {
        wallpapersRestored = true
        restoreWallpapers()
    }

    /// 导出配置备份前调用：把当前壁纸文件内容补进 UserDefaults，避免只备份到旧沙盒路径。
    func refreshWallpaperBackupForExport() {
        var backup = UserDefaults.standard.dictionary(forKey: wallpaperDataKey) as? [String: String] ?? [:]
        let candidates = ([backgroundImagePath] + wallpaperPaths).filter { !$0.isEmpty }
        for path in candidates {
            guard FileManager.default.fileExists(atPath: path),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
            backup[path] = data.base64EncodedString()
        }
        UserDefaults.standard.set(backup, forKey: wallpaperDataKey)
    }

    func setUIStyle(_ style: BeansUIStyle) {
        guard uiStyle != style else { return }
        uiStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: uiStyleKey)
    }

    func set(_ newAccent: BeansAccent) {
        guard accent != newAccent else { return }
        accent = newAccent
        UserDefaults.standard.set(newAccent.rawValue, forKey: AccentTheme.key)
    }

    /// 自定义强调色（色盘选色）
    func setCustomAccent(_ hex: String?) {
        let normalized = hex?.isEmpty == true ? nil : hex
        customAccentHex = normalized
        UserDefaults.standard.set(normalized ?? "", forKey: customAccentKey)
    }

    func clearCustomAccent() {
        setCustomAccent(nil)
    }

    /// 自定义背景色
    func setBackground(_ hex: String) {
        backgroundHex = hex
        UserDefaults.standard.set(hex, forKey: backgroundKey)
    }

    func setBackgroundSyncAll(_ on: Bool) {
        backgroundSyncAll = on
        UserDefaults.standard.set(on, forKey: syncAllKey)
    }

    /// 自定义强调色 Color
    var customAccent: Color? {
        guard let customAccentHex else { return nil }
        return Color(hex: customAccentHex)
    }

    /// 自定义背景色 Color
    var customBackground: Color? {
        guard !backgroundHex.isEmpty else { return nil }
        return Color(hex: backgroundHex)
    }

    /// 上传的背景图片（按路径加载，解码结果缓存，避免大图每次重复解码导致卡顿/布局抖动）
    private var cachedBackgroundImage: UIImage?
    var customBackgroundImage: UIImage? {
        if let cached = cachedBackgroundImage { return cached }
        guard !backgroundImagePath.isEmpty else { return nil }
        let image = BeansImageFileCache.image(at: backgroundImagePath)
        cachedBackgroundImage = image
        return image
    }

    private func invalidateBackgroundCache() {
        cachedBackgroundImage = nil
    }

    /// 上传新壁纸：归一化后保存到壁纸库，并直接设为当前背景（覆盖保存当前壁纸）
    func addWallpaper(_ data: Data) {
        let normalized = Self.normalizedWallpaperJPEG(from: data)
        let imageData: Data
        if let normalized, !normalized.isEmpty {
            imageData = normalized
        } else if !data.isEmpty {
            // 归一化失败（如超内存的极端大图）：兜底保存原图，保证上传必生效
            imageData = data
        } else {
            return
        }
        let url = Self.wallpaperDirectory()
            .appendingPathComponent("wallpaper-\(Int(Date().timeIntervalSince1970))-\(Int.random(in: 100...999)).jpg")
        do {
            try imageData.write(to: url, options: .atomic)
            wallpaperPaths.append(url.path)
            saveWallpaperList()
            backgroundImagePath = url.path
            UserDefaults.standard.set(url.path, forKey: backgroundImageKey)
            saveWallpaperBackup(url.path, data: imageData)
            invalidateBackgroundCache()
            BeansImageFileCache.remove(url.path)
        } catch {
            // 保存失败：静默保留当前壁纸
        }
    }

    /// 从壁纸库选择壁纸应用为当前背景（无需再去相册）
    func applyWallpaper(at path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        backgroundImagePath = path
        UserDefaults.standard.set(path, forKey: backgroundImageKey)
        invalidateBackgroundCache()
    }

    /// 删除壁纸库中的某张壁纸；若正在使用则自动切换到上一张/清空
    func deleteWallpaper(at path: String) {
        try? FileManager.default.removeItem(atPath: path)
        BeansImageFileCache.remove(path)
        wallpaperPaths.removeAll { $0 == path }
        removeWallpaperBackup(path)
        saveDeletedWallpaper(path)
        saveWallpaperList()
        if backgroundImagePath == path {
            backgroundImagePath = wallpaperPaths.first ?? ""
            UserDefaults.standard.set(backgroundImagePath, forKey: backgroundImageKey)
            invalidateBackgroundCache()
        }
    }

    /// 清除当前背景（保留壁纸库，可随时重新选择）
    func clearBackgroundImage() {
        backgroundImagePath = ""
        UserDefaults.standard.set("", forKey: backgroundImageKey)
        invalidateBackgroundCache()
    }

    /// 重置设置时清空整套壁纸库与当前背景。
    func clearAllWallpapers() {
        for path in wallpaperPaths {
            try? FileManager.default.removeItem(atPath: path)
            BeansImageFileCache.remove(path)
        }
        if !backgroundImagePath.isEmpty {
            try? FileManager.default.removeItem(atPath: backgroundImagePath)
            BeansImageFileCache.remove(backgroundImagePath)
        }
        wallpaperPaths = []
        backgroundImagePath = ""
        UserDefaults.standard.removeObject(forKey: wallpaperListKey)
        UserDefaults.standard.removeObject(forKey: wallpaperDataKey)
        UserDefaults.standard.removeObject(forKey: deletedKey)
        UserDefaults.standard.set("", forKey: backgroundImageKey)
        invalidateBackgroundCache()
        BeansImageFileCache.removeAll()
    }

    private static func wallpaperDirectory() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BeansWallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func saveWallpaperList() {
        UserDefaults.standard.set(wallpaperPaths, forKey: wallpaperListKey)
    }

    /// base64 备份（UserDefaults 持久化）：覆盖安装导致文件丢失时可自动重建
    private func saveWallpaperBackup(_ path: String, data: Data) {
        var backup = UserDefaults.standard.dictionary(forKey: wallpaperDataKey) as? [String: String] ?? [:]
        backup[path] = data.base64EncodedString()
        UserDefaults.standard.set(backup, forKey: wallpaperDataKey)
    }

    private func removeWallpaperBackup(_ path: String) {
        var backup = UserDefaults.standard.dictionary(forKey: wallpaperDataKey) as? [String: String] ?? [:]
        backup.removeValue(forKey: path)
        UserDefaults.standard.set(backup, forKey: wallpaperDataKey)
    }

    /// 删除标记：删除过的壁纸不会被目录扫描/备份重新拉回（保证删除是永久的）
    private func saveDeletedWallpaper(_ path: String) {
        var set = UserDefaults.standard.stringArray(forKey: deletedKey) ?? []
        if !set.contains(path) { set.append(path) }
        UserDefaults.standard.set(set, forKey: deletedKey)
    }

    private func deletedWallpaperPaths() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: deletedKey) ?? [])
    }

    private static func wallpaperBackupValue(for path: String, in backup: [String: String]) -> String? {
        if let exact = backup[path] { return exact }
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        return backup.first { URL(fileURLWithPath: $0.key).lastPathComponent == fileName }?.value
    }
    /// 归一化背景图：长边统一到 1600px；原图过小时放大到该尺寸并轻度高斯模糊柔化，
    /// 铺满屏幕时既不会像素化，也不会因小图拉伸引发布局/视觉问题
    private static func normalizedWallpaperJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let w = image.size.width
        let h = image.size.height
        guard w > 0, h > 0 else { return nil }
        let target: CGFloat = 1600
        let longest = max(w, h)
        let wasSmall = longest < target
        let scale = target / longest
        let size = CGSize(width: w * scale, height: h * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1 // 固定输出真实像素：长边 1600px，避免高分屏生成 4800px 巨图导致内存/解码异常
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        var result = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        if wasSmall,
           let ci = CIImage(image: result)?.clampedToExtent(),
           let filter = CIFilter(name: "CIGaussianBlur") {
            filter.setValue(ci, forKey: kCIInputImageKey)
            filter.setValue(4, forKey: kCIInputRadiusKey)
            if let output = filter.outputImage?.cropped(to: ci.extent),
               let cg = CIContext().createCGImage(output, from: output.extent) {
                result = UIImage(cgImage: cg)
            }
        }
        return result.jpegData(compressionQuality: 0.8)
    }
}

/// 当前配色读取 / 写入（持久化到 UserDefaults，统一走 ThemeStore）
enum AccentTheme {
    static let key = "beans.accent"

    static var current: BeansAccent {
        ThemeStore.shared.accent
    }

    static func set(_ accent: BeansAccent) {
        ThemeStore.shared.set(accent)
    }
}

// MARK: - 背景氛围渐变（让液态玻璃始终有内容可采样）

extension LinearGradient {
    /// 暖调咖啡色系背景
    static let beansBackdrop = LinearGradient(
        colors: [
            Color(uiColor: .beansBackground),
            Color(uiColor: .beansBackground).opacity(0.72),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// 强调色渐变（跟随配色主题）
    static var beansAccent: LinearGradient {
        LinearGradient(
            colors: AccentTheme.current.gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - 浅色立体阴影（卡片分层质感）

struct BeansCardShadowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat
    var y: CGFloat

    func body(content: Content) -> some View {
        content.shadow(
            color: colorScheme == .dark ? .black.opacity(0.35) : .black.opacity(0.08),
            radius: radius,
            y: y
        )
    }
}

extension View {
    /// 卡片阴影：浅色模式柔和阴影提升层次，深色模式轻微阴影保持立体
    func beansCardShadow(radius: CGFloat = 9, y: CGFloat = 3) -> some View {
        modifier(BeansCardShadowModifier(radius: radius, y: y))
    }
}

// MARK: - 主题模式 ↔ 系统外观

extension BeansThemeMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
// MARK: - 颜色工具（hex 解析 / 明暗调整，供色盘自定义使用）

extension UIColor {
    convenience init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8, let raw = UInt64(value, radix: 16) else { return nil }
        let r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
        if value.count == 8 {
            a = CGFloat((raw >> 24) & 0xFF) / 255
            r = CGFloat((raw >> 16) & 0xFF) / 255
            g = CGFloat((raw >> 8) & 0xFF) / 255
            b = CGFloat(raw & 0xFF) / 255
        } else {
            a = 1
            r = CGFloat((raw >> 16) & 0xFF) / 255
            g = CGFloat((raw >> 8) & 0xFF) / 255
            b = CGFloat(raw & 0xFF) / 255
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "%02X%02X%02X",
            Int(r * 255), Int(g * 255), Int(b * 255)
        )
    }

    func shaded(_ amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let k = max(0, 1 - amount)
        return UIColor(red: r * k, green: g * k, blue: b * k, alpha: a)
    }
}

extension Color {
    init?(hex: String) {
        guard let ui = UIColor(hex: hex) else { return nil }
        self.init(uiColor: ui)
    }

    var hexString: String {
        UIColor(self).hexString
    }
}
