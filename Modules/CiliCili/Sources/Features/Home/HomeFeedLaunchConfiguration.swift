import Foundation

struct HomeFeedLaunchConfiguration {
    let autoOpenDetail: Bool
    let startVideo: VideoItem?
    let onVideoSelect: ((VideoItem) -> Void)?
}
