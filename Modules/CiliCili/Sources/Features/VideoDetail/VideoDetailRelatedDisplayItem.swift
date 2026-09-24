import Foundation

nonisolated struct VideoDetailRelatedDisplayItem: Identifiable, Equatable {
    let id: String
    let video: VideoItem
    let display: VideoCardDisplayModel

    init(video: VideoItem) {
        id = video.id
        self.video = video
        display = VideoCardDisplayModel(video: video)
    }
}
