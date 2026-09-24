import SwiftUI

struct VideoCoverMetaOverlay: View {
    @Environment(\.showsVideoCoverDurationBadges) private var showsVideoCoverDurationBadges
    let viewText: String
    let durationText: String
    var showsViewCount = true
    var durationMaxWidth: CGFloat = 96
    var horizontalPadding: CGFloat = 10
    var bottomPadding: CGFloat = 8
    var spacing: CGFloat = 6

    var body: some View {
        HStack(spacing: spacing) {
            if showsViewCount, !viewText.isEmpty {
                VideoCoverViewCountBadge(viewText)
            }

            Spacer(minLength: spacing)

            if showsVideoCoverDurationBadges, !durationText.isEmpty {
                VideoCoverDurationBadge(durationText, maxWidth: durationMaxWidth)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .clipped()
    }

    var showsAnyMetadata: Bool {
        (showsViewCount && !viewText.isEmpty) || (showsVideoCoverDurationBadges && !durationText.isEmpty)
    }
}
