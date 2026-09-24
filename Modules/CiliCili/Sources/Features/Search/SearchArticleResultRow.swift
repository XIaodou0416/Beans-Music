import SwiftUI

struct SearchArticleResultRow: View {
    let article: SearchArticleItem

    private var publishDate: String {
        BiliFormatters.publishDate(article.pubTime)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SearchPosterCover(
                sourceURLString: article.imageURLs.first?.normalizedBiliURL(),
                thumbnailWidth: 228,
                thumbnailHeight: 228,
                targetPixelSize: 228,
                size: CGSize(width: 78, height: 78),
                placeholderSystemImage: "doc.text"
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(article.title)
                    .appTypography(.compactVideoTitle, fallback: .subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                SearchArticleMetaLine(article: article, publishDate: publishDate)
                SearchArticleDescriptionText(article: article)
                SearchArticleMetricsLine(article: article)
            }
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        }
        .contentShape(Rectangle())
    }
}

private struct SearchArticleMetaLine: View {
    let article: SearchArticleItem
    let publishDate: String

    var body: some View {
        HStack(spacing: 8) {
            if let author = article.author, !author.isEmpty {
                Text(author)
            }
            if publishDate != "-" {
                Text(publishDate)
            }
        }
        .appTypography(.metadata, fallback: .caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct SearchArticleDescriptionText: View {
    let article: SearchArticleItem

    var body: some View {
        if let description = article.description, !description.isEmpty {
            Text(description.removingHTMLTags())
                .appTypography(.settingsSubtitle, fallback: .caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct SearchArticleMetricsLine: View {
    let article: SearchArticleItem

    var body: some View {
        HStack(spacing: 12) {
            SearchMetadataLabel(text: BiliFormatters.compactCount(article.view), systemImage: "eye")
            SearchMetadataLabel(text: BiliFormatters.compactCount(article.reply), systemImage: "bubble.left")
            SearchMetadataLabel(text: BiliFormatters.compactCount(article.like), systemImage: "hand.thumbsup")
        }
        .appTypography(.tertiaryMetadata, fallback: .caption2)
        .foregroundStyle(.tertiary)
    }
}
