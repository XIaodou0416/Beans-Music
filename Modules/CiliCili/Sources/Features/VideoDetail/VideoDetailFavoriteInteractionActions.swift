import Foundation

extension VideoDetailViewModel {
    @discardableResult
    func toggleFavorite() async -> Bool {
        guard let aid = detail.aid else {
            interactionMessage = "没有找到视频 AV 号，无法收藏"
            return false
        }
        let targetState = !interactionState.isFavorited
        return await performInteractionMutation(.favorite) {
            try await api.setVideoFavorite(aid: aid, favorited: targetState)
            interactionState.isFavorited = targetState
        }
    }
}
