import ActivityKit

struct BeansNowPlayingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let isPlaying: Bool
    }

    let songKey: String
    let title: String
    let artist: String
}
