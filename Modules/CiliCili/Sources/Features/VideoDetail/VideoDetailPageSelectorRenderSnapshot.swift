import Foundation

struct VideoDetailPageSelectorRenderSnapshot: Equatable {
    var pages: [VideoPage] = []
    var selectedCID: Int?
    var pageCountText = "0P"

    var shouldShowPageSelector: Bool {
        pages.count > 1
    }

    init() {}

    init(playback: VideoDetailPlaybackRenderSnapshot) {
        pages = playback.pages
        selectedCID = playback.selectedCID
        pageCountText = "\(playback.pages.count)P"
    }
}
