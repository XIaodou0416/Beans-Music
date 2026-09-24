import SwiftUI

struct YouTubeStyleVideoFeedMetadataRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let display: VideoCardDisplayModel
    let showsMetadataSummary: Bool
    let usesGenericAuthorIcon: Bool
    let placesViewAndPublishTimeTrailing: Bool

    private static let avatarSide: CGFloat = 34
    private static let authorBadgeSide: CGFloat = 12

    var body: some View {
        Group {
            if usesGenericAuthorIcon {
                VStack(alignment: .leading, spacing: 3) {
                    titleLabel
                    if usesAccessibilityLayout {
                        genericAuthorAccessibilityMetadata
                    } else if placesViewAndPublishTimeTrailing {
                        genericAuthorSplitMetadataRow
                    } else {
                        HStack(spacing: 3) {
                            BilibiliUPBadge(size: Self.authorBadgeSide)

                            genericAuthorMetadataLabel
                        }
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 9) {
                    authorIdentityIcon

                    VStack(alignment: .leading, spacing: 3) {
                        titleLabel
                        metadataLabel
                    }
                }
            }
        }
        .frame(minHeight: Self.avatarSide, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleLabel: some View {
        StableVideoTitleText(
            display.title,
            style: .feedHeadline,
            lineLimit: usesAccessibilityLayout ? 2 : 1
        )
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadataLabel: some View {
        Text(metadataText)
            .appTypography(.metadata, fallback: .caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(usesAccessibilityLayout ? 2 : 1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var genericAuthorMetadataLabel: some View {
        Text(genericAuthorMetadataText)
            .appTypography(.metadata, fallback: .caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(usesAccessibilityLayout ? 2 : 1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadataText: String {
        showsMetadataSummary ? display.metadataSummaryText : display.authorName
    }

    private var genericAuthorMetadataText: String {
        guard showsMetadataSummary else { return display.authorName }

        return [
            display.authorName,
            display.recommendReasonText.isEmpty ? nil : display.recommendReasonText,
            display.viewText.isEmpty ? nil : "\(display.viewText)次观看",
            display.publishTimeText
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: " · ")
    }

    private var genericAuthorLeadingMetadataText: String {
        [
            display.authorName,
            display.recommendReasonText.isEmpty ? nil : display.recommendReasonText
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: " · ")
    }

    private var trailingMetadataText: String {
        guard showsMetadataSummary else { return "" }

        return [
            display.viewText.isEmpty ? nil : "\(display.viewText)次观看",
            display.publishTimeText.isEmpty ? nil : display.publishTimeText
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var genericAuthorSplitMetadataRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            HStack(spacing: 3) {
                BilibiliUPBadge(size: Self.authorBadgeSide)

                Text(genericAuthorLeadingMetadataText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            if !trailingMetadataText.isEmpty {
                Text(trailingMetadataText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .appTypography(.metadata, fallback: .caption.weight(.medium))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var genericAuthorAccessibilityMetadata: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                BilibiliUPBadge(size: Self.authorBadgeSide)

                Text(genericAuthorLeadingMetadataText)
                    .appTypography(.compactAuthor, fallback: .caption.weight(.medium))
                    .lineLimit(2)
            }

            if !trailingMetadataText.isEmpty {
                Text(trailingMetadataText)
                    .appTypography(.metadata, fallback: .caption.weight(.medium))
                    .lineLimit(2)
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var usesAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    @ViewBuilder
    private var authorIdentityIcon: some View {
        AvatarRemoteImage(urlString: display.avatarURLString, pixelSize: 68) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(width: Self.avatarSide, height: Self.avatarSide)
        .clipShape(Circle())
        .mediaShadow(.subtle)
    }
}
