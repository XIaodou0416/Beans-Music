import SwiftUI

struct DynamicCommentsFooter: View {
    @ObservedObject var viewModel: DynamicCommentsViewModel

    @ViewBuilder
    var body: some View {
        if viewModel.loadMoreState.isLoading {
            CommentLoadingSkeletonRow()
                .padding(.vertical, 10)
        } else if case .failed(let message) = viewModel.loadMoreState {
            Button(action: loadMore) {
                Label("评论加载失败，点按重试", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .accessibilityHint(message)
        } else if viewModel.hasMoreComments {
            Color.clear
                .frame(height: 18)
                .dynamicCommentLoadMoreTrigger(id: viewModel.commentItems.last?.id ?? -1) {
                    await viewModel.loadMore()
                }
        } else {
            Text("没有更多评论了")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
    }

    private func loadMore() {
        Task { await viewModel.loadMore() }
    }
}

private extension View {
    func dynamicCommentLoadMoreTrigger(id: Int, action: @escaping () async -> Void) -> some View {
        onAppear {
            Task {
                await action()
            }
        }
        .id(id)
    }
}
