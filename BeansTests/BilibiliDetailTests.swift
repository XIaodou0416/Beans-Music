import XCTest
@testable import Beans

@MainActor
final class BilibiliDetailTests: XCTestCase {
    private func reply(_ id: String) -> BilibiliReply {
        BilibiliReply(id: id, author: Artist(id: "1", name: "作者", coverURL: nil, source: .bilibili),
                      message: id, date: .distantPast, likeCount: 0, liked: false, replyCount: 0)
    }

    func testReturningToMountedCommentsDoesNotReloadOrLoseRows() async {
        var requests = 0
        let item = reply("1")
        let store = BilibiliReplyStore { _, _, _, _ in
            requests += 1
            return BilibiliReplies(items: [item], total: 1, hasMore: false)
        }
        await store.load(aid: "1", hot: true, root: nil, reset: true, ifNeeded: true)
        await store.load(aid: "1", hot: true, root: nil, reset: true, ifNeeded: true)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(store.rows.map(\.id), ["1"])
    }

    func testRefreshFailureKeepsAlreadyLoadedComments() async {
        var requests = 0
        let item = reply("1")
        let store = BilibiliReplyStore { _, _, _, _ in
            requests += 1
            if requests > 1 { throw BilibiliError(message: "离线") }
            return BilibiliReplies(items: [item], total: 1, hasMore: false)
        }
        await store.load(aid: "1", hot: true, root: nil, reset: true)
        await store.load(aid: "1", hot: true, root: nil, reset: true)
        XCTAssertEqual(store.rows.map(\.id), ["1"])
        XCTAssertEqual(store.error, "离线")
        XCTAssertFalse(store.loading)
    }

    func testOverlappingRefreshesShareOneRequest() async {
        let started = expectation(description: "request started")
        var finish: CheckedContinuation<BilibiliReplies, Never>?
        var requests = 0
        let store = BilibiliReplyStore { _, _, _, _ in
            requests += 1
            return await withCheckedContinuation { continuation in
                finish = continuation
                started.fulfill()
            }
        }
        let first = Task { await store.load(aid: "1", hot: true, root: nil, reset: true) }
        await fulfillment(of: [started], timeout: 2)
        let joined = expectation(description: "second refresh joined")
        let second = Task {
            joined.fulfill()
            await store.load(aid: "1", hot: true, root: nil, reset: true)
        }
        await fulfillment(of: [joined], timeout: 2)
        finish?.resume(returning: BilibiliReplies(items: [reply("1")], total: 1, hasMore: false))
        await first.value
        await second.value
        XCTAssertEqual(requests, 1)
    }

    func testStaleSortResponseCannotReplaceNewSort() async {
        let started = expectation(description: "hot request started")
        var finish: CheckedContinuation<BilibiliReplies, Never>?
        let newest = reply("new")
        let store = BilibiliReplyStore { _, _, hot, _ in
            if hot {
                return await withCheckedContinuation { continuation in
                    finish = continuation
                    started.fulfill()
                }
            }
            return BilibiliReplies(items: [newest], total: 1, hasMore: false)
        }
        let first = Task { await store.load(aid: "1", hot: true, root: nil, reset: true) }
        await fulfillment(of: [started], timeout: 2)
        await store.load(aid: "1", hot: false, root: nil, reset: true)
        finish?.resume(returning: BilibiliReplies(items: [reply("old")], total: 1, hasMore: false))
        await first.value
        XCTAssertEqual(store.rows.map(\.id), ["new"])
        XCTAssertNil(store.error)
    }

    func testPaginationDeduplicatesOverlappingPages() async {
        let first = reply("1")
        let second = reply("2")
        let store = BilibiliReplyStore { _, page, _, _ in
            BilibiliReplies(items: page == 1 ? [first] : [first, second], total: 2, hasMore: page == 1)
        }
        await store.load(aid: "1", hot: true, root: nil, reset: true)
        await store.load(aid: "1", hot: true, root: nil, reset: false)
        XCTAssertEqual(store.rows.map(\.id), ["1", "2"])
        XCTAssertFalse(store.more)
    }

