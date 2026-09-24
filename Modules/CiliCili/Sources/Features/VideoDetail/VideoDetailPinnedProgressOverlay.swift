import SwiftUI

struct VideoDetailPinnedProgressOverlay: View {
    let isPresented: Bool
    let playerWidth: CGFloat?
    let playerViewModel: PlayerStateViewModel?
    let onPrepareSeek: (Double) -> Void

    var body: some View {
        if isPresented {
            VideoDetailPinnedProgressOverlayContent(
                playerViewModel: playerViewModel,
                onPrepareSeek: onPrepareSeek
            )
                .frame(width: playerWidth)
                .frame(maxWidth: .infinity)
                .frame(height: VideoDetailPinnedProgressBar.height)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}
