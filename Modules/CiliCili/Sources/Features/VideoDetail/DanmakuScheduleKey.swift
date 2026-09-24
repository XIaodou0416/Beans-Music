import Foundation

struct DanmakuScheduleKey: Equatable {
    let cid: Int
    let segmentIndex: Int
    let includesPreviousSegment: Bool
}
