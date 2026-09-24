import SwiftUI

struct VideoDetailPinnedProgressOverlayContent: View {
    let playerViewModel: PlayerStateViewModel?
    let onPrepareSeek: (Double) -> Void

    var body: some View {
        if let playerViewModel {
            VideoDetailPinnedProgressBar(
                playerViewModel: playerViewModel,
                onPrepareSeek: onPrepareSeek
            )
        } else {
            VideoDetailPinnedProgressPlaceholder()
        }
    }
}
