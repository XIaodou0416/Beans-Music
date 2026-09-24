import XCTest
@testable import CiliCiliKit

final class VideoDetailCommentAuthorIdentityTests: XCTestCase {
    func testCommentMemberBuildsRouteableOwnerFromValidMID() throws {
        let member = try decodeMember(mid: "12345", name: "评论作者")

        XCTAssertEqual(member.videoOwner?.mid, 12345)
        XCTAssertEqual(member.videoOwner?.name, "评论作者")
        XCTAssertEqual(member.videoOwner?.face, "https://example.com/avatar.jpg")
    }

    func testCommentMemberRejectsInvalidMIDForProfileNavigation() throws {
        XCTAssertNil(try decodeMember(mid: "0", name: "评论作者").videoOwner)
        XCTAssertNil(try decodeMember(mid: "not-a-mid", name: "评论作者").videoOwner)
    }

    func testDisplayModelMarksOnlyTheCurrentVideoUploader() throws {
        let comment = try JSONDecoder().decode(
            Comment.self,
            from: Data(
                """
                {
                  "rpid": 1,
                  "member": {
                    "mid": "12345",
                    "uname": "视频UP主",
                    "avatar": "https://example.com/avatar.jpg"
                  }
                }
                """.utf8
            )
        )
        let display = VideoDetailCommentDisplayModel(comment: comment)

        XCTAssertTrue(display.isVideoUploader(ownerMID: 12345))
        XCTAssertFalse(display.isVideoUploader(ownerMID: 54321))
        XCTAssertFalse(display.isVideoUploader(ownerMID: nil))
    }

    @MainActor
    func testDynamicCommentDisplayRetainsTheCommentAuthorOwner() throws {
        let comment = try JSONDecoder().decode(
            Comment.self,
            from: Data(
                """
                {
                  "rpid": 1,
                  "member": {
                    "mid": "12345",
                    "uname": "动态作者",
                    "avatar": "https://example.com/avatar.jpg"
                  }
                }
                """.utf8
            )
        )
        let display = DynamicCommentRowDisplayModel(comment: comment)

        XCTAssertEqual(display.authorOwner?.mid, 12345)
        XCTAssertEqual(display.authorOwner?.name, "动态作者")
    }

    private func decodeMember(mid: String, name: String) throws -> CommentMember {
        try JSONDecoder().decode(
            CommentMember.self,
            from: Data(
                """
                {
                  "mid": "\(mid)",
                  "uname": "\(name)",
                  "avatar": "https://example.com/avatar.jpg"
                }
                """.utf8
            )
        )
    }
}
