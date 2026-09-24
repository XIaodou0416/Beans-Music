import SwiftUI

/// Live rooms use the same title and creator treatment as video details,
/// while keeping live-only controls inside the player surface.
struct LiveRoomMinimalDetailHeader: View {
    @ObservedObject var viewModel: LiveRoomViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlaybackDetailTitleText(
                text: titleText,
                typographyRole: .liveRoomTitle
            )
                .commentCopyContextMenu(text: titleText, title: "复制标题")

            HStack(spacing: 0) {
                PlaybackDetailOwnerAvatar(
                    owner: viewModel.anchorOwner,
                    fallbackURLString: viewModel.anchorFace,
                    side: 34
                )

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleText: String {
        let trimmedTitle = viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "直播间" : trimmedTitle
    }
}
