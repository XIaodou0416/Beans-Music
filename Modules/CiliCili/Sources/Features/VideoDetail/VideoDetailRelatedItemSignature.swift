import Foundation

nonisolated struct VideoDetailRelatedItemSignature: Equatable {
    let id: String
    let title: String
    let coverURL: String?
    let duration: Int?
    let ownerID: Int?
    let ownerName: String?
    let viewCount: Int?
    let pubdate: Int?

    init(_ video: VideoItem) {
        id = video.id
        title = video.title
        coverURL = video.pic
        duration = video.duration
        ownerID = video.owner?.mid
        ownerName = video.owner?.name
        viewCount = video.stat?.view
        pubdate = video.pubdate
    }
}
