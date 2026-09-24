import Combine
import Foundation

@MainActor
final class VideoDetailCommentsRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailCommentsRenderSnapshot()
    private var deferredSnapshot = VideoDetailDeferredValue<VideoDetailCommentsRenderSnapshot>()

    var detail: VideoItem? { snapshot.detail }
    var comments: [Comment] { snapshot.comments }
    var commentItems: [VideoDetailCommentDisplayItem] { snapshot.commentItems }
    var state: LoadingState { snapshot.state }
    var loadMoreState: LoadingState { snapshot.loadMoreState }
    var selectedSort: CommentSort { snapshot.selectedSort }
    var didCompleteInitialLoad: Bool { snapshot.didCompleteInitialLoad }
    var hasMoreComments: Bool { snapshot.hasMoreComments }
    var shouldShowEmptyCommentsState: Bool { snapshot.shouldShowEmptyCommentsState }
    var shouldShowCommentReloadPrompt: Bool { snapshot.shouldShowCommentReloadPrompt }
    var replyCountText: String? { snapshot.replyCountText }

    func updateSnapshot(_ transform: (inout VideoDetailCommentsRenderSnapshot) -> Void) {
        var next = deferredSnapshot.pendingOrNil ?? snapshot
        transform(&next)
        setSnapshot(next)
    }

    func setSnapshot(_ next: VideoDetailCommentsRenderSnapshot) {
        guard let next = deferredSnapshot.submit(
            next,
            current: snapshot,
            isEquivalent: { $0.changeSignature == $1.changeSignature }
        ) else { return }
        snapshot = next
    }

    func setUpdatesDeferred(_ deferred: Bool) {
        guard let pending = deferredSnapshot.setDeferred(deferred),
              pending.changeSignature != snapshot.changeSignature
        else { return }
        snapshot = pending
    }
}
