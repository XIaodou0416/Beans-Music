import SwiftUI

struct CommentsSectionLoadedListFooterContent: View {
    @ObservedObject var store: VideoDetailCommentsRenderStore
    let maxVisibleComments: Int?
    let showAllComments: (() -> Void)?
    let loadMoreComments: () async -> Void

    var body: some View {
        if maxVisibleComments != nil {
            CommentsSectionPreviewFooter(
                store: store,
                showAllComments: showAllComments
            )
        } else {
            CommentsSectionLoadMoreFooter(
                store: store,
                maxVisibleComments: maxVisibleComments,
                loadMoreComments: loadMoreComments
            )
        }
    }
}
