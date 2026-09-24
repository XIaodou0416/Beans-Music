import SwiftUI

private struct VideoDetailDanmakuOverlayLifecycleModifier: ViewModifier {
    let playerViewModel: PlayerStateViewModel
    let isEnabled: Bool
    let actions: VideoDetailDanmakuOverlayLifecycleActions

    func body(content: Content) -> some View {
        content
            .onAppear(perform: actions.bindAndReportPlaybackTime)
            .onChange(of: ObjectIdentifier(playerViewModel)) { _, _ in
                actions.bindAndReportPlaybackTime()
            }
            .onChange(of: isEnabled) { _, isEnabled in
                guard isEnabled else { return }
                actions.reportPlaybackTime()
            }
            .onDisappear(perform: actions.unbind)
    }
}

extension View {
    func videoDetailDanmakuOverlayLifecycle(
        store: VideoDetailDanmakuRenderStore,
        playerViewModel: PlayerStateViewModel,
        clock: PlayerPlaybackClock,
        isEnabled: Bool,
        state: VideoDetailDanmakuOverlayState,
        onPlaybackTime: @escaping (TimeInterval, Bool) -> Void
    ) -> some View {
        modifier(
            VideoDetailDanmakuOverlayLifecycleModifier(
                playerViewModel: playerViewModel,
                isEnabled: isEnabled,
                actions: VideoDetailDanmakuOverlayLifecycleActions(
                    store: store,
                    playerViewModel: playerViewModel,
                    clock: clock,
                    state: state,
                    onPlaybackTime: onPlaybackTime
                )
            )
        )
    }
}
