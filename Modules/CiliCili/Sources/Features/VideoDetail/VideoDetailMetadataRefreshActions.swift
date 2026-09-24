import Foundation

extension VideoDetailViewModel {
    func refreshDetailMetadata(
        preserving confirmation: VideoDetailInteractionMutationConfirmation? = nil
    ) async {
        let bvid = detail.bvid
        let aid = detail.aid
        do {
            let updated = try await fetchCurrentFullDetail()
            guard isCurrentVideoContext(aid: aid, bvid: bvid) else { return }
            detail = updated
            syncCommentsRenderStore()
            if selectedCID == nil {
                selectedCID = updated.pages?.first?.cid ?? updated.cid
            }
        } catch {
            // Interaction already succeeded, so stale stat counts should not block the UI update.
        }

        guard isCurrentVideoContext(aid: aid, bvid: bvid) else { return }
        await loadUploaderProfile(bvid: bvid, aid: aid)
        guard isCurrentVideoContext(aid: aid, bvid: bvid) else { return }
        await loadInteractionState(aid: aid, bvid: bvid, preserving: confirmation)
    }
}
