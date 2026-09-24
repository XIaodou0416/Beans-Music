struct VideoDetailDanmakuOverlaySnapshot: Equatable {
    var items: [DanmakuItem] = []
    var itemsRevision = 0
    var isPlaying = false
    var playbackRate = 1.0
    var isEnabled = true
    var hasPresentedPlayback = false
    var isLoadShedding = false
    var settings: DanmakuSettings = .default

    static func == (lhs: VideoDetailDanmakuOverlaySnapshot, rhs: VideoDetailDanmakuOverlaySnapshot) -> Bool {
        lhs.itemsRevision == rhs.itemsRevision
            && lhs.isPlaying == rhs.isPlaying
            && lhs.playbackRate == rhs.playbackRate
            && lhs.isEnabled == rhs.isEnabled
            && lhs.hasPresentedPlayback == rhs.hasPresentedPlayback
            && lhs.isLoadShedding == rhs.isLoadShedding
            && lhs.settings == rhs.settings
    }
}
