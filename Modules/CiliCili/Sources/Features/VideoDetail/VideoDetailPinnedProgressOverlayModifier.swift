import SwiftUI

struct VideoDetailPinnedProgressOverlayConfiguration {
    let isPresented: Bool
    let playerWidth: CGFloat?
    let playerViewModel: PlayerStateViewModel?
    let onPrepareSeek: (Double) -> Void
}

private struct VideoDetailPinnedProgressOverlayModifier: ViewModifier {
    let configuration: VideoDetailPinnedProgressOverlayConfiguration

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            VideoDetailPinnedProgressOverlay(
                isPresented: configuration.isPresented,
                playerWidth: configuration.playerWidth,
                playerViewModel: configuration.playerViewModel,
                onPrepareSeek: configuration.onPrepareSeek
            )
        }
    }
}

extension View {
    func videoDetailPinnedProgressOverlay(
        configuration: VideoDetailPinnedProgressOverlayConfiguration
    ) -> some View {
        modifier(VideoDetailPinnedProgressOverlayModifier(configuration: configuration))
    }
}
