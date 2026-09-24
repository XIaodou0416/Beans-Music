import SwiftUI

struct DynamicCommentRepliesContent: View {
    let rootComment: Comment
    @ObservedObject var replyStore: DynamicCommentReplyStore
    let highlightedReplyID: Int?
    let showDialog: (Comment) -> Void
    let replyToComment: (Comment) -> Void

    var body: some View {
        let snapshot = replyStore.repliesSnapshot(for: rootComment)

        DynamicCommentRepliesStateContent(
            snapshot: snapshot,
            rootComment: rootComment,
            replyStore: replyStore,
            highlightedReplyID: highlightedReplyID,
            showDialog: showDialog,
            replyToComment: replyToComment
        )
    }
}

private struct DynamicCommentRepliesStateContent: View {
    let snapshot: DynamicCommentRepliesSnapshot
    let rootComment: Comment
    @ObservedObject var replyStore: DynamicCommentReplyStore
    let highlightedReplyID: Int?
    let showDialog: (Comment) -> Void
    let replyToComment: (Comment) -> Void

    var body: some View {
        if snapshot.replies.isEmpty && snapshot.state.isLoading {
            CommentLoadingSkeletonList(count: 3)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        } else if snapshot.replies.isEmpty, case .failed(let message) = snapshot.state {
            DynamicCommentErrorView(message: message) {
                Task { await replyStore.reloadReplies(for: rootComment) }
            }
            .padding(16)
        } else if snapshot.replies.isEmpty {
            EmptyStateView(title: "暂无回复", systemImage: "bubble.left.and.bubble.right", message: "这条评论还没有可展示的回复。")
                .padding(16)
        } else {
            DynamicCommentRepliesLoadedList(
                snapshot: snapshot,
                replyItems: snapshot.replyItems,
                rootComment: rootComment,
                replyStore: replyStore,
                highlightedReplyID: highlightedReplyID,
                showDialog: showDialog,
                replyToComment: replyToComment
            )
        }
    }

    private func loadMoreReplies() {
        Task { await replyStore.loadMoreReplies(for: rootComment) }
    }
}

private struct DynamicCommentRepliesLoadedList: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let snapshot: DynamicCommentRepliesSnapshot
    let replyItems: [DynamicCommentReplyItem]
    let rootComment: Comment
    @ObservedObject var replyStore: DynamicCommentReplyStore
    let highlightedReplyID: Int?
    let showDialog: (Comment) -> Void
    let replyToComment: (Comment) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(replyItems) { replyItem in
                DynamicCommentReplyDetailRow(
                    item: replyItem,
                    showDialog: replyItem.canShowDialog ? {
                        showDialog(replyItem.reply)
                    } : nil,
                    reply: { replyToComment(replyItem.reply) }
                )
                .padding(.horizontal, 16)
                .background(
                    replyItem.id == highlightedReplyID ? appTintColor.opacity(0.10) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .id(replyItem.id)

                Divider()
            }

            DynamicCommentRepliesFooter(
                snapshot: snapshot,
                loadMore: loadMoreReplies
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func loadMoreReplies() {
        Task { await replyStore.loadMoreReplies(for: rootComment) }
    }
}

private struct DynamicCommentRepliesFooter: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let snapshot: DynamicCommentRepliesSnapshot
    let loadMore: () -> Void

    var body: some View {
        if snapshot.hasLoadedReplies, snapshot.state.isLoading {
            CommentLoadingSkeletonRow()
        } else if case .failed(let message) = snapshot.state {
            DynamicCommentErrorView(message: message, retry: loadMore)
        } else if snapshot.hasMoreReplies {
            Button(action: loadMore) {
                Label("查看更多回复", systemImage: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(appTintColor)
        }
    }
}
