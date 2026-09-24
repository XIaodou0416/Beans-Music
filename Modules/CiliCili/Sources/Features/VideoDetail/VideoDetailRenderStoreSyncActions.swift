import Foundation

extension VideoDetailViewModel {
    func syncAllRenderStores() {
        syncCommentsRenderStore()
        syncRelatedRenderStore()
        syncInteractionRenderStore()
        syncPlaybackRenderStore()
        syncCommentThreadRenderStore()
        syncFavoriteFolderRenderStore()
        syncDanmakuSettingsRenderStore()
        syncDanmakuRenderStore()
        syncNetworkDiagnosticsRenderStore()
        syncDescriptionRenderStore()
        syncPlayerIdentityRenderStore()
    }

    func syncCommentsRenderStore() {
        commentsRenderStore.update(
            detail: detail,
            comments: comments,
            state: commentState,
            loadMoreState: commentLoadMoreState,
            selectedSort: selectedCommentSort,
            didCompleteInitialLoad: didCompleteInitialCommentLoad,
            hasMoreComments: hasMoreComments
        )
    }

    func refreshDetailDisplayMetrics() {
        detailDisplayMetrics = VideoDetailDisplayMetrics(video: detail)
    }

    func refreshUploaderFanCountText() {
        let fanCount = uploaderProfile?.follower ?? uploaderProfile?.card?.fans
        uploaderFanCountText = "粉丝 \(BiliFormatters.compactCount(fanCount))"
    }

    func syncCommentThreadRenderStore() {
        commentThreadRenderStore.update(
            replyThreads: replyThreads,
            replyThreadStates: replyThreadStates,
            replyThreadHasMore: replyThreadHasMore,
            dialogThreads: dialogThreads,
            dialogThreadStates: dialogThreadStates
        )
    }

    func syncDanmakuRenderStore() {
        danmakuRenderStore.update(
            VideoDetailDanmakuRenderSnapshot(viewModel: self)
        )
    }
}
