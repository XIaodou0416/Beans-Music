import Foundation
import XCTest
@testable import CiliCiliKit

final class VideoDetailInteractionReliabilityTests: XCTestCase {
    func testManualPageSelectionPreservesExplicitCID() {
        XCTAssertTrue(
            VideoDetailPlaybackHistorySelectionPolicy.preservesManualPage(
                manuallySelectedCID: 202,
                currentCID: 202
            )
        )
        XCTAssertFalse(
            VideoDetailPlaybackHistorySelectionPolicy.preservesManualPage(
                manuallySelectedCID: 101,
                currentCID: 202
            )
        )
    }

    func testLikeConfirmationSurvivesStaleInteractionRefresh() {
        let confirmation = VideoDetailInteractionMutationConfirmation(
            kind: .like,
            state: VideoInteractionState(isLiked: true)
        )
        let staleState = VideoInteractionState(isLiked: false, coinCount: 1, isFavorited: true)

        let reconciled = confirmation.reconciling(staleState)

        XCTAssertTrue(reconciled.isLiked)
        XCTAssertEqual(reconciled.coinCount, 1)
        XCTAssertTrue(reconciled.isFavorited)
    }

    func testCoinConfirmationNeverMovesConfirmedCountBackwards() {
        let confirmation = VideoDetailInteractionMutationConfirmation(
            kind: .coin,
            state: VideoInteractionState(coinCount: 2)
        )

        XCTAssertEqual(
            confirmation.reconciling(VideoInteractionState(coinCount: 1)).coinCount,
            2
        )
        XCTAssertEqual(
            confirmation.reconciling(VideoInteractionState(coinCount: 3)).coinCount,
            3
        )
    }

    func testOnlyAmbiguousMutationFailuresTriggerStateVerification() {
        XCTAssertTrue(
            VideoDetailInteractionReliabilityPolicy.shouldVerifyAmbiguousMutationResult(
                after: URLError(.networkConnectionLost)
            )
        )
        XCTAssertTrue(
            VideoDetailInteractionReliabilityPolicy.shouldVerifyAmbiguousMutationResult(
                after: BiliAPIError.emptyData
            )
        )
        XCTAssertTrue(
            VideoDetailInteractionReliabilityPolicy.shouldVerifyAmbiguousMutationResult(
                after: BiliAPIError.api(code: -500, message: "服务器错误")
            )
        )
        XCTAssertFalse(
            VideoDetailInteractionReliabilityPolicy.shouldVerifyAmbiguousMutationResult(
                after: BiliAPIError.api(code: 34005, message: "硬币不足")
            )
        )
    }

    func testIdempotentMutationRetryPolicyAllowsPostWithoutChangingStandardAPIBehavior() throws {
        let url = try XCTUnwrap(URL(string: "https://api.bilibili.com/x/web-interface/archive/like"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        XCTAssertTrue(BiliNetworkRetryPolicy.idempotentMutation.canRetry(request))
        XCTAssertEqual(BiliNetworkRetryPolicy.idempotentMutation.attempts, 2)
        XCTAssertFalse(BiliNetworkRetryPolicy.api.canRetry(request))
    }
}
