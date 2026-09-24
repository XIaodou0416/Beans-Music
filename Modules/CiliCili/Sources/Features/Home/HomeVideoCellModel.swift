import Foundation

struct HomeVideoCellModel: Identifiable, Equatable {
    let id: String
    let index: Int
    let video: VideoItem
    let display: VideoCardDisplayModel

    init(video: VideoItem, index: Int) {
        self.id = video.id
        self.index = index
        self.video = video
        self.display = VideoCardDisplayModel(video: video)
    }
}

nonisolated struct HomeVideoCellSignature: Equatable {
    let bvid: String
    let title: String
    let pic: String?
    let duration: Int?
    let pubdate: Int?
    let ownerID: Int?
    let ownerName: String?
    let ownerFace: String?
    let view: Int?
    let width: Int?
    let height: Int?
    let rotate: Int?
    let recommendReason: String?

    init(video: VideoItem) {
        bvid = video.bvid
        title = video.title
        pic = video.pic
        duration = video.duration
        pubdate = video.pubdate
        ownerID = video.owner?.mid
        ownerName = video.owner?.name
        ownerFace = video.owner?.face
        view = video.stat?.view
        width = video.dimension?.width
        height = video.dimension?.height
        rotate = video.dimension?.rotate
        recommendReason = video.recommendReason
    }
}

struct HomeVideoCellCacheEntry {
    let signature: HomeVideoCellSignature
    let cell: HomeVideoCellModel
}
