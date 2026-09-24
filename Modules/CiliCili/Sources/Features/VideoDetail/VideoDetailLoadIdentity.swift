import Foundation

enum VideoDetailLoadIdentity: Equatable {
    case bvid(String)
    case aid(Int)

    var metricsMessage: String {
        switch self {
        case .bvid(let bvid):
            return "bvid=\(bvid)"
        case .aid(let aid):
            return "aid=\(aid)"
        }
    }
}
