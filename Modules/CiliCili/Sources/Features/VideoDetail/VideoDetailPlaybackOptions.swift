import Foundation

nonisolated struct VideoDetailPlaybackOptions: Equatable, Sendable {
    var recordsPlaybackHistory = true
    var resumesPlaybackHistory = true
    var usesStartupCaches = true

    static let performanceTest = VideoDetailPlaybackOptions(
        recordsPlaybackHistory: false,
        resumesPlaybackHistory: false,
        usesStartupCaches: false
    )
}
