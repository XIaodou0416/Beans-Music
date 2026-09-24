import SwiftUI

struct VideoCardView: View, Equatable {
    @Environment(\.showsVideoCoverDurationBadges) private var showsVideoCoverDurationBadges
    enum SurfaceStyle: Equatable {
        case elevated
        case blended
        case bordered
    }

    let display: VideoCardDisplayModel
    private let showsPublishTimeInAuthorRow: Bool
    private let showsAuthorIdentity: Bool
    private let usesGenericAuthorIcon: Bool
    private let showsCoverViewCountBadge: Bool
    private let surfaceStyle: SurfaceStyle
    private let coverAspectRatio: CGFloat
    private let fixedCoverSize: CGSize?
    private let coverMaximumPixelLength: Int
    @State private var coverLoadedState = VideoCoverLoadedState()

    init(
        video: VideoItem,
        showsPublishTimeInAuthorRow: Bool = false,
        showsAuthorIdentity: Bool = true,
        usesGenericAuthorIcon: Bool = false,
        showsCoverViewCountBadge: Bool = true,
        surfaceStyle: SurfaceStyle = .elevated,
        coverAspectRatio: CGFloat = 16.0 / 9.0,
        fixedCoverSize: CGSize? = nil,
        coverMaximumPixelLength: Int = 1280
    ) {
        self.display = VideoCardDisplayModel(video: video)
        self.showsPublishTimeInAuthorRow = showsPublishTimeInAuthorRow
        self.showsAuthorIdentity = showsAuthorIdentity
        self.usesGenericAuthorIcon = usesGenericAuthorIcon
        self.showsCoverViewCountBadge = showsCoverViewCountBadge
        self.surfaceStyle = surfaceStyle
        self.coverAspectRatio = coverAspectRatio
        self.fixedCoverSize = fixedCoverSize
        self.coverMaximumPixelLength = coverMaximumPixelLength
    }

    init(
        display: VideoCardDisplayModel,
        showsPublishTimeInAuthorRow: Bool = false,
        showsAuthorIdentity: Bool = true,
        usesGenericAuthorIcon: Bool = false,
        showsCoverViewCountBadge: Bool = true,
        surfaceStyle: SurfaceStyle = .elevated,
        coverAspectRatio: CGFloat = 16.0 / 9.0,
        fixedCoverSize: CGSize? = nil,
        coverMaximumPixelLength: Int = 1280
    ) {
        self.display = display
        self.showsPublishTimeInAuthorRow = showsPublishTimeInAuthorRow
        self.showsAuthorIdentity = showsAuthorIdentity
        self.usesGenericAuthorIcon = usesGenericAuthorIcon
        self.showsCoverViewCountBadge = showsCoverViewCountBadge
        self.surfaceStyle = surfaceStyle
        self.coverAspectRatio = coverAspectRatio
        self.fixedCoverSize = fixedCoverSize
        self.coverMaximumPixelLength = coverMaximumPixelLength
    }

    static func == (lhs: VideoCardView, rhs: VideoCardView) -> Bool {
        lhs.display == rhs.display
            && lhs.showsPublishTimeInAuthorRow == rhs.showsPublishTimeInAuthorRow
            && lhs.showsAuthorIdentity == rhs.showsAuthorIdentity
            && lhs.usesGenericAuthorIcon == rhs.usesGenericAuthorIcon
            && lhs.showsCoverViewCountBadge == rhs.showsCoverViewCountBadge
            && lhs.surfaceStyle == rhs.surfaceStyle
            && lhs.coverAspectRatio == rhs.coverAspectRatio
            && lhs.fixedCoverSize == rhs.fixedCoverSize
            && lhs.coverMaximumPixelLength == rhs.coverMaximumPixelLength
    }

    var body: some View {
        Group {
            switch surfaceStyle {
            case .elevated:
                elevatedBody
            case .blended:
                blendedBody
            case .bordered:
                borderedBody
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private var elevatedBody: some View {
        VideoCardElevatedBody(
            display: display,
            cover: cover,
            showsPublishTimeInAuthorRow: showsPublishTimeInAuthorRow,
            showsAuthorIdentity: showsAuthorIdentity,
            usesGenericAuthorIcon: usesGenericAuthorIcon
        )
    }

    private var blendedBody: some View {
        VideoCardBlendedBody(
            display: display,
            cover: cover,
            showsPublishTimeInAuthorRow: showsPublishTimeInAuthorRow,
            showsAuthorIdentity: showsAuthorIdentity,
            usesGenericAuthorIcon: usesGenericAuthorIcon
        )
    }

    private var borderedBody: some View {
        VideoCardBorderedBody(
            display: display,
            cover: cover,
            showsPublishTimeInAuthorRow: showsPublishTimeInAuthorRow,
            showsAuthorIdentity: showsAuthorIdentity,
            usesGenericAuthorIcon: usesGenericAuthorIcon
        )
    }

    private var cover: some View {
        Color.clear
            .aspectRatio(coverAspectRatio, contentMode: .fit)
            .overlay {
                ZStack(alignment: .bottom) {
                    coverImage
                    if coverLoadedState.isLoaded(identity: display.coverLoadIdentity) {
                        coverBottomScrim
                        coverMetaOverlay
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
    }

    @ViewBuilder
    private var coverImage: some View {
        AdaptiveVideoCoverImage(
            display: display,
            style: .exactCrop,
            fixedSize: fixedCoverSize,
            maximumPixelLength: coverMaximumPixelLength,
            onPhaseChange: { phase in
                coverLoadedState.update(phase: phase, identity: display.coverLoadIdentity)
            }
        )
    }

    private var coverMetaOverlay: some View {
        VideoCoverMetaOverlay(
            viewText: display.viewText,
            durationText: display.durationText,
            showsViewCount: showsCoverViewCountBadge,
            horizontalPadding: 10,
            bottomPadding: 8,
            spacing: 6
        )
    }

    @ViewBuilder
    private var coverBottomScrim: some View {
        if (showsCoverViewCountBadge && !display.viewText.isEmpty)
            || (showsVideoCoverDurationBadges && !display.durationText.isEmpty) {
            VideoCoverBottomScrim()
        }
    }
}
