import Foundation
import ActivityKit

/// App 与 Widget Extension 共用的正在播放数据。
@available(iOS 16.1, *)
struct NowPlayingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var songName: String
        var artist: String
        var coverURL: String?
        var isPlaying: Bool
        var progress: Double
        var duration: Double
        var lyricText: String
    }

    var title: String = "正在播放"
}
