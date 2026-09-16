import XCTest
@testable import Beans

final class LyricParserTests: XCTestCase {
    func testNetEaseYRCUsesAbsoluteWordTimes() {
        let lrc = "[00:01.00]你好"
        let yrc = "[1000,800](1000,300,0)你(1300,500,0)好"
        let line = LyricParser.parse(lrc, wordRaw: yrc, wordFormat: .neteaseYRC).first

        XCTAssertEqual(line?.words?.map(\.text), ["你", "好"])
        XCTAssertEqual(line?.words?.first?.start ?? -1, 1.0, accuracy: 0.001)
        XCTAssertEqual(line?.words?.dropFirst().first?.duration ?? -1, 0.5, accuracy: 0.001)
    }

    func testDecodedQQQRCParsesWordRuns() {
        let qrc = "[2000,900](2000,450,0)hello (2450,450,0)world"
        let line = LyricParser.parse("", wordRaw: qrc, wordFormat: .qqQRC).first

        XCTAssertEqual(line?.text, "hello world")
        XCTAssertEqual(line?.time ?? -1, 2.0, accuracy: 0.001)
        XCTAssertEqual(line?.words?.count, 2)
    }

    func testDecodedKRCParsesRelativeWordOffsets() {
        let krc = "[3000,1000]<0,400,0>你<400,600,0>好"
        let line = LyricParser.parse("", wordRaw: krc, wordFormat: .kugouKRC).first

        XCTAssertEqual(line?.text, "你好")
        XCTAssertEqual(line?.words?.first?.start ?? -1, 3.0, accuracy: 0.001)
        XCTAssertEqual(line?.words?.dropFirst().first?.start ?? -1, 3.4, accuracy: 0.001)
    }

    func testPlainLRCKeepsLineFallback() {
        let lines = LyricParser.parse("[00:01.00]plain line\n[00:03.00]next")

        XCTAssertEqual(lines.count, 2)
        XCTAssertNil(lines.first?.words)
    }

    func testKaraokeOpacityInterpolates() {
        let word = LyricWord(text: "歌", start: 10, duration: 2)

        XCTAssertEqual(LyricKaraokeTiming.opacity(for: word, at: 9), 0.28, accuracy: 0.001)
        XCTAssertEqual(LyricKaraokeTiming.opacity(for: word, at: 11), 0.64, accuracy: 0.001)
        XCTAssertEqual(LyricKaraokeTiming.opacity(for: word, at: 12), 1.0, accuracy: 0.001)
    }
}
