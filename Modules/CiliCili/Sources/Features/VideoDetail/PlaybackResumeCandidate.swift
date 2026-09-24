import Foundation

struct PlaybackResumeCandidate {
    let time: TimeInterval
    let sourceTitle: String
    let reason: String
    let cid: Int?
}
