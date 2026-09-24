import Foundation

extension VideoDetailViewModel {
    func isCurrentVideoContext(
        aid: Int? = nil,
        bvid: String? = nil,
        ownerMID: Int? = nil
    ) -> Bool {
        guard !Task.isCancelled, !isPlaybackInvalidatedForNavigation else { return false }
        if let aid, detail.aid != aid {
            return false
        }
        if let bvid, detail.bvid != bvid {
            return false
        }
        if let ownerMID, detail.owner?.mid != ownerMID {
            return false
        }
        return true
    }

    func isCurrentPlaybackContext(
        bvid: String? = nil,
        cid: Int? = nil,
        page: Int? = nil
    ) -> Bool {
        guard isCurrentVideoContext(bvid: bvid) else { return false }
        if let cid, selectedCID != cid {
            return false
        }
        if let page, selectedPageNumber != page {
            return false
        }
        return true
    }
}
