import SwiftUI

struct VideoDetailRelatedPlaceholderList: View {
    let layout: VideoDetailRelatedListLayout

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<VideoDetailRelatedStyle.placeholderCount, id: \.self) { _ in
                VideoCompactListPlaceholderRow(
                    coverSize: layout.coverSize,
                    fill: Color(.tertiarySystemFill).opacity(0.64),
                    cornerRadius: VideoDetailRelatedStyle.coverCornerRadius,
                    titleMinHeight: VideoDetailRelatedStyle.rowTitleMinHeight,
                    authorStyle: .plain,
                    metadataStyle: .related
                )
                .padding(.vertical, VideoDetailRelatedStyle.rowVerticalPadding)

                Divider()
                    .padding(.leading, layout.dividerLeadingPadding)
            }
        }
    }
}
