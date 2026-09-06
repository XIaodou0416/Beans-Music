import XCTest
@testable import Beans

final class RecommendationServiceTests: XCTestCase {
    func testNewSongParsing() {
        let json: [String: Any] = [
            "data": [
                "songs": [[
                    "songmid": "new-mid",
                    "songname": "New Song",
                    "singer": [["singerMID": "artist-1", "singerName": "Artist"]],
                    "album": ["name": "Album", "mid": "album-1"],
                    "interval": 215,
                    "payplay": 0
                ]]
            ]
        ]

        let songs = RecommendationService.parseSongs(from: json)
        XCTAssertEqual(songs.count, 1)
        XCTAssertEqual(songs.first?.name, "New Song")
        XCTAssertEqual(songs.first?.artists, "Artist")
        XCTAssertEqual(songs.first?.source, .qq)
        XCTAssertEqual(songs.first?.duration ?? 0, 215, accuracy: 0.01)
    }

    func testPlaylistParsing() {
        let json: [String: Any] = [
            "result": [
                "songlists": [[
                    "dissid": "1001",
                    "dissname": "Recommended List",
                    "logo": "https://example.com/cover.jpg",
                    "song_cnt": 25
                ]]
            ]
        ]

        let playlists = RecommendationService.parsePlaylists(from: json)
        XCTAssertEqual(playlists.count, 1)
        XCTAssertEqual(playlists.first?.id, 1001)
        XCTAssertEqual(playlists.first?.name, "Recommended List")
        XCTAssertEqual(playlists.first?.trackCount, 25)
        XCTAssertEqual(playlists.first?.source, .qq)
    }

    func testPlaylistDetailParsing() {
        let json: [String: Any] = [
            "data": [
                "songlist": [
                    ["id": 1, "songname": "First", "songmid": "mid-1", "interval": 180],
                    ["id": 2, "songname": "Second", "songmid": "mid-2", "interval": 200]
                ]
            ]
        ]

        let songs = RecommendationService.parseSongs(from: json)
        XCTAssertEqual(songs.map(\.name), ["First", "Second"])
        XCTAssertEqual(songs.map(\.qqMid), ["mid-1", "mid-2"])
    }

    func testRadarPageParsingAndDeduplication() {
        let json: [String: Any] = [
            "hasMore": true,
            "data": [
                "records": [
                    ["id": 7, "name": "Radar A", "mid": "radar-a", "duration": 120000],
                    ["id": 7, "name": "Radar A", "mid": "radar-a", "duration": 120000],
                    ["id": 8, "name": "Radar B", "mid": "radar-b", "duration": 130000]
                ]
            ]
        ]

        let songs = RecommendationService.parseSongs(from: json)
        XCTAssertEqual(songs.count, 2)
        XCTAssertEqual(songs.map(\.name), ["Radar A", "Radar B"])
    }

    func testArtistParsing() {
        let json: [String: Any] = [
            "artists": [
                ["singerMID": "s1", "singerName": "One", "pic": "https://example.com/one.jpg"],
                ["singerMID": "s2", "singerName": "Two"]
            ]
        ]

        let artists = RecommendationService.parseArtists(from: json)
        XCTAssertEqual(artists.map(\.name), ["One", "Two"])
        XCTAssertEqual(artists.map(\.source), [.qq, .qq])
    }
}
