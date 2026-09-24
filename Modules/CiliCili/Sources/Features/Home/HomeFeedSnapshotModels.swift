import Foundation

nonisolated struct HomeFeedSnapshot: Codable {
    let savedAt: Date
    let lastSeenMarkerIndex: Int?
    let videos: [HomeFeedCachedVideo]
}

nonisolated struct HomeFeedSnapshotRestore {
    let videos: [VideoItem]
    let lastSeenMarkerIndex: Int?
}

nonisolated struct HomeFeedCachedVideo: Codable {
    let bvid: String
    let aid: Int?
    let title: String
    let pic: String?
    let desc: String?
    let duration: Int?
    let pubdate: Int?
    let owner: HomeFeedCachedOwner?
    let stat: HomeFeedCachedStat?
    let cid: Int?
    let recommendReason: String?
}

nonisolated struct HomeFeedCachedOwner: Codable {
    let mid: Int
    let name: String
    let face: String?
}

nonisolated struct HomeFeedCachedStat: Codable {
    let view: Int?
    let reply: Int?
    let like: Int?
    let coin: Int?
    let favorite: Int?
}
