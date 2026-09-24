import SwiftUI

struct DynamicArchivePreview: View {
    @Environment(\.showsVideoCoverDurationBadges) private var showsVideoCoverDurationBadges
    enum Style {
        case large
        case compact
    }

    private static let compactCoverSize = CGSize(width: 118, height: 66)

    let video: VideoItem
    let display: VideoCardDisplayModel
    var style: Style = .large
    var showsHeader = true
    var showsCoverBadges = true

    init(
        video: VideoItem,
        style: Style = .large,
        showsHeader: Bool = true,
        showsCoverBadges: Bool = true
    ) {
        self.video = video
        self.display = VideoCardDisplayModel(video: video)
        self.style = style
        self.showsHeader = showsHeader
        self.showsCoverBadges = showsCoverBadges
    }

    var body: some View {
        switch style {
        case .large:
            largeContent
        case .compact:
            compactContent
        }
    }

    private var largeContent: some View {
        YouTubeStyleVideoFeedCardView(
            display: display,
            showsMetadataSummary: false,
            showsPlayBadge: true,
            fixedCoverAspectRatio: 16 / 9,
            coverShadowLevel: .control
        )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("瑙嗛 \(video.title)")
    }

    private var compactContent: some View {
        HStack(spacing: 10) {
            cover(
                showsPlayGlyph: showsCoverBadges,
                showsDurationBadge: showsCoverBadges,
                aspectRatio: 16 / 9,
                fixedSize: Self.compactCoverSize
            )
                .frame(width: Self.compactCoverSize.width, height: Self.compactCoverSize.height)

            VStack(alignment: .leading, spacing: 7) {
                DynamicVideoTitleText(
                    video.title,
                    style: .compact,
                    lineLimit: 2
                )

                metadata
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func cover(
        showsPlayGlyph: Bool,
        showsDurationBadge: Bool = true,
        aspectRatio: CGFloat,
        fixedSize: CGSize? = nil
    ) -> some View {
        FixedAspectPreview(aspectRatio: aspectRatio) {
            ZStack {
                Color.clear

                AdaptiveVideoCoverImage(display: display, style: .exactCrop, fixedSize: fixedSize)

                if showsPlayGlyph || (showsVideoCoverDurationBadges && showsDurationBadge) {
                    VideoCoverBottomScrim()
                }

                if showsPlayGlyph {
                    DynamicVideoPlayBadge(size: 28, iconSize: 12)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }

                if showsVideoCoverDurationBadges, showsDurationBadge, video.duration != nil {
                    VideoCoverDurationBadge(BiliFormatters.duration(video.duration))
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
        }
        .background(BiliMediaPlaceholder(style: .video, iconSize: 16))
        .videoCoverSurface(cornerRadius: 16, shadowLevel: .control)
    }

    private var metadata: some View {
        HStack(spacing: 10) {
            if let ownerName = video.owner?.name, !ownerName.isEmpty {
                Text(ownerName)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
