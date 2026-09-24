import SwiftUI

struct PlayerNativePlaybackControls: View {
    let clock: PlayerPlaybackClock
    let metrics: PlayerNativeControlMetrics
    let layout: BiliPlayerControlLayout
    let canSeek: Bool
    let isPlaying: Bool
    let isDanmakuEnabled: Bool
    let showsDanmakuButton: Bool
    let canToggleFullscreen: Bool
    let isFullscreenActive: Bool
    let controlsAccessory: AnyView?
    let controlsCenterAccessory: AnyView?
    let progressStyle: PlayerNativeProgressStyle
    let actions: PlayerNativePlaybackControlsActions

    var body: some View {
        GlassEffectContainer(spacing: metrics.groupSpacing) {
            VStack(spacing: metrics.stackSpacing) {
                if layout.showsProgress {
                    PlayerNativeProgressSection(
                        metrics: metrics,
                        clock: clock,
                        canSeek: canSeek,
                        sliderVisualScale: metrics.sliderVisualScale,
                        style: progressStyle,
                        onScrubStart: actions.onScrubStart,
                        onScrubChanged: actions.onScrubChanged,
                        onScrubEnded: actions.onScrubEnded,
                        onScrubCancelled: actions.onScrubCancelled
                    )
                    .id(ObjectIdentifier(clock))
                }

                PlayerNativeControlButtonRow(
                    clock: clock,
                    metrics: metrics,
                    layout: layout,
                    isPlaying: isPlaying,
                    isDanmakuEnabled: isDanmakuEnabled,
                    showsDanmakuButton: showsDanmakuButton,
                    canToggleFullscreen: canToggleFullscreen,
                    isFullscreenActive: isFullscreenActive,
                    controlsAccessory: controlsAccessory,
                    controlsCenterAccessory: controlsCenterAccessory,
                    actions: actions
                )
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .biliLiquidGlassForeground(shadowOpacity: 0.20)
        .controlSize(.mini)
    }
}
