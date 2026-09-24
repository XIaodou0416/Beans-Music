import Foundation

extension HomeFeedPageCoordinator {
    func resetCursor(for mode: HomeFeedMode) {
        switch mode {
        case .recommend:
            if usesNativeAppRecommendSource(for: mode) {
                freshIndex = 0
            } else {
                freshIndex = usesGuestRecommendDiversity(for: mode) ? HomeGuestRecommendState.nextFreshIndex() : 0
            }
        case .popular:
            popularPage = 1
        }
    }

    func advanceRefreshCursor(for mode: HomeFeedMode) {
        switch mode {
        case .recommend:
            if usesNativeAppRecommendSource(for: mode) {
                freshIndex = 0
            } else if usesGuestRecommendDiversity(for: mode) {
                freshIndex = max(freshIndex + 1, HomeGuestRecommendState.nextFreshIndex())
            } else {
                freshIndex += 1
            }
        case .popular:
            popularPage = 1
        }
    }

    func advanceCursor(for mode: HomeFeedMode) {
        switch mode {
        case .recommend:
            if usesNativeAppRecommendSource(for: mode) {
                freshIndex += 1
            } else if usesGuestRecommendDiversity(for: mode) {
                freshIndex = max(freshIndex + 1, HomeGuestRecommendState.nextFreshIndex())
            } else {
                freshIndex += 1
            }
        case .popular:
            popularPage += 1
        }
    }

    func rollbackCursor(for mode: HomeFeedMode) {
        switch mode {
        case .recommend:
            freshIndex = max(0, freshIndex - 1)
        case .popular:
            popularPage = max(1, popularPage - 1)
        }
    }
}
