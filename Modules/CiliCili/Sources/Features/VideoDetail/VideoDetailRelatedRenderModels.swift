import Foundation

struct VideoDetailRelatedRenderSnapshot: Equatable {
    var related: [VideoItem] = [] {
        didSet {
            relatedItems = related.map(VideoDetailRelatedDisplayItem.init(video:))
            relatedSignature = VideoDetailRelatedListSignature(related)
        }
    }
    var relatedItems: [VideoDetailRelatedDisplayItem] = []
    private var relatedSignature = VideoDetailRelatedListSignature([])
    var state: LoadingState = .idle
    var lastLoadTimedOut = false

    init() {}

    init(
        related: [VideoItem],
        state: LoadingState,
        lastLoadTimedOut: Bool
    ) {
        self.related = related
        relatedItems = related.map(VideoDetailRelatedDisplayItem.init(video:))
        relatedSignature = VideoDetailRelatedListSignature(related)
        self.state = state
        self.lastLoadTimedOut = lastLoadTimedOut
    }

    var changeSignature: VideoDetailRelatedRenderChangeSignature {
        VideoDetailRelatedRenderChangeSignature(
            relatedSignature: relatedSignature,
            state: state,
            lastLoadTimedOut: lastLoadTimedOut
        )
    }
}
