import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }
}

func beansLocalized(_ chinese: String, _ english: String) -> String {
    UserDefaults.standard.string(forKey: "beans.language") == AppLanguage.english.rawValue ? english : chinese
}

func beansPlatformName(_ provider: SearchProvider) -> String {
    switch provider {
    case .netease: return beansLocalized("网易云音乐", "NetEase Cloud Music")
    case .qq: return beansLocalized("QQ音乐", "QQ Music")
    case .kugou: return beansLocalized("酷狗音乐", "Kugou Music")
    }
}

func beansLocalizedSettingValue(_ value: String) -> String {
    guard UserDefaults.standard.string(forKey: "beans.language") == AppLanguage.english.rawValue else { return value }
    switch value {
    case "关闭": return "Off"
    case "开启": return "On"
    case "跟随": return "Follow"
    case "自动": return "Automatic"
    case "默认": return "Default"
    default:
        if value.hasSuffix(" 行") { return String(value.dropLast(2)) + " lines" }
        if value.hasPrefix("提前 ") { return "Advance " + String(value.dropFirst(3)) }
        if value.hasPrefix("延后 ") { return "Delay " + String(value.dropFirst(3)) }
        return value
    }
}
