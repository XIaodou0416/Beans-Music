import XCTest
import CiliCiliKit
@testable import Beans

@MainActor
final class BilibiliDetailTests: XCTestCase {
    private func song(_ id: String) -> Song {
        Song(id: 1, name: "测试", artists: "UP", album: "", coverURL: nil,
             duration: 0, source: .bilibili, bilibiliID: id)
    }

    func testVideoRoutePreservesExplicitCID() {
        XCTAssertEqual(BilibiliNativeRoute.video(song("BV1RHaw6mEDR:456")).ciliCiliRoute,
                       .video(bvid: "BV1RHaw6mEDR", title: "测试", cover: nil, cid: 456))
    }

    func testVideoRouteWithoutPartDoesNotInventCID() {
        XCTAssertEqual(BilibiliNativeRoute.video(song("BV1RHaw6mEDR")).ciliCiliRoute,
                       .video(bvid: "BV1RHaw6mEDR", title: "测试", cover: nil, cid: nil))
    }

    func testUPRouteUsesOriginalCiliCiliDestination() {
        XCTAssertEqual(BilibiliNativeRoute.up(Artist(id: "123", name: "作者", coverURL: nil, source: .bilibili)).ciliCiliRoute,
                       .uploader(mid: 123, name: "作者", avatar: nil))
    }

    func testPresentationOwnershipIsIdempotentAndIndependent() {
        let state = BilibiliPresentationState()
        state.enterVideo("home")
        state.enterVideo("home")
        state.enterVideo("history")
        XCTAssertEqual(state.activeVideoIDs.count, 2)
        state.leaveVideo("home")
        XCTAssertTrue(state.isVideoDetailActive)
        state.leaveVideo("history")
        XCTAssertFalse(state.isVideoDetailActive)
    }
}
