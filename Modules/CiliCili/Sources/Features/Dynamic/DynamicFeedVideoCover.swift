import SwiftUI

struct DynamicFeedVideoCover: View {
    @Environment(\.showsVideoCoverDurationBadges) private var showsVideoCoverDurationBadges
    let video: VideoItem
    let display: VideoCardDisplayModel
    @State private var coverLoadedState = VideoCoverLoadedState()

    var body: some View {
        FixedAspectPreview(aspectRatio: 16 / 9) {
            ZStack {
                Color.clear

                AdaptiveVideoCoverImage(
                    display: display,
                    style: .maxSide,
                    onPhaseChange: { phase in
                        coverLoadedState.update(phase: phase, identity: display.coverLoadIdentity)
                    }
                )

                if coverLoadedState.isLoaded(identity: display.coverLoadIdentity) {
                    VideoCoverBottomScrim()

                    DynamicVideoPlayBadge(size: 34, iconSize: 14)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                    if showsVideoCoverDurationBadges, video.duration != nil {
                        VideoCoverDurationBadge(BiliFormatters.duration(video.duration))
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }
            }
        }
        .videoCoverSurface(cornerRadius: 20, shadowLevel: .control)
    }
}
