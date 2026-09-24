import XCTest
@testable import CiliCiliKit

final class VideoDetailCommentDeepLinkResolutionTests: XCTestCase {
    func testTargetLookupSkipsExtraPagesWhenTheFirstPageAlreadyContainsTheReply() {
        XCTAssertEqual(
            VideoDetailCommentDeepLinkResolution.additionalPageNumbers(
                replyCount: 120,
                knownReplyIDs: [202],
                targetReplyID: 202
            ),
            []
        )
    }

    func testTargetLookupUsesBoundedFollowUpPages() {
        XCTAssertEqual(
            VideoDetailCommentDeepLinkResolution.additionalPageNumbers(
                replyCount: 60,
                knownReplyIDs: [101],
                targetReplyID: 202
            ),
            [2, 3]
        )
        XCTAssertEqual(
            VideoDetailCommentDeepLinkResolution.additionalPageNumbers(
                replyCount: 500,
                knownReplyIDs: [101],
                targetReplyID: 202
            ),
            Array(2...VideoDetailCommentDeepLinkResolution.maximumTargetSearchPages)
        )
    }

    func testFocusedReplyRequiresTheRequestedSecondaryReply() throws {
        let replies = [try comment(id: 202), try comment(id: 303)]

        XCTAssertEqual(
            VideoDetailCommentDeepLinkResolution.focusedReplyID(
                requestedReplyID: 202,
                rootID: 101,
                replies: replies
            ),
            202
        )
        XCTAssertNil(
            VideoDetailCommentDeepLinkResolution.focusedReplyID(
                requestedReplyID: 404,
                rootID: 101,
                replies: replies
            )
        )
        XCTAssertNil(
            VideoDetailCommentDeepLinkResolution.focusedReplyID(
                requestedReplyID: 101,
                rootID: 101,
                replies: replies
            )
        )
    }

    func testReplyAvailabilityKeepsTheThreadUntilAnEmptyPageIsReached() {
        XCTAssertTrue(
            VideoDetailCommentDeepLinkResolution.hasMoreReplies(
                replyCount: 42,
                loadedReplyCount: 20,
                reachedEmptyPage: false
            )
        )
        XCTAssertFalse(
            VideoDetailCommentDeepLinkResolution.hasMoreReplies(
                replyCount: 42,
                loadedReplyCount: 20,
                reachedEmptyPage: true
            )
        )
        XCTAssertFalse(
            VideoDetailCommentDeepLinkResolution.hasMoreReplies(
                replyCount: 20,
                loadedReplyCount: 20,
                reachedEmptyPage: false
            )
        )
    }

    private func comment(id: Int) throws -> Comment {
        try JSONDecoder().decode(
            Comment.self,
            from: Data(
                """
                {
                  "rpid": \(id),
                  "root": 101,
                  "member": { "uname": "回复者" },
                  "content": { "message": "回复内容" }
                }
                """.utf8
            )
        )
    }
}
