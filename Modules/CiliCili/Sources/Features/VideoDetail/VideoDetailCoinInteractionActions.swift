import Foundation

extension VideoDetailViewModel {
    @discardableResult
    func addCoin(count requestedCount: Int = 1) async -> Bool {
        guard let aid = detail.aid else {
            interactionMessage = "没有找到视频 AV 号，无法投币"
            return false
        }
        let remainingCoinCount = max(0, 2 - interactionState.coinCount)
        guard remainingCoinCount > 0 else {
            interactionMessage = "这个视频已经投过 2 枚币了"
            return false
        }
        guard (1...remainingCoinCount).contains(requestedCount) else {
            interactionMessage = "当前最多还能投 \(remainingCoinCount) 枚币"
            return false
        }
        let bvid = detail.bvid
        let previousCoinCount = interactionState.coinCount
        let expectedCoinCount = previousCoinCount + requestedCount
        let shouldLike = interactionState.isLiked
        return await performInteractionMutation(
            .coin,
            isCurrent: { isCurrentVideoContext(aid: aid, bvid: bvid) }
        ) {
            do {
                try await api.addVideoCoin(
                    aid: aid,
                    multiply: requestedCount,
                    selectLike: shouldLike
                )
                guard isCurrentVideoContext(aid: aid, bvid: bvid) else { throw CancellationError() }
                interactionState.coinCount = min(2, max(interactionState.coinCount, expectedCoinCount))
            } catch {
                guard isCurrentVideoContext(aid: aid, bvid: bvid) else { throw CancellationError() }
                guard await recoverAmbiguousCoinMutationIfNeeded(
                    error,
                    expectedCoinCount: expectedCoinCount,
                    aid: aid,
                    bvid: bvid
                ) else {
                    throw error
                }
            }
        }
    }
}
