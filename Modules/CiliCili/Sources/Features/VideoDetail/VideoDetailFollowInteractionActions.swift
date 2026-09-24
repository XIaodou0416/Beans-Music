import Foundation

extension VideoDetailViewModel {
    @discardableResult
    func toggleFollow() async -> Bool {
        guard let mid = detail.owner?.mid, mid > 0 else {
            interactionMessage = "没有找到 UP 主 UID，无法关注"
            return false
        }
        let bvid = detail.bvid
        let targetState = !interactionState.isFollowing
        return await performInteractionMutation(
            .follow,
            isCurrent: { isCurrentVideoContext(bvid: bvid, ownerMID: mid) }
        ) {
            try await api.setUploaderFollowing(mid: mid, following: targetState)
            guard isCurrentVideoContext(bvid: bvid, ownerMID: mid) else { throw CancellationError() }
            interactionState.isFollowing = targetState
        }
    }
}
