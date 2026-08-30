import SwiftUI
import CoreText

/// 全局字体管理：把用户上传的 ttf/otf 复制到 Documents/Fonts 并动态注册，App 重启后自动重新注册
enum FontManager {
    static let storedFontNameKey = "beans.globalFont"
    static let storedGreetingFontNameKey = "beans.homeGreetingFont"

    private static var cachedInstalledFontName: String? = UserDefaults.standard.string(forKey: storedFontNameKey)

    static var installedFontName: String? {
        get { cachedInstalledFontName }
        set {
            cachedInstalledFontName = newValue
            UserDefaults.standard.set(newValue, forKey: storedFontNameKey)
        }
    }

    static var greetingFontName: String? {
        get { UserDefaults.standard.string(forKey: storedGreetingFontNameKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: storedGreetingFontNameKey)
            } else {
                UserDefaults.standard.removeObject(forKey: storedGreetingFontNameKey)
            }
        }
    }

    private static var fontsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Fonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var greetingFontsDirectory: URL {
        let dir = fontsDirectory.appendingPathComponent("Greeting", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 启动时重新注册已安装的字体（覆盖安装后 Documents 保留，字体继续生效）
    static func reinstallIfNeeded() {
        guard installedFontName != nil else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(at: fontsDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files where ["ttf", "otf", "ttc"].contains(file.pathExtension.lowercased()) {
            register(file)
        }
        if greetingFontName != nil,
           let files = try? FileManager.default.contentsOfDirectory(at: greetingFontsDirectory, includingPropertiesForKeys: nil) {
            for file in files where ["ttf", "otf", "ttc"].contains(file.pathExtension.lowercased()) {
                register(file)
            }
        }
    }

    /// 安装用户选择的字体文件（先清空旧字体再复制注册），返回注册成功后的字体名
    @discardableResult
    static func install(from sourceURL: URL) -> String? {
        let file = fontsDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        if let files = try? FileManager.default.contentsOfDirectory(at: fontsDirectory, includingPropertiesForKeys: nil) {
            for f in files { try? FileManager.default.removeItem(at: f) }
        }
        if FileManager.default.fileExists(atPath: file.path) { try? FileManager.default.removeItem(at: file) }
        guard (try? FileManager.default.copyItem(at: sourceURL, to: file)) != nil else { return nil }
        guard let name = register(file) else { return nil }
        installedFontName = name
        return name
    }

    /// 导出字体信息（字体名 + 字体文件数据），供配置备份使用
    static func exportFontData() -> (name: String, data: Data)? {
        guard installedFontName != nil else { return nil }
        guard let files = try? FileManager.default.contentsOfDirectory(at: fontsDirectory, includingPropertiesForKeys: nil) else { return nil }
        for file in files where ["ttf", "otf", "ttc"].contains(file.pathExtension.lowercased()) {
            if let data = try? Data(contentsOf: file) { return (installedFontName ?? "", data) }
        }
        return nil
    }

    /// 从备份恢复字体：清空旧字体 → 写回字体文件 → 重新注册
    @discardableResult
    static func restoreFont(name: String, data: Data) -> Bool {
        clear()
        let file = fontsDirectory.appendingPathComponent("beans-restored-font.ttf")
        do {
            try data.write(to: file, options: .atomic)
        } catch {
            return false
        }
        guard let registered = register(file) else { return false }
        installedFontName = registered
        return true
    }

    static func clear() {
        installedFontName = nil
        if let files = try? FileManager.default.contentsOfDirectory(at: fontsDirectory, includingPropertiesForKeys: nil) {
            for f in files { try? FileManager.default.removeItem(at: f) }
        }
    }

    /// 安装仅用于主页问候语的字体，不影响全局字体。
    @discardableResult
    static func installGreeting(from sourceURL: URL) -> String? {
        let file = greetingFontsDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        if let files = try? FileManager.default.contentsOfDirectory(at: greetingFontsDirectory, includingPropertiesForKeys: nil) {
            for f in files { try? FileManager.default.removeItem(at: f) }
        }
        guard (try? FileManager.default.copyItem(at: sourceURL, to: file)) != nil else { return nil }
        guard let name = register(file) else { return nil }
        greetingFontName = name
        return name
    }

    static func clearGreeting() {
        greetingFontName = nil
        if let files = try? FileManager.default.contentsOfDirectory(at: greetingFontsDirectory, includingPropertiesForKeys: nil) {
            for f in files { try? FileManager.default.removeItem(at: f) }
        }
    }

    @discardableResult
    private static func register(_ url: URL) -> String? {
        // 用 Data 读取避免安全作用域/CGDataProvider(url:) 兼容问题，iOS 上更稳
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let provider = CGDataProvider(data: data as CFData), let font = CGFont(provider) else { return nil }
        var error: Unmanaged<CFError>?
        guard CTFontManagerRegisterGraphicsFont(font, &error) else { return nil }
        return font.postScriptName as String?
    }
}

/// 全局字体快捷入口：已上传字体时全局使用自定义字体，否则回退系统字体（支持 design 回退）
enum BeansFont {
    static func appFont(_ size: CGFloat, _ weight: Font.Weight = .regular, _ design: Font.Design = .default) -> Font {
        if let name = FontManager.installedFontName {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: weight, design: design)
    }

    static func greetingFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if let name = FontManager.greetingFontName {
            return .custom(name, size: size)
        }
        return appFont(size, weight)
    }

    /// UIKit 版字体（UITextField 等 SwiftUI 不覆盖的控件用）
    static func appUIFont(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        if let name = FontManager.installedFontName {
            return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
        }
        return .systemFont(ofSize: size, weight: weight)
    }
}
