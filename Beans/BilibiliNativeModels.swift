import Foundation

struct BilibiliVideoInfo {
    let song: Song
    let aid: String
    let owner: Artist
    let description: String
    let views: Int
    let likes: Int
    let coins: Int
    let favorites: Int
    let published: Date
    let parts: [Song]
    let collection: BilibiliSeries?
}
struct BilibiliSeries: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case season, series }
    let number: String
    let ownerID: String
    let ownerName: String
    let title: String
    let cover: URL?
    let description: String
    let count: Int
    let kind: Kind
    var id: String { "\(kind.rawValue):\(ownerID):\(number)" }
}
struct BilibiliUPProfile {
    let artist: Artist
    let sign: String
    let followers: Int
    let following: Bool
}
struct BilibiliReply: Identifiable {
    let id: String
    let author: Artist
    let message: String
    let date: Date
    let likeCount: Int
    let liked: Bool
    let replyCount: Int
}
struct BilibiliReplies {
    let items: [BilibiliReply]
    let total: Int
    let hasMore: Bool
}
struct BilibiliFavoriteFolder: Identifiable {
    let id: String
    let title: String
    let containsVideo: Bool
}
struct BilibiliInteractionState {
    var liked: Bool
    var coins: Int
    var favorited: Bool
}
struct BilibiliLiveRoom: Identifiable, Codable {
    let id: String
    let title: String
    let cover: URL?
    let owner: Artist
    let viewers: String
}
enum BilibiliNativeRoute: Identifiable {
    case video(Song), up(Artist), collection(BilibiliSeries), live(BilibiliLiveRoom)
    var id: String {
        switch self {
        case .video(let s): return s.identityKey
        case .up(let a): return "up:" + a.id
        case .collection(let s): return s.id
        case .live(let r): return "live:" + r.id
        }
    }
}
extension BilibiliChannel {
    var regionID: String {
        switch self {
        case .recommended, .live: return "0"
        case .music: return "3"
        case .game: return "4"
        case .animation: return "1"
        case .knowledge: return "36"
        case .technology: return "188"
        case .life: return "160"
        case .food: return "211"
        case .entertainment: return "5"
        case .dance: return "129"
        }
    }
}
