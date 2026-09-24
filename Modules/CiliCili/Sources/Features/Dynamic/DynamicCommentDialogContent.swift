import SwiftUI

struct DynamicCommentDialogContent: View {
    let rootComment: Comment
    let focusReply: Comment
    let replyToComment: (Comment) -> Void
    @ObservedObject var replyStore: DynamicCommentReplyStore

    var body: some View {
        let snapshot = replyStore.dialogSnapshot(for: rootComment, reply: focusReply)

        DynamicCommentDialogStateContent(
            snapshot: snapshot,
            rootComment: rootComment,
            focusReply: focusReply,
            replyToComment: replyToComment,
            replyStore: replyStore
        )
    }
}

private struct DynamicCommentDialogStateContent: View {
    let snapshot: DynamicCommentDialogSnapshot
    let rootComment: Comment
    let focusReply: Comment
    let replyToComment: (Comment) -> Void
    @ObservedObject var replyStore: DynamicCommentReplyStore

    var body: some View {
        if snapshot.items.isEmpty && snapshot.state.isLoading {
            CommentLoadingSkeletonList(count: 3)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        } else if snapshot.items.isEmpty, case .failed(let message) = snapshot.state {
            DynamicCommentErrorView(message: message, retry: reloadDialog)
                .padding(16)
        } else if snapshot.items.isEmpty {
            EmptyStateView(title: "暂无对话", systemImage: "text.bubble", message: "暂时没有找到这条回复的上下文。")
                .padding(16)
        } else {
            DynamicCommentDialogLoadedList(
                snapshot: snapshot,
                items: snapshot.items,
                focusReply: focusReply,
                replyToComment: replyToComment,
                reloadDialog: reloadDialog
            )
        }
    }

    private func reloadDialog() {
        Task { await replyStore.reloadDialog(for: rootComment, reply: focusReply) }
    }
}

private struct DynamicCommentDialogLoadedList: View {
    let snapshot: DynamicCommentDialogSnapshot
    let items: [DynamicCommentDialogItem]
    let focusReply: Comment
    let replyToComment: (Comment) -> Void
    let reloadDialog: () -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                DynamicCommentDialogRow(
                    item: item,
                    isFocused: item.id == focusReply.id,
                    reply: { replyToComment(item.reply) }
                )
                    .padding(.horizontal, 16)

                Divider()
                    .padding(.leading, 66)
            }

            if case .failed(let message) = snapshot.state {
                DynamicCommentErrorView(message: message, retry: reloadDialog)
                    .padding(16)
            }
        }
    }
}
