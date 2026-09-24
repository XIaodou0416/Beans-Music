import SwiftUI

struct PlayerNativeControlButtonRow: View {
    let clock: PlayerPlaybackClock
    let metrics: PlayerNativeControlMetrics
    let layout: BiliPlayerControlLayout
    let isPlaying: Bool
    let isDanmakuEnabled: Bool
    let showsDanmakuButton: Bool
    let canToggleFullscreen: Bool
    let isFullscreenActive: Bool
    let controlsAccessory: AnyView?
    let controlsCenterAccessory: AnyView?
    let actions: PlayerNativePlaybackControlsActions

    var body: some View {
        ZStack {
            HStack(spacing: metrics.controlSpacing) {
                if layout.showsPlaybackToggle {
                    PlayerNativeGlassIconButton(
                        systemName: isPlaying ? "pause.fill" : "play.fill",
                        accessibilityLabel: isPlaying ? "暂停" : "播放",
                        metrics: metrics,
                        action: actions.onTogglePlayback
                    )
                }

                if layout.showsTimeLabel {
                    PlayerNativeTimeLabel(clock: clock, metrics: metrics)
                        .frame(
                            width: metrics.timeLabelWidth,
                            height: metrics.controlHeight
                        )
                        .biliPlayerClearGlass(
                            interactive: false,
                            in: Capsule(),
                            isEnabled: true
                        )
                }

                if layout.isLive, let controlsAccessory {
                    controlsAccessory
                        .frame(height: metrics.controlHeight)
                }

                Spacer(minLength: 0)

                if !layout.isLive, let controlsAccessory {
                    controlsAccessory
                        .frame(height: metrics.controlHeight)
                }

                if showsDanmakuButton {
                    PlayerNativeGlassIconButton(
                        systemName: danmakuControlSymbol,
                        accessibilityLabel: "弹幕设置",
                        accessibilityIdentifier: "ui.player.danmaku.toggle",
                        metrics: metrics,
                        action: actions.onToggleDanmaku
                    )
                }

                if canToggleFullscreen {
                    PlayerNativeGlassIconButton(
                        systemName: isFullscreenActive ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                        accessibilityLabel: isFullscreenActive ? "退出全屏" : "全屏",
                        accessibilityIdentifier: "ui.player.fullscreen.toggle",
                        metrics: metrics,
                        action: actions.onToggleFullscreen
                    )
                }
            }

            if let controlsCenterAccessory {
                controlsCenterAccessory
                    .frame(height: metrics.controlHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: metrics.controlHeight)
    }

    private var danmakuControlSymbol: String {
        layout.isLive
            ? "slider.horizontal.3"
            : (isDanmakuEnabled ? "text.bubble.fill" : "text.bubble")
    }
}
