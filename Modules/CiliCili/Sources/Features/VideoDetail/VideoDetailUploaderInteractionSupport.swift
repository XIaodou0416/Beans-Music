import Foundation

extension VideoDetailViewModel {
    var currentUploaderInteractionIdentity: String? {
        let mid = detail.owner?.mid ?? 0
        let aid = detail.aid ?? 0
        guard mid > 0 || aid > 0 else { return nil }
        return "\(mid)-\(aid)"
    }

    func fetchCurrentFullDetail() async throws -> VideoItem {
        if detail.bvid.hasPrefix("av"),
           let aid = detail.aid,
           aid > 0 {
            return try await api.fetchVideoDetail(aid: aid)
        }
        if !detail.bvid.isEmpty {
            return try await api.fetchVideoDetail(bvid: detail.bvid)
        }
        if let aid = detail.aid, aid > 0 {
            return try await api.fetchVideoDetail(aid: aid)
        }
        throw BiliAPIError.missingPayload
    }
}
