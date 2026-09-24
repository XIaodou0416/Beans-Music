import SwiftUI

struct VideoCompactCover: View, Equatable {
    @Environment(\.showsVideoCoverDurationBadges) private var showsVideoCoverDurationBadges
    let display: VideoCardDisplayModel
    let size: CGSize
    let maximumPixelLength: Int
    let cornerRadius: CGFloat
    let showsBorder: Bool
    var borderOpacityScale: Double = 1
    var showsShadow = true
    private let badgeInset: CGFloat = 7
    @State private var coverLoadedState = VideoCoverLoadedState()

    static func == (lhs: VideoCompactCover, rhs: VideoCompactCover) -> Bool {
        lhs.display == rhs.display
            && lhs.size == rhs.size
            && lhs.maximumPixelLength == rhs.maximumPixelLength
            && lhs.cornerRadius == rhs.cornerRadius
            && lhs.showsBorder == rhs.showsBorder
            && lhs.borderOpacityScale == rhs.borderOpacityScale
            && lhs.showsShadow == rhs.showsShadow
    }

    var body: some View {
        AdaptiveVideoCoverImage(
            display: display,
            style: .exactCrop,
            fixedSize: size,
            maximumPixelLength: maximumPixelLength,
            onPhaseChange: { phase in
                coverLoadedState.update(phase: phase, identity: display.coverLoadIdentity)
            }
        )
        .frame(width: size.width, height: size.height)
        .overlay {
            if coverLoadedState.isLoaded(identity: display.coverLoadIdentity), showsDurationBadge {
                VideoCoverBottomScrim()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if coverLoadedState.isLoaded(identity: display.coverLoadIdentity), showsDurationBadge {
                VideoCoverDurationBadge(
                    display.durationText,
                    maxWidth: max(size.width - badgeInset * 2, 1)
                )
                .padding(badgeInset)
            }
        }
        .clipped()
        .videoCoverSurface(
            cornerRadius: cornerRadius,
            shadowLevel: showsShadow ? .subtle : nil,
            emphasizesBorder: showsBorder,
            borderOpacityScale: borderOpacityScale
        )
    }

    private var showsDurationBadge: Bool {
        showsVideoCoverDurationBadges && !display.durationText.isEmpty
    }
}
