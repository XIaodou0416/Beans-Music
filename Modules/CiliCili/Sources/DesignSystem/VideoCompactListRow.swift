import SwiftUI

struct VideoCompactListRow: View, Equatable {
    enum AuthorStyle: Equatable {
        case plain
        case icon(String)
    }

    enum MetadataStyle: Equatable {
        case related
        case search
    }

    let display: VideoCardDisplayModel
    let coverSize: CGSize
    var coverMaximumPixelLength: Int = 1280
    var coverCornerRadius: CGFloat = 10
    var showsCoverBorder = false
    var titleMinHeight: CGFloat = 36
    var authorStyle: AuthorStyle = .plain
    var metadataStyle: MetadataStyle = .related

    static func == (lhs: VideoCompactListRow, rhs: VideoCompactListRow) -> Bool {
        lhs.display == rhs.display
            && lhs.coverSize == rhs.coverSize
            && lhs.coverMaximumPixelLength == rhs.coverMaximumPixelLength
            && lhs.coverCornerRadius == rhs.coverCornerRadius
            && lhs.showsCoverBorder == rhs.showsCoverBorder
            && lhs.titleMinHeight == rhs.titleMinHeight
            && lhs.authorStyle == rhs.authorStyle
            && lhs.metadataStyle == rhs.metadataStyle
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VideoCompactCover(
                display: display,
                size: coverSize,
                maximumPixelLength: coverMaximumPixelLength,
                cornerRadius: coverCornerRadius,
                showsBorder: showsCoverBorder
            )

            VideoCompactListTextColumn(
                display: display,
                titleMinHeight: titleMinHeight,
                authorStyle: authorStyle,
                metadataStyle: metadataStyle,
                minHeight: coverSize.height
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(display.title)
    }
}

struct VideoCompactListPlaceholderRow: View {
    let coverSize: CGSize
    var fill: Color = Color(.secondarySystemGroupedBackground)
    var cornerRadius: CGFloat = 10
    var titleMinHeight: CGFloat = 36
    var authorStyle: VideoCompactListRow.AuthorStyle = .plain
    var metadataStyle: VideoCompactListRow.MetadataStyle = .related

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)
                .frame(width: coverSize.width, height: coverSize.height)

            VStack(alignment: .leading, spacing: 5) {
                titlePlaceholder
                    .frame(minHeight: titleMinHeight, alignment: .topLeading)

                authorPlaceholder
                metadataPlaceholder
            }
            .frame(maxWidth: .infinity, minHeight: coverSize.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityLabel("正在加载视频列表")
    }

    private var titlePlaceholder: some View {
        VStack(alignment: .leading, spacing: 4) {
            placeholderBlock(height: 15)
            placeholderBlock(width: 156, height: 15)
        }
    }

    @ViewBuilder
    private var authorPlaceholder: some View {
        switch authorStyle {
        case .plain:
            placeholderBlock(width: 118, height: 12)
        case .icon(_):
            HStack(spacing: 4) {
                placeholderBlock(width: 12, height: 12)
                placeholderBlock(width: 118, height: 12)
            }
        }
    }

    @ViewBuilder
    private var metadataPlaceholder: some View {
        switch metadataStyle {
        case .related:
            placeholderBlock(width: 92, height: 11)
        case .search:
            HStack(spacing: 7) {
                placeholderBlock(width: 62, height: 11)
                placeholderBlock(width: 74, height: 11)
            }
        }
    }

    private func placeholderBlock(width: CGFloat? = nil, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(fill)
            .frame(width: width, height: height)
    }
}
