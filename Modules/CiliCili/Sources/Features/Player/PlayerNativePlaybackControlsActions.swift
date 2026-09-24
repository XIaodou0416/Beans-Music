import Foundation

struct PlayerNativePlaybackControlsActions {
    let onScrubStart: (Double) -> Void
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: (Double) -> Void
    let onScrubCancelled: () -> Void
    let onTogglePlayback: () -> Void
    let onToggleDanmaku: () -> Void
    let onToggleFullscreen: () -> Void
}
