import SwiftUI

struct VideoDetailActionStripOwnerAvatar: View {
    let owner: VideoOwner?

    var body: some View {
        PlaybackDetailOwnerAvatar(
            owner: owner,
            side: VideoDetailActionStrip.Metrics.avatarImageSide,
            pixelSize: VideoDetailActionStrip.Metrics.avatarPixelSize
        )
    }
}
