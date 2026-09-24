import SwiftUI

struct VideoFeedStoryMediaContainer: View {
    @Environment(\.showsVideoCoverDurationBadges) private var showsVideoCoverDurationBadges
    let display: VideoCardDisplayModel
    @State private var coverLoadedState = VideoCoverLoadedState()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover

            StableVideoTitleText(display.title, style: .feedStory)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(.separator).opacity(0.10), lineWidth: 0.6)
        }
        .mediaShadow(.regular)
    }

    private var cover: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 16,
            topTrailingRadius: 16,
            style: .continuous
        )

        return Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                ZStack(alignment: .bottom) {
                    AdaptiveVideoCoverImage(
                        display: display,
                        style: .exactCrop,
                        onPhaseChange: { phase in
                            coverLoadedState.update(phase: phase, identity: display.coverLoadIdentity)
                        }
                    )

                    if coverLoadedState.isLoaded(identity: display.coverLoadIdentity) {
                        coverBottomScrim
                        coverMetaOverlay
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(shape)
            .unifiedVideoCoverBorder(in: shape)
    }

    private var coverMetaOverlay: some View {
        HStack(spacing: 8) {
            if !display.viewText.isEmpty {
                VideoCoverGlassBadge {
                    Label(display.viewText, systemImage: "play.fill")
                        .labelStyle(.titleAndIcon)
                }
            }

            Spacer(minLength: 8)

            if showsVideoCoverDurationBadges, !display.durationText.isEmpty {
                VideoCoverDurationBadge(display.durationText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .clipped()
    }

    @ViewBuilder
    private var coverBottomScrim: some View {
        if !display.viewText.isEmpty || (showsVideoCoverDurationBadges && !display.durationText.isEmpty) {
            VideoCoverBottomScrim()
        }
    }
}
