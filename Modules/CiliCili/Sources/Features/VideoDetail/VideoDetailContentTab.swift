import Foundation

enum VideoDetailContentTab: String, CaseIterable, Identifiable {
    case detail
    case comments

    var id: Self { self }

    var title: String {
        switch self {
        case .detail:
            return "详情"
        case .comments:
            return "评论"
        }
    }

    var systemImage: String {
        switch self {
        case .detail:
            return "text.alignleft"
        case .comments:
            return "bubble.left.and.bubble.right"
        }
    }
}
