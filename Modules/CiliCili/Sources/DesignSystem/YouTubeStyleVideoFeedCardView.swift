import SwiftUI

struct YouTubeStyleVideoFeedCardView: View, Equatable {
    let display: VideoCardDisplayModel
    private let showsMetadataSummary: Bool
    private let showsPlayBadge: Bool
    private let usesGenericAuthorIcon: Bool
    private let placesViewAndPublishTimeTrailing: Bool
    private let fixedCoverAspectRatio: CGFloat?
    private let fixedCoverSize: CGSize?
    private let coverMaximumPixelLength: Int
    private let coverShadowLevel: MediaShadowLevel

    init(
        video: VideoItem,
        showsMetadataSummary: Bool = true,
        showsPlayBadge: Bool = false,
        usesGenericAuthorIcon: Bool = false,
        placesViewAndPublishTimeTrailing: Bool = false,
        fixedCoverAspectRatio: CGFloat? = nil,
        fixedCoverSize: CGSize? = nil,
        coverMaximumPixelLength: Int = 1280,
        coverShadowLevel: MediaShadowLevel = .control
    ) {
        self.display = VideoCardDisplayModel(video: video)
        self.showsMetadataSummary = showsMetadataSummary
        self.showsPlayBadge = showsPlayBadge
        self.usesGenericAuthorIcon = usesGenericAuthorIcon
        self.placesViewAndPublishTimeTrailing = placesViewAndPublishTimeTrailing
        self.fixedCoverAspectRatio = fixedCoverAspectRatio
        self.fixedCoverSize = fixedCoverSize
        self.coverMaximumPixelLength = coverMaximumPixelLength
        self.coverShadowLevel = coverShadowLevel
    }

    init(
        display: VideoCardDisplayModel,
        showsMetadataSummary: Bool = true,
        showsPlayBadge: Bool = false,
        usesGenericAuthorIcon: Bool = false,
        placesViewAndPublishTimeTrailing: Bool = false,
        fixedCoverAspectRatio: CGFloat? = nil,
        fixedCoverSize: CGSize? = nil,
        coverMaximumPixelLength: Int = 1280,
        coverShadowLevel: MediaShadowLevel = .control
    ) {
        self.display = display
        self.showsMetadataSummary = showsMetadataSummary
        self.showsPlayBadge = showsPlayBadge
        self.usesGenericAuthorIcon = usesGenericAuthorIcon
        self.placesViewAndPublishTimeTrailing = placesViewAndPublishTimeTrailing
        self.fixedCoverAspectRatio = fixedCoverAspectRatio
        self.fixedCoverSize = fixedCoverSize
        self.coverMaximumPixelLength = coverMaximumPixelLength
        self.coverShadowLevel = coverShadowLevel
    }

    static func == (lhs: YouTubeStyleVideoFeedCardView, rhs: YouTubeStyleVideoFeedCardView) -> Bool {
        lhs.display == rhs.display
            && lhs.showsMetadataSummary == rhs.showsMetadataSummary
            && lhs.showsPlayBadge == rhs.showsPlayBadge
            && lhs.usesGenericAuthorIcon == rhs.usesGenericAuthorIcon
            && lhs.placesViewAndPublishTimeTrailing == rhs.placesViewAndPublishTimeTrailing
            && lhs.fixedCoverAspectRatio == rhs.fixedCoverAspectRatio
            && lhs.fixedCoverSize == rhs.fixedCoverSize
            && lhs.coverMaximumPixelLength == rhs.coverMaximumPixelLength
            && lhs.coverShadowLevel == rhs.coverShadowLevel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            YouTubeStyleVideoFeedThumbnail(
                display: display,
                showsPlayBadge: showsPlayBadge,
                coverAspectRatio: effectiveCoverAspectRatio,
                fixedCoverSize: fixedCoverSize,
                coverMaximumPixelLength: coverMaximumPixelLength,
                coverShadowLevel: coverShadowLevel
            )

            YouTubeStyleVideoFeedMetadataRow(
                display: display,
                showsMetadataSummary: showsMetadataSummary,
                usesGenericAuthorIcon: usesGenericAuthorIcon,
                placesViewAndPublishTimeTrailing: placesViewAndPublishTimeTrailing
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private var sanitizedCoverAspectRatio: CGFloat {
        min(max(display.coverAspectRatio, 0.56), 2.2)
    }

    private var effectiveCoverAspectRatio: CGFloat {
        fixedCoverAspectRatio ?? sanitizedCoverAspectRatio
    }
}
