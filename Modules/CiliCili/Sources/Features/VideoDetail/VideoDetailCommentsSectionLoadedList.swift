import SwiftUI

struct CommentsSectionLoadedList: View {
    @ObservedObject var store: VideoDetailCommentsRenderStore
    let style: CommentSectionStyle
    let maxVisibleComments: Int?
    let actions: VideoDetailCommentsSectionActions

    private var visibleCommentItems: [VideoDetailCommentDisplayItem] {
        guard let maxVisibleComments else { return store.commentItems }
        return Array(store.commentItems.prefix(maxVisibleComments))
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(visibleCommentItems) { item in
                CommentRow(
                    item: item,
                    style: style,
                    showReplies: {
                        actions.showReplies(item.comment)
                    },
                    replyToComment: actions.replyToComment.map { action in
                        { action(item.comment) }
                    }
                )
                .equatable()
                .padding(.horizontal, style.horizontalPadding)

                Divider()
                    .padding(.horizontal, 14)
            }

            CommentsSectionLoadedListFooter(
                store: store,
                style: style,
                maxVisibleComments: maxVisibleComments,
                showAllComments: actions.showAllComments,
                loadMoreComments: actions.loadMoreComments
            )
        }
    }
}