    func testRefreshDuringPaginationRunsAfterPageCompletes() async {
        let pageStarted = expectation(description: "page request started")
        let refreshStarted = expectation(description: "refresh requested")
        var finishPage: CheckedContinuation<BilibiliReplies, Never>?
        var firstPageRequests = 0
        let old = reply("old")
        let new = reply("new")
        let store = BilibiliReplyStore { _, page, _, _ in
            if page == 1 {
                firstPageRequests += 1
                return BilibiliReplies(items: [firstPageRequests == 1 ? old : new], total: 2, hasMore: true)
            }
            return await withCheckedContinuation { continuation in
                finishPage = continuation
                pageStarted.fulfill()
            }
        }
        await store.load(aid: "1", hot: true, root: nil, reset: true)
        let paging = Task { await store.load(aid: "1", hot: true, root: nil, reset: false) }
        await fulfillment(of: [pageStarted], timeout: 2)
        let refresh = Task {
            refreshStarted.fulfill()
            await store.load(aid: "1", hot: true, root: nil, reset: true)
        }
        await fulfillment(of: [refreshStarted], timeout: 2)
        finishPage?.resume(returning: BilibiliReplies(items: [reply("page2")], total: 2, hasMore: false))
        await paging.value
        await refresh.value
        XCTAssertEqual(firstPageRequests, 2)
        XCTAssertEqual(store.rows.map(\.id), ["new"])
    }

    func testReplyParsingKeepsImagesAndBoundedPreviews() {
        let fixture: [String: Any] = [
            "rpid_str": "100", "rcount": 2,
            "member": ["mid": "3", "uname": "作者"],
            "content": ["message": "正文", "pictures": [["img_src": "https://example.com/image.jpg"]]],
            "replies": [["rpid_str": "101", "content": ["message": "预览"],
                         "replies": [["rpid_str": "102"]]]]
        ]
        let result = BilibiliAPI.commentReply(fixture)
        XCTAssertEqual(result?.pictures.count, 1)
        XCTAssertEqual(result?.previews.first?.message, "预览")
        XCTAssertEqual(result?.previews.first?.previews.count, 0)
        XCTAssertNil(BilibiliAPI.commentReply([:]))
    }

    func testSamePlaybackKeyDoesNotRestartFailedRequestWithoutUserRetry() async {
        let first = expectation(description: "first request")
        let retry = expectation(description: "explicit retry")
        var requests = 0
        let model = BilibiliNativePlayer()
        let loader: () async throws -> [URL] = {
            requests += 1
            if requests == 1 { first.fulfill() } else { retry.fulfill() }
            throw BilibiliError(message: "离线")
        }
        model.open(key: "video|64", loader)
        model.open(key: "video|64", loader)
        await fulfillment(of: [first], timeout: 2)
        model.open(key: "video|64", loader)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(model.error, "离线")
        model.open(key: "video|64", force: true, loader)
        await fulfillment(of: [retry], timeout: 2)
        XCTAssertEqual(requests, 2)
        model.stop()
        XCTAssertNil(model.error)
        XCTAssertFalse(model.loading)
    }

    func testStopDiscardsLatePlaybackFailure() async {
        let started = expectation(description: "playback request")
        let completed = expectation(description: "request completed")
        var finish: CheckedContinuation<Void, Never>?
        let model = BilibiliNativePlayer()
        model.open(key: "video|64") {
            await withCheckedContinuation { continuation in
                finish = continuation
                started.fulfill()
            }
            completed.fulfill()
            throw BilibiliError(message: "late failure")
        }
        await fulfillment(of: [started], timeout: 2)
        model.stop()
        finish?.resume()
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertNil(model.error)
        XCTAssertNil(model.player)
        XCTAssertFalse(model.loading)
        XCTAssertFalse(model.wantsPlayback)
    }
}
