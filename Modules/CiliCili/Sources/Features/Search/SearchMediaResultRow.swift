import SwiftUI

struct SearchMediaResultRow: View {
    let media: SearchMediaItem
    let kind: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SearchPosterCover(
                sourceURLString: media.cover,
                thumbnailWidth: 216,
                thumbnailHeight: 288,
                targetPixelSize: 288,
                size: CGSize(width: 76, height: 102),
                placeholderSystemImage: "film"
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(media.title)
                    .appTypography(.compactVideoTitle, fallback: .subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                SearchMediaMetaLine(media: media, kind: kind)
                SearchMediaStylesText(media: media)
                SearchMediaDescriptionText(media: media)
            }
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .topLeading)
        }
        .contentShape(Rectangle())
    }
}

private struct SearchMediaMetaLine: View {
    let media: SearchMediaItem
    let kind: String

    var body: some View {
        HStack(spacing: 8) {
            SearchSoftPill(media.typeName ?? kind)
            if let rating = media.rating, !rating.isEmpty {
                SearchSoftPill("\(rating)分", tint: .pink)
            }
            if let indexShow = media.indexShow, !indexShow.isEmpty {
                Text(indexShow)
            }
        }
        .appTypography(.metadata, fallback: .caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct SearchMediaStylesText: View {
    let media: SearchMediaItem

    var body: some View {
        if let stylesText = media.stylesText, !stylesText.isEmpty {
            Text(stylesText)
                .appTypography(.tertiaryMetadata, fallback: .caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct SearchMediaDescriptionText: View {
    let media: SearchMediaItem

    var body: some View {
        if let description = media.description, !description.isEmpty {
            Text(description.removingHTMLTags())
                .appTypography(.settingsSubtitle, fallback: .caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}
