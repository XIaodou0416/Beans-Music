import Foundation

extension VideoDetailViewModel {
    func loadUploaderProfile(mid capturedMID: Int? = nil, bvid capturedBVID: String? = nil, aid capturedAID: Int? = nil) async {
        let mid = capturedMID ?? detail.owner?.mid
        let bvid = capturedBVID ?? detail.bvid
        let aid = capturedAID ?? detail.aid
        guard let mid, mid > 0 else {
            guard isCurrentVideoContext(aid: aid, bvid: bvid) else { return }
            uploaderProfile = nil
            interactionState.isFollowing = false
            return
        }

        do {
            let profile = try await api.fetchUploaderProfile(mid: mid)
            guard !Task.isCancelled,
                  isCurrentVideoContext(aid: aid, bvid: bvid, ownerMID: mid)
            else { return }
            uploaderProfile = profile
            interactionState.isFollowing = profile.following == true
        } catch {
            guard !Task.isCancelled,
                  isCurrentVideoContext(aid: aid, bvid: bvid, ownerMID: mid)
            else { return }
            uploaderProfile = nil
            interactionState.isFollowing = false
        }
    }
}
