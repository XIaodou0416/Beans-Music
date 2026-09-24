import SwiftUI

struct VideoCompactListTextColumn: View {
    let display: VideoCardDisplayModel
    let titleMinHeight: CGFloat
    let authorStyle: VideoCompactListRow.AuthorStyle
    let metadataStyle: VideoCompactListRow.MetadataStyle
    let minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            StableVideoTitleText(display.title, style: .related, lineLimit: 2)
                .frame(minHeight: titleMinHeight, alignment: .topLeading)

            VideoCompactAuthorLabel(display: display, authorStyle: authorStyle)

            VideoCompactMetadataRow(display: display, metadataStyle: metadataStyle)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
    }
}

private struct VideoCompactAuthorLabel: View {
    let display: VideoCardDisplayModel
    let authorStyle: VideoCompactListRow.AuthorStyle

    var body: some View {
        switch authorStyle {
        case .plain:
            Text(display.authorName)
                .appTypography(.compactAuthor, fallback: .caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .icon(let systemImage):
            Label(display.authorName, systemImage: systemImage)
                .appTypography(.compactAuthor, fallback: .caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct VideoCompactMetadataRow: View {
    let display: VideoCardDisplayModel
    let metadataStyle: VideoCompactListRow.MetadataStyle

    var body: some View {
        switch metadataStyle {
        case .related:
            HStack(spacing: 4) {
                if !display.viewText.isEmpty {
                    Label(display.viewText, systemImage: "play.fill")
                        .labelStyle(.titleAndIcon)
                }

                if !display.publishTimeText.isEmpty {
                    Text(display.viewText.isEmpty ? display.publishTimeText : "· \(display.publishTimeText)")
                }
            }
            .appTypography(.tertiaryMetadata, fallback: .caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        case .search:
            HStack(spacing: 7) {
                VideoCompactMetadataLabel(text: display.viewText, systemImage: "play.rectangle")
                VideoCompactMetadataLabel(text: display.publishTimeText, systemImage: "clock")
            }
            .appTypography(.tertiaryMetadata, fallback: .caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
    }
}

private struct VideoCompactMetadataLabel: View {
    let text: String
    let systemImage: String

    var body: some View {
        if !text.isEmpty {
            Label(text, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
        }
    }
}
