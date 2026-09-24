import Foundation

struct PlaybackResumeDiagnostics: Equatable {
    let sourceTitle: String
    let targetTime: TimeInterval?
    let cid: Int?
    let statusTitle: String
    let reason: String
    let currentTime: TimeInterval?

    static let none = PlaybackResumeDiagnostics(
        sourceTitle: "无",
        targetTime: nil,
        cid: nil,
        statusTitle: "从头播放",
        reason: "没有可用历史进度",
        currentTime: nil
    )
}
