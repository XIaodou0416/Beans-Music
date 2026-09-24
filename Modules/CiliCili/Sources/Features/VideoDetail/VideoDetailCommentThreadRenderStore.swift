import Combine
import Foundation

@MainActor
final class VideoDetailCommentThreadRenderStore: ObservableObject {
    @Published var snapshot = VideoDetailCommentThreadRenderSnapshot()
    var replyDisplayCache: [Int: VideoDetailCommentReplyDisplayCacheEntry] = [:]
    var dialogDisplayCache: [String: VideoDetailCommentDialogDisplayCacheEntry] = [:]

    func update(
        replyThreads: [Int: [Comment]],
        replyThreadStates: [Int: LoadingState],
        replyThreadHasMore: [Int: Bool],
        dialogThreads: [String: [Comment]],
        dialogThreadStates: [String: LoadingState]
    ) {
        setSnapshot(
            VideoDetailCommentThreadRenderSnapshot(
                replyThreads: replyThreads,
                replyThreadStates: replyThreadStates,
                replyThreadHasMore: replyThreadHasMore,
                dialogThreads: dialogThreads,
                dialogThreadStates: dialogThreadStates
            )
        )
    }

    private func setSnapshot(_ next: VideoDetailCommentThreadRenderSnapshot) {
        guard next.changeSignature != snapshot.changeSignature else { return }
        snapshot = next
    }
}
