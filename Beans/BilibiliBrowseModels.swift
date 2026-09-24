import Foundation

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
