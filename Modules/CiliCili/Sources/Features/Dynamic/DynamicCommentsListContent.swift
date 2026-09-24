import SwiftUI

struct DynamicCommentsListContent: View {
    @ObservedObject var viewModel: DynamicCommentsViewModel
    let highlightedCommentID: Int?
    let showReplies: (Comment) -> Void
    let dividerHorizontalPadding: CGFloat
    var replyToComment: ((Comment) -> Void)? = nil

    init(
        viewModel: DynamicCommentsViewModel,
        highlightedCommentID: Int?,
        showReplies: @escaping (Comment) -> Void,
        dividerHorizontalPadding: CGFloat = 14,
        replyToComment: ((Comment) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.highlightedCommentID = highlightedCommentID
        self.showReplies = showReplies
        self.dividerHorizontalPadding = dividerHorizontalPadding
        self.replyToComment = replyToComment
    }

    @ViewBuilder
    var body: some View {
        if !viewModel.canLoadComments {
            EmptyStateView(title: "暂不支持评论", systemImage: "bubble.left", message: "这条动态没有返回评论入口。")
                .padding(16)
        } else if viewModel.comments.isEmpty && viewModel.state.isLoading {
            CommentLoadingSkeletonList(count: 4)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        } else if viewModel.comments.isEmpty, case .failed(let message) = viewModel.state {
            DynamicCommentErrorView(message: message) {
                Task { await viewModel.reload() }
            }
            .padding(14)
        } else if viewModel.comments.isEmpty {
            DynamicCommentPlainEmptyStateView(
                title: "暂无评论",
                systemImage: "bubble.left",
                message: "这里还没有可展示的评论。"
            )
            .padding(14)
        } else {
            DynamicCommentsLoadedList(
                viewModel: viewModel,
                highlightedCommentID: highlightedCommentID,
                showReplies: showReplies,
                dividerHorizontalPadding: dividerHorizontalPadding,
                replyToComment: replyToComment
            )
        }
    }
}

private struct DynamicCommentsLoadedList: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    @ObservedObject var viewModel: DynamicCommentsViewModel
    let highlightedCommentID: Int?
    let showReplies: (Comment) -> Void
    let dividerHorizontalPadding: CGFloat
    let replyToComment: ((Comment) -> Void)?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.commentItems) { item in
                DynamicCommentRow(
                    item: item,
                    showReplies: { showReplies(item.comment) },
                    replyToComment: replyToComment.map { action in
                        { action(item.comment) }
                    }
                )
                .padding(.horizontal, 14)
                .background(
                    item.id == highlightedCommentID ? appTintColor.opacity(0.10) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .id(item.id)

                Divider()
                    .padding(.horizontal, dividerHorizontalPadding)
            }

            DynamicCommentsFooter(viewModel: viewModel)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
    }
}
