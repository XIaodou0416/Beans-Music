import Foundation

@MainActor
struct VideoDetailReplySheetActions {
    weak var viewModel: VideoDetailViewModel?

    func loadReplies(for comment: Comment) async {
        await viewModel?.loadReplies(for: comment)
    }

    func reloadReplies(for comment: Comment) async {
        await viewModel?.reloadReplies(for: comment)
    }

    func loadMoreReplies(for comment: Comment) async {
        await viewModel?.loadMoreReplies(for: comment)
    }

    func loadDialog(for rootComment: Comment, reply: Comment) async {
        await viewModel?.loadDialog(for: rootComment, reply: reply)
    }

    func reloadDialog(for rootComment: Comment, reply: Comment) async {
        await viewModel?.reloadDialog(for: rootComment, reply: reply)
    }
}
