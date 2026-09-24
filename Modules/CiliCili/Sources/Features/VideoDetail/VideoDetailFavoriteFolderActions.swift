import Foundation

extension VideoDetailViewModel {
    func loadFavoriteFoldersForCurrentVideo(forceRefresh: Bool = false) async {
        guard !isPlaybackInvalidatedForNavigation else { return }
        guard let aid = detail.aid else {
            favoriteFolders = []
            favoriteFolderState = .failed("没有找到视频 AV 号，无法读取收藏夹")
            return
        }
        let bvid = detail.bvid
        guard forceRefresh || favoriteFolders.isEmpty else { return }
        favoriteFolderState = .loading
        do {
            let folders = try await api.fetchFavoriteFolders(for: aid)
            guard !isPlaybackInvalidatedForNavigation,
                  isCurrentVideoContext(aid: aid, bvid: bvid)
            else { return }
            favoriteFolders = folders
            favoriteFolderState = .loaded
            interactionState.isFavorited = folders.contains { $0.isFavorited }
            interactionMessage = nil
        } catch BiliAPIError.missingSESSDATA {
            guard !isPlaybackInvalidatedForNavigation,
                  isCurrentVideoContext(aid: aid, bvid: bvid)
            else { return }
            favoriteFolders = []
            favoriteFolderState = .failed("请先登录后再查看收藏夹")
        } catch {
            guard !isPlaybackInvalidatedForNavigation,
                  isCurrentVideoContext(aid: aid, bvid: bvid)
            else { return }
            favoriteFolders = []
            favoriteFolderState = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func setFavoriteFolders(selectedIDs: Set<Int>) async -> Bool {
        guard let aid = detail.aid else {
            interactionMessage = "没有找到视频 AV 号，无法收藏"
            return false
        }
        let bvid = detail.bvid
        let currentIDs = Set(favoriteFolders.filter(\.isFavorited).map(\.id))
        let addIDs = selectedIDs.subtracting(currentIDs)
        let removeIDs = currentIDs.subtracting(selectedIDs)
        guard !addIDs.isEmpty || !removeIDs.isEmpty else {
            interactionMessage = selectedIDs.isEmpty ? "未选择收藏夹" : "收藏夹未变化"
            return true
        }

        return await performInteractionMutation(
            .favorite,
            isCurrent: { !isPlaybackInvalidatedForNavigation && isCurrentVideoContext(aid: aid, bvid: bvid) }
        ) {
            try await api.setVideoFavorite(
                aid: aid,
                addFolderIDs: addIDs,
                removeFolderIDs: removeIDs
            )
            guard !isPlaybackInvalidatedForNavigation,
                  isCurrentVideoContext(aid: aid, bvid: bvid)
            else { throw CancellationError() }
            interactionState.isFavorited = !selectedIDs.isEmpty
            let folders = try await api.fetchFavoriteFolders(for: aid)
            guard !isPlaybackInvalidatedForNavigation,
                  isCurrentVideoContext(aid: aid, bvid: bvid)
            else { throw CancellationError() }
            favoriteFolders = folders
            favoriteFolderState = .loaded
            interactionMessage = selectedIDs.isEmpty ? "已取消收藏" : "已更新收藏夹"
        }
    }
}
