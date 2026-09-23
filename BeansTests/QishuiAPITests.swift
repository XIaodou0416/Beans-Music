import XCTest
@testable import Beans

final class QishuiAPITests: XCTestCase {
    func testCoverURLReadsNestedURLLists() {
        let value: [String: Any] = [
            "uri": "tos-cn-qishui-cover",
            "urls": ["https://cdn.example.com/cover.jpg"],
        ]

        XCTAssertEqual(QishuiResourceURL.first(in: value)?.absoluteString, "https://cdn.example.com/cover.jpg")
    }

    func testCoverURLRejectsNonHTTPValuesAndAcceptsProtocolRelativeURLs() {
        XCTAssertNil(QishuiResourceURL.first(in: "tos-cn-qishui-cover"))
        XCTAssertEqual(QishuiResourceURL.first(in: "//cdn.example.com/cover.jpg")?.absoluteString, "https://cdn.example.com/cover.jpg")
    }

    func testQishuiPlaylistCoverCombinesURIAndImageTemplate() {
        let playlist: [String: Any] = [
            "cover_url": "https://p3-luna.douyinpic.com/img/",
            "raw": [
                "url_cover": [
                    "uri": "ies-music/pgc_cover_123",
                    "urls": [
                        "https://p3-luna.douyinpic.com/img/",
                        "https://p6-luna.douyinpic.com/img/",
                    ],
                    "template_prefix": "tplv-b829550vbb",
                ],
            ],
        ]

        XCTAssertEqual(
            QishuiResourceURL.playlistCover(in: playlist)?.absoluteString,
            "https://p3-luna.douyinpic.com/img/ies-music/pgc_cover_123~tplv-b829550vbb-crop-center:720:720.jpg"
        )
    }

    func testQishuiSongImageURLKeepsItsOriginalImagePath() {
        XCTAssertEqual(
            QishuiResourceURL.first(in: "https://p3-luna.douyinpic.com/img/ies-music/pgc_cover_123")?.absoluteString,
            "https://p3-luna.douyinpic.com/img/ies-music/pgc_cover_123"
        )
    }

    func testQishuiTrackCoverUsesOriginalAlbumTemplateMetadata() {
        let albumCover: [String: Any] = [
            "uri": "tos-cn-v-2774c002/cover-id",
            "urls": ["https://p3-luna.douyinpic.com/img/"],
            "template_prefix": "tplv-b829550vbb",
        ]

        XCTAssertEqual(
            QishuiResourceURL.first(in: albumCover)?.absoluteString,
            "https://p3-luna.douyinpic.com/img/tos-cn-v-2774c002/cover-id~tplv-b829550vbb-crop-center:720:720.jpg"
        )
    }

    func testQishuiPlaylistCoverRepairsFlatURLUsingRawTemplateMetadata() {
        let playlist: [String: Any] = [
            "cover_url": "https://p3-luna.douyinpic.com/img/tos-cn-i-b829550vbb/cover-id",
            "raw": [
                "url_cover": [
                    "uri": "tos-cn-i-b829550vbb/cover-id",
                    "urls": ["https://p3-luna.douyinpic.com/img/"],
                    "template_prefix": "tplv-b829550vbb",
                ],
            ],
        ]

        XCTAssertEqual(
            QishuiResourceURL.playlistCover(in: playlist)?.absoluteString,
            "https://p3-luna.douyinpic.com/img/tos-cn-i-b829550vbb/cover-id~tplv-b829550vbb-crop-center:720:720.jpg"
        )
    }

    func testSearchPageStateUsesPublicCatalogOffset() {
        let state = QishuiSearchPageState.resolve(
            ["has_more": true, "next_offset": 50],
            currentOffset: 0,
            receivedCount: 50
        )

        XCTAssertTrue(state.hasMore)
        XCTAssertEqual(state.nextOffset, 50)
    }

    func testSearchPageStateFallsBackToTheNextPageSize() {
        let state = QishuiSearchPageState.resolve(
            ["upstream": ["has_more": true, "cursor": 0]],
            currentOffset: 20,
            receivedCount: 20
        )

        XCTAssertTrue(state.hasMore)
        XCTAssertEqual(state.nextOffset, 40)
    }

    func testSearchPageStateReadsNestedUpstreamMetadata() {
        let state = QishuiSearchPageState.resolve(
            ["upstream": ["data": ["has_more": true, "next_cursor": "60"]]],
            currentOffset: 30,
            receivedCount: 30
        )

        XCTAssertTrue(state.hasMore)
        XCTAssertEqual(state.nextOffset, 60)
    }
}
