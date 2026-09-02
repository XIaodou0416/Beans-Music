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

func beansChartName(_ name: String) -> String {
    guard UserDefaults.standard.string(forKey: "beans.language") == AppLanguage.english.rawValue else { return name }
    let replacements: [(String, String)] = [
        ("巅峰榜·流行指数", "Peak Chart · Popularity"),
        ("巅峰榜·网络歌曲", "Peak Chart · Online Songs"),
        ("巅峰榜·影视金曲", "Peak Chart · Soundtracks"),
        ("巅峰榜·说唱", "Peak Chart · Rap"),
        ("巅峰榜·国风", "Peak Chart · Chinese Style"),
        ("巅峰榜·音乐人", "Peak Chart · Musicians"),
        ("巅峰榜·电音", "Peak Chart · Electronic"),
        ("巅峰榜·MV", "Peak Chart · Music Videos"),
        ("巅峰榜·K歌金曲", "Peak Chart · Karaoke Gold"),
        ("巅峰榜·韩国", "Peak Chart · Korean Music"),
        ("巅峰榜·日本", "Peak Chart · Japanese Music"),
        ("巅峰榜·热歌", "Peak Chart · Hot Songs"),
        ("巅峰榜·新歌", "Peak Chart · New Songs"),
        ("巅峰榜·欧美", "Peak Chart · Western Music"),
        ("巅峰榜·内地", "Peak Chart · Mainland China"),
        ("巅峰榜·港台", "Peak Chart · Hong Kong & Taiwan"),
        ("酷狗TOP500", "Kugou TOP 500"),
        ("网络红歌榜", "Viral Songs"),
        ("网络热歌榜", "Online Hot Songs"),
        ("TOP500", "TOP 500"),
        ("视频号热歌酷狗榜", "WeChat Channels Hot Songs"),
        ("短视频收藏人气榜", "Short-video Favorites"),
        ("JOOX香港热歌榜", "JOOX Hong Kong Hot Songs"),
        ("80后热歌榜", "Post-80s Hot Songs"),
        ("90后热歌榜", "Post-90s Hot Songs"),
        ("KKBOX风云榜", "KKBOX Chart"),
        ("R&B榜", "R&B Chart"),
        ("DJ热歌榜", "DJ Hot Songs"),
        ("欧美金曲榜", "Western Gold Songs"),
        ("华语新歌榜", "Chinese New Songs"),
        ("抖音热歌榜", "Douyin Hot Songs"),
        ("电音热歌榜", "Electronic Hot Songs"),
        ("电音榜", "Electronic Music"),
        ("动漫音乐榜", "Anime Music"),
        ("动漫榜", "Anime Music"),
        ("古风音乐榜", "Ancient-style Music"),
        ("经典老歌榜", "Classic Songs"),
        ("KTV点唱榜", "KTV Favorites"),
        ("综艺新歌榜", "Variety Show New Songs"),
        ("粤语歌曲榜", "Cantonese Songs"),
        ("粤语金曲榜", "Cantonese Gold Songs"),
        ("抖音榜", "Douyin Chart"),
        ("短视频热歌榜", "Short-video Hot Songs"),
        ("说唱榜", "Rap Songs"),
        ("国风榜", "Chinese Style Songs"),
        ("国潮音乐榜", "Chinese Trend Music"),
        ("国风热歌榜", "Chinese Style Hot Songs"),
        ("国乐榜", "Chinese Instrumental Music"),
        ("香港地区榜", "Hong Kong Chart"),
        ("台湾地区榜", "Taiwan Chart"),
        ("韩国榜", "Korean Chart"),
        ("日本榜", "Japanese Chart"),
        ("内地榜", "Mainland China Chart"),
        ("DJ舞曲榜", "DJ Dance Chart"),
        ("听歌识曲榜", "Song Recognition Chart"),
        ("游戏音乐榜", "Game Music"),
        ("有声榜", "Audio Chart"),
        ("纯音乐榜", "Instrumental Music"),
        ("民谣榜", "Folk Music"),
        ("伤感榜", "Heartbreak Songs"),
        ("百万收藏榜", "Million Favorites"),
        ("说唱先锋榜", "Rap Rising"),
        ("摇滚榜", "Rock Songs"),
        ("ACG新歌榜", "ACG New Songs"),
        ("热歌榜", "Hot Songs"), ("新歌榜", "New Songs"), ("飙升榜", "Rising Songs"),
        ("原创榜", "Original Songs"), ("欧美榜", "Western Music"), ("华语榜", "Chinese Music"),
        ("ACG音乐榜", "ACG Music"), ("流行指数榜", "Popularity Chart"), ("巅峰榜", "Peak Chart")
    ]
    var result = name
    for (chinese, english) in replacements where result.contains(chinese) {
        result = result.replacingOccurrences(of: chinese, with: english)
    }
    return result
}

func beansChartSubtitle(_ subtitle: String) -> String {
    guard !subtitle.isEmpty else { return subtitle }
    guard UserDefaults.standard.string(forKey: "beans.language") == AppLanguage.english.rawValue else { return subtitle }
    let replacements: [(String, String)] = [
        ("周五凌晨更新周榜", "Weekly, updated early Friday"),
        ("周四更新", "Updated Thursday"),
        ("每日更新", "Updated daily"),
        ("每天", "Updated daily"),
        ("每周更新", "Updated weekly"),
        ("每月更新", "Updated monthly"),
        ("工作日", "Updated on weekdays"),
        ("周一", "Updated Monday"),
        ("周三", "Updated Wednesday"),
        ("周四", "Updated Thursday"),
        ("每年年底", "Updated at year end"),
        ("官方热门榜单", "Official popular chart"),
        ("酷狗官网热门榜单", "Kugou popular chart"),
        ("QQ 峰尖榜", "QQ Music Peak Chart"),
        ("峰尖榜", "Peak Chart")
    ]
    var result = subtitle
    for (chinese, english) in replacements where result.contains(chinese) {
        result = result.replacingOccurrences(of: chinese, with: english)
    }
    return result
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
