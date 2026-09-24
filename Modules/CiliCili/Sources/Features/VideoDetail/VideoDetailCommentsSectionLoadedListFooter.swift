import SwiftUI

struct CommentsSectionLoadedListFooter: View {
    @ObservedObject var store: VideoDetailCommentsRenderStore
    let style: CommentSectionStyle
    let maxVisibleComments: Int?
    let showAllComments: (() -> Void)?
    let loadMoreComments: () async -> Void

    var body: some View {
        CommentsSectionLoadedListFooterContent(
            store: store,
            maxVisibleComments: maxVisibleComments,
            showAllComments: showAllComments,
            loadMoreComments: loadMoreComments
        )
            .padding(.horizontal, style.horizontalPadding)
            .padding(.top, 8)
    }
}
