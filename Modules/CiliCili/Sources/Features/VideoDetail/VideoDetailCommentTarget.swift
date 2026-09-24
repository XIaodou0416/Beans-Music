import Foundation

nonisolated struct VideoDetailCommentTarget: Hashable {
    let oid: String
    let type: Int
    let bvid: String
    let contextKey: String

    init?(detail: VideoItem) {
        let bvid = detail.bvid.trimmingCharacters(in: .whitespacesAndNewlines)
        if let aid = detail.aid, aid > 0 {
            self.oid = String(aid)
            self.type = 1
        } else if detail.isPGCEpisode,
                  let episodeID = detail.pgcEpisodeID,
                  episodeID > 0 {
            self.oid = String(episodeID)
            self.type = 33
        } else {
            return nil
        }
        self.bvid = bvid
        self.contextKey = [
            bvid,
            detail.cid.map(String.init) ?? "cid-",
            detail.pgcSeasonID.map { "ss\($0)" } ?? "ss-",
            detail.pgcEpisodeID.map { "ep\($0)" } ?? "ep-",
            "oid\(oid)",
            "type\(type)"
        ].joined(separator: "|")
    }
}

extension VideoDetailViewModel {
    var commentTarget: VideoDetailCommentTarget? {
        VideoDetailCommentTarget(detail: detail)
    }

    func isCurrentCommentTarget(_ target: VideoDetailCommentTarget) -> Bool {
        guard let current = commentTarget else { return false }
        return current == target
            && isCurrentVideoContext(bvid: target.bvid)
    }
}
