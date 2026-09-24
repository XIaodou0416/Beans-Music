import XCTest

@testable import CiliCiliKit

final class HomeFeedModeSwitchTests: XCTestCase {
    @MainActor
    func testPopularToRecommendSkipsRefreshWhenContentWasRestored() {
        XCTAssertFalse(
            HomeFeedMode.recommend.requiresRefreshAfterSwitch(
                from: .popular,
                restoredContent: true
            )
        )
    }

    @MainActor
    func testPopularToRecommendRefreshesWithoutRestoredContent() {
        XCTAssertTrue(
            HomeFeedMode.recommend.requiresRefreshAfterSwitch(
                from: .popular,
                restoredContent: false
            )
        )
    }

    @MainActor
    func testRecommendToPopularStillRefreshes() {
        XCTAssertTrue(
            HomeFeedMode.popular.requiresRefreshAfterSwitch(
                from: .recommend,
                restoredContent: true
            )
        )
    }
}
