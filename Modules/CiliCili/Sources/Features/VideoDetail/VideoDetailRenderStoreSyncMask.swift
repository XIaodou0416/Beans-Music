import Foundation

struct VideoDetailRenderStoreSyncMask: OptionSet {
    let rawValue: Int

    static let interaction = VideoDetailRenderStoreSyncMask(rawValue: 1 << 0)
    static let playback = VideoDetailRenderStoreSyncMask(rawValue: 1 << 1)
    static let favoriteFolder = VideoDetailRenderStoreSyncMask(rawValue: 1 << 2)
    static let danmakuSettings = VideoDetailRenderStoreSyncMask(rawValue: 1 << 3)
    static let networkDiagnostics = VideoDetailRenderStoreSyncMask(rawValue: 1 << 4)
    static let description = VideoDetailRenderStoreSyncMask(rawValue: 1 << 5)
    static let playerIdentity = VideoDetailRenderStoreSyncMask(rawValue: 1 << 6)
    static let danmaku = VideoDetailRenderStoreSyncMask(rawValue: 1 << 7)
}
