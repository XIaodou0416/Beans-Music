import Foundation

struct HomeFeedCellStore {
    private var cache: [String: HomeVideoCellCacheEntry] = [:]

    mutating func update(with videos: [VideoItem]) -> [HomeVideoCellModel] {
        var nextCache = [String: HomeVideoCellCacheEntry]()
        nextCache.reserveCapacity(videos.count)
        let cells = videos.enumerated().map { index, video in
            let signature = HomeVideoCellSignature(video: video)
            if let cached = cache[video.id],
               cached.signature == signature,
               cached.cell.index == index {
                nextCache[video.id] = cached
                return cached.cell
            }
            let cell = HomeVideoCellModel(video: video, index: index)
            nextCache[video.id] = HomeVideoCellCacheEntry(signature: signature, cell: cell)
            return cell
        }
        cache = nextCache
        return cells
    }
}
