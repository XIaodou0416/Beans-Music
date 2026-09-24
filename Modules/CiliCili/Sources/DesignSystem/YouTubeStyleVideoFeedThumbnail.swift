import SwiftUI

struct YouTubeStyleVideoFeedThumbnail: View {
    @Environment(\.showsVideoCoverDurationBadges) private var showsVideoCoverDurationBadges
    let display: VideoCardDisplayModel
    let showsPlayBadge: Bool
    let coverAspectRatio: CGFloat
    let fixedCoverSize: CGSize?
    let coverMaximumPixelLength: Int
    let coverShadowLevel: MediaShadowLevel
    @State private var coverLoadedState = VideoCoverLoadedState()

    var body: some View {
        Color.clear
            .aspectRatio(coverAspectRatio, contentMode: .fit)
            .overlay {
                ZStack(alignment: .bottomTrailing) {
                    AdaptiveVideoCoverImage(
                        display: display,
                        style: .maxSide,
                        fixedSize: fixedCoverSize,
                        maximumPixelLength: coverMaximumPixelLength,
                        onPhaseChange: { phase in
                            coverLoadedState.update(phase: phase, identity: display.coverLoadIdentity)
                        }
                    )

                    if coverLoadedState.isLoaded(identity: display.coverLoadIdentity) {
                        thumbnailBottomScrim
                        playBadge
                        durationBadge
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            .frame(maxWidth: .infinity)
            .videoCoverSurface(cornerRadius: 18, shadowLevel: coverShadowLevel)
    }

    @ViewBuilder
    private var thumbnailBottomScrim: some View {
        if showsPlayBadge || (showsVideoCoverDurationBadges && !display.durationText.isEmpty) {
            VideoCoverBottomScrim()
        }
    }

    @ViewBuilder
    private var playBadge: some View {
        if showsPlayBadge {
            VideoCoverPlayBadge(size: 40, iconSize: 15)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }

    @ViewBuilder
    private var durationBadge: some View {
        if showsVideoCoverDurationBadges, !display.durationText.isEmpty {
            VideoCoverDurationBadge(display.durationText)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }
}
