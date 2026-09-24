import SwiftUI

struct VideoCardElevatedBody<Cover: View>: View {
    let display: VideoCardDisplayModel
    let cover: Cover
    let showsPublishTimeInAuthorRow: Bool
    let showsAuthorIdentity: Bool
    let usesGenericAuthorIcon: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover

            VideoCardTextStack(
                display: display,
                showsPublishTimeInAuthorRow: showsPublishTimeInAuthorRow,
                showsAuthorIdentity: showsAuthorIdentity,
                usesGenericAuthorIcon: usesGenericAuthorIcon
            )
            .padding(.horizontal, 8)
            .padding(.top, 7)
            .padding(.bottom, 8)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.10), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .mediaShadow(.subtle)
    }
}

struct VideoCardBlendedBody<Cover: View>: View {
    let display: VideoCardDisplayModel
    let cover: Cover
    let showsPublishTimeInAuthorRow: Bool
    let showsAuthorIdentity: Bool
    let usesGenericAuthorIcon: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cover
                .videoCoverSurface(cornerRadius: 15, shadowLevel: .control)

            VideoCardTextStack(
                display: display,
                showsPublishTimeInAuthorRow: showsPublishTimeInAuthorRow,
                showsAuthorIdentity: showsAuthorIdentity,
                usesGenericAuthorIcon: usesGenericAuthorIcon
            )
            .padding(.horizontal, 2)
        }
    }
}

struct VideoCardBorderedBody<Cover: View>: View {
    let display: VideoCardDisplayModel
    let cover: Cover
    let showsPublishTimeInAuthorRow: Bool
    let showsAuthorIdentity: Bool
    let usesGenericAuthorIcon: Bool

    private let cornerRadius: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cover
                .videoCardBorderedCover()

            VideoCardTextStack(
                display: display,
                showsPublishTimeInAuthorRow: showsPublishTimeInAuthorRow,
                showsAuthorIdentity: showsAuthorIdentity,
                usesGenericAuthorIcon: usesGenericAuthorIcon
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .videoCardBorderedSurface(cornerRadius: cornerRadius)
    }
}

struct VideoCardBorderedCompactBody: View, Equatable {
    enum LeadingMetadata: Equatable {
        case viewCount
        case duration
    }

    @Environment(\.showsVideoCoverDurationBadges) private var showsVideoCoverDurationBadges
    let display: VideoCardDisplayModel
    let coverSize: CGSize
    var usesGenericAuthorIcon = false
    var leadingMetadata: LeadingMetadata = .viewCount
    var showsRecommendReason = true
    var showsCoverDurationBadge = true
    @State private var coverLoadedState = VideoCoverLoadedState()

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.display == rhs.display
            && lhs.coverSize == rhs.coverSize
            && lhs.usesGenericAuthorIcon == rhs.usesGenericAuthorIcon
            && lhs.leadingMetadata == rhs.leadingMetadata
            && lhs.showsRecommendReason == rhs.showsRecommendReason
            && lhs.showsCoverDurationBadge == rhs.showsCoverDurationBadge
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            cover

            VStack(alignment: .leading, spacing: 8) {
                StableVideoTitleText(display.title, style: .compactCard, lineLimit: 2)
                    .frame(minHeight: 38, alignment: .topLeading)

                Spacer(minLength: 0)

                metadataStack
            }
            .frame(maxWidth: .infinity, minHeight: coverSize.height, alignment: .topLeading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: max(coverSize.height + 20, 108), alignment: .topLeading)
        .compactVideoResultSurface(cornerRadius: 18)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(display.title)
    }

    private var cover: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        return AdaptiveVideoCoverImage(
            display: display,
            style: .exactCrop,
            fixedSize: coverSize,
            maximumPixelLength: 480,
            onPhaseChange: coverPhaseChangeHandler
        )
        .frame(width: coverSize.width, height: coverSize.height)
        .overlay {
            if showsLoadedDurationBadge {
                VideoCoverBottomScrim()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showsLoadedDurationBadge {
                VideoCoverDurationBadge(
                    display.durationText,
                    maxWidth: max(coverSize.width - 14, 1)
                )
                .padding(7)
            }
        }
        .clipShape(shape)
        .unifiedVideoCoverBorder(in: shape)
    }

    private var metadataStack: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !display.authorName.isEmpty {
                HStack(spacing: 4) {
                    authorIdentityIcon

                    Text(display.authorName)
                        .lineLimit(1)

                    if showsRecommendReason, !display.recommendReasonText.isEmpty {
                        Text(display.recommendReasonText)
                            .lineLimit(1)
                    }
                }
                .appTypography(.compactAuthor, fallback: .system(size: 12))
            }

            if !leadingMetadataText.isEmpty || !display.publishTimeText.isEmpty {
                HStack(spacing: 8) {
                    if !leadingMetadataText.isEmpty {
                        Label(leadingMetadataText, systemImage: leadingMetadataSystemImage)
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    if !display.publishTimeText.isEmpty {
                        Text(display.publishTimeText)
                            .lineLimit(1)
                    }
                }
                .appTypography(.tertiaryMetadata, fallback: .system(size: 11))
            }
        }
        .foregroundStyle(.secondary)
    }

    private var leadingMetadataText: String {
        switch leadingMetadata {
        case .viewCount:
            return display.viewText
        case .duration:
            return display.durationText
        }
    }

    private var leadingMetadataSystemImage: String {
        switch leadingMetadata {
        case .viewCount:
            return "play.fill"
        case .duration:
            return "clock"
        }
    }

    private var showsLoadedDurationBadge: Bool {
        showsCoverDurationBadge
            && showsVideoCoverDurationBadges
            && !display.durationText.isEmpty
            && coverLoadedState.isLoaded(identity: display.coverLoadIdentity)
    }

    private var coverPhaseChangeHandler: ((RemoteImageLoadingPhase) -> Void)? {
        guard showsCoverDurationBadge else { return nil }
        return { phase in
            coverLoadedState.update(phase: phase, identity: display.coverLoadIdentity)
        }
    }

    @ViewBuilder
    private var authorIdentityIcon: some View {
        if usesGenericAuthorIcon {
            BilibiliUPBadge(size: 12)
        }
    }
}

extension View {
    func compactVideoResultSurface(cornerRadius: CGFloat = 18) -> some View {
        modifier(CompactVideoResultSurfaceModifier(cornerRadius: cornerRadius))
    }

    func videoCardBorderedSurface(cornerRadius: CGFloat = 18, showsShadow: Bool = true) -> some View {
        modifier(VideoCardBorderedSurfaceModifier(cornerRadius: cornerRadius, showsShadow: showsShadow))
    }

    func videoCardBorderedCover(cornerRadius: CGFloat = 14) -> some View {
        videoCoverSurface(cornerRadius: cornerRadius, emphasizesBorder: true)
    }
}

private struct CompactVideoResultSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                shape.fill(Color(.secondarySystemGroupedBackground))
            }
            .overlay {
                shape.strokeBorder(Color(.separator).opacity(0.16), lineWidth: 0.5)
            }
    }
}

private struct VideoCardBorderedSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let showsShadow: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: 1)
            }
            .shadow(color: .black.opacity(showsShadow ? shadowOpacity : 0), radius: 18, x: 0, y: 10)
            .shadow(color: .black.opacity(showsShadow ? 0.06 : 0), radius: 6, x: 0, y: 2)
    }

    private var borderColor: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.18)
        default:
            return Color.black.opacity(0.12)
        }
    }

    private var shadowOpacity: Double {
        colorScheme == .dark ? 0.18 : 0.10
    }
}
