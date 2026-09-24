import SwiftUI

struct VideoDetailLoadedCommentsContentPage: View {
    let viewModel: VideoDetailViewModel
    let onReply: (Comment) -> Void
    let onComposeReply: ((Comment) -> Void)?

    var body: some View {
        VideoDetailEmbeddedCommentsSection(
            viewModel: viewModel,
            onReply: onReply,
            onComposeReply: onComposeReply
        )
        .padding(.top, 0)
    }
}
