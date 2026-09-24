import SwiftUI

struct DynamicCommentsSheetContent: View {
    @ObservedObject var viewModel: DynamicCommentsViewModel
    let highlightedCommentID: Int?
    let selectSort: @MainActor @Sendable (CommentSort) -> Void
    let showReplies: (Comment) -> Void
    var dividerHorizontalPadding: CGFloat = 14
    var replyToComment: ((Comment) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DynamicCommentsHeader(
                replyCount: viewModel.displayedReplyCount,
                selectedSort: Binding(
                    get: { viewModel.selectedSort },
                    set: selectSort
                )
            )
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 6)

            DynamicCommentsListContent(
                viewModel: viewModel,
                highlightedCommentID: highlightedCommentID,
                showReplies: showReplies,
                dividerHorizontalPadding: dividerHorizontalPadding,
                replyToComment: replyToComment
            )
        }
    }
}
