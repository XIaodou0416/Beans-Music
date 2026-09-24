import SwiftUI

struct VideoDetailPlayerSurfaceDanmakuLayer: View {
    let store: VideoDetailDanmakuRenderStore
    let playerViewModel: PlayerStateViewModel
    let usesLandscapePlaybackChrome: Bool
    let isLayoutTransitioning: Bool
    let onPlaybackTime: (TimeInterval, Bool) -> Void

    var body: some View {
        VideoDetailDanmakuOverlay(
            store: store,
            playerViewModel: playerViewModel,
            clock: playerViewModel.playbackClock,
            usesLandscapePlaybackChrome: usesLandscapePlaybackChrome,
            isLayoutTransitioning: isLayoutTransitioning,
            onPlaybackTime: onPlaybackTime
        )
    }
}
