import Foundation

enum HomeFeedMode: String, CaseIterable, Hashable, Identifiable {
    case recommend
    case popular

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommend:
            return "推荐"
        case .popular:
            return "热门"
        }
    }

    var systemImage: String {
        switch self {
        case .recommend:
            return "wand.and.stars.inverse"
        case .popular:
            return "chart.line.uptrend.xyaxis"
        }
    }

    func requiresRefreshAfterSwitch(
        from previousMode: HomeFeedMode,
        restoredContent: Bool
    ) -> Bool {
        !(previousMode == .popular && self == .recommend && restoredContent)
    }
}
