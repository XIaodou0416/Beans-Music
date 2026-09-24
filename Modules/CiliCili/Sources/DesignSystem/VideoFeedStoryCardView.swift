import SwiftUI

struct VideoFeedStoryCardView: View, Equatable {
    let display: VideoCardDisplayModel
    private let showsHeader: Bool

    init(video: VideoItem, showsHeader: Bool = true) {
        self.display = VideoCardDisplayModel(video: video)
        self.showsHeader = showsHeader
    }

    init(display: VideoCardDisplayModel, showsHeader: Bool = true) {
        self.display = display
        self.showsHeader = showsHeader
    }

    static func == (lhs: VideoFeedStoryCardView, rhs: VideoFeedStoryCardView) -> Bool {
        lhs.display == rhs.display && lhs.showsHeader == rhs.showsHeader
    }

    var body: some View {
        VStack(alignment: .leading, spacing: showsHeader ? 8 : 0) {
            if showsHeader {
                VideoFeedStoryHeader(display: display)
            }

            VideoFeedStoryMediaContainer(display: display)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
