import Foundation
import SwiftUI

enum BilibiliExperience: String, CaseIterable, Identifiable {
    case listen, video
    static let key = "beans.bilibili.experience.v1"
    var id: String { rawValue }
    var title: String { self == .listen ? "听哔哩哔哩" : "看哔哩哔哩" }
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
                 ? "使用原生视频播放器，浏览UP主与合集，参与点赞、投币、收藏和评论。"
                 : "使用音乐播放器听视频，评论区显示对应视频的评论。")
                .font(BeansFont.appFont(12)).foregroundStyle(Color.beansComment)
        }.padding(.vertical, 14).padding(.horizontal, 4)
    }
}
