import Foundation
import SwiftUI

enum BilibiliExperience: String, CaseIterable, Identifiable {
    case listen, video
    static let key = "beans.bilibili.experience.v1"
    var id: String { rawValue }
    var title: String { self == .listen ? "听哔哩哔哩" : "看哔哩哔哩（网页）" }
    static var current: Self { Self(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .listen }
}

enum BilibiliChannel: String, CaseIterable, Identifiable {
    case recommended, live, music, game, animation, knowledge, technology, life, food, entertainment, dance
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recommended: return "推荐"
        case .live: return "直播"
        case .music: return "音乐"
        case .game: return "游戏"
        case .animation: return "动画"
        case .knowledge: return "知识"
        case .technology: return "科技"
        case .life: return "生活"
        case .food: return "美食"
        case .entertainment: return "娱乐"
        case .dance: return "舞蹈"
        }
    }

}

struct BilibiliOfficialPage: Identifiable {
    let url: URL
    let title: String
    var id: String { url.absoluteString }

    static func up(_ id: String) -> Self? {
        guard !id.isEmpty, id.allSatisfy(\.isNumber), let url = URL(string: "https://space.bilibili.com/\(id)") else { return nil }
        return Self(url: url, title: "UP主主页")
    }
    static func collections(_ id: String) -> Self? {
        guard !id.isEmpty, id.allSatisfy(\.isNumber), let url = URL(string: "https://space.bilibili.com/\(id)/lists") else { return nil }
        return Self(url: url, title: "UP主的合集")
    }
    static func video(_ song: Song) -> Self? {
        guard song.source == .bilibili, let url = song.officialURL else { return nil }
        return Self(url: url, title: song.name)
    }
    static func search(_ keyword: String, up: Bool = false) -> Self {
        var url = URLComponents(string: "https://search.bilibili.com/\(up ? "upuser" : "all")")!
        url.queryItems = [URLQueryItem(name: "keyword", value: keyword)]
        return Self(url: url.url!, title: up ? "搜索UP主" : "哔哩哔哩搜索")
    }
}

extension BilibiliChannel {
    var officialURL: URL {
        let path: String
        switch self {
        case .recommended: return URL(string: "https://www.bilibili.com/")!
        case .live: return URL(string: "https://live.bilibili.com/")!
        case .music: path = "music"
        case .game: path = "game"
        case .animation: path = "douga"
        case .knowledge: path = "knowledge"
        case .technology: path = "tech"
        case .life: path = "life"
        case .food: path = "food"
        case .entertainment: path = "ent"
        case .dance: path = "dance"
        }
        return URL(string: "https://www.bilibili.com/v/\(path)/")!
    }
}

struct BilibiliModeSettings: View {
    @AppStorage(BilibiliExperience.key) private var mode = BilibiliExperience.listen.rawValue
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("哔哩哔哩模式", systemImage: "play.rectangle")
                .font(BeansFont.appFont(15)).foregroundStyle(Color.beansLabel)
            Picker("哔哩哔哩模式", selection: $mode) {
                ForEach(BilibiliExperience.allCases) { item in Text(item.title).tag(item.rawValue) }
            }.pickerStyle(.segmented)
            Text(mode == BilibiliExperience.video.rawValue
                 ? "官方网页体验：在应用内看视频、浏览UP主页和合集；点赞、投币、收藏、发评论使用官方网页，需要在网页中登录。不是官方App的完整复刻。"
                 : "使用音乐播放器听视频，评论区显示对应视频的评论。")
                .font(BeansFont.appFont(12)).foregroundStyle(Color.beansComment)
        }.padding(.vertical, 14).padding(.horizontal, 4)
    }
}
