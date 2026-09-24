import Foundation

nonisolated struct VideoDetailRelatedListSignature: Equatable {
    let items: [VideoDetailRelatedItemSignature]

    init(_ videos: [VideoItem]) {
        items = videos.map(VideoDetailRelatedItemSignature.init)
    }
}
