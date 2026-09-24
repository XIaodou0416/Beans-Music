import SwiftUI

struct PlaybackNetworkPlayerStatusSection: View {
    let playerViewModel: PlayerStateViewModel?
    let fallbackMessage: String?

    var body: some View {
        if let playerViewModel {
            PlaybackNetworkPlayerSection(
                playerViewModel: playerViewModel,
                fallbackMessage: fallbackMessage
            )
        } else {
            PlaybackNetworkPlayerFallbackSection(fallbackMessage: fallbackMessage)
        }
    }
}
