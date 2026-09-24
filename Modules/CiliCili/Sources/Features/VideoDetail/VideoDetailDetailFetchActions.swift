import Foundation

extension VideoDetailViewModel {
    var detailLoadIdentity: VideoDetailLoadIdentity {
        if detail.bvid.hasPrefix("av"),
           let aid = detail.aid,
           aid > 0 {
            return .aid(aid)
        }
        if !detail.bvid.isEmpty {
            return .bvid(detail.bvid)
        }
        if let aid = detail.aid, aid > 0 {
            return .aid(aid)
        }
        return .bvid(detail.bvid)
    }

    func fetchFullDetail(identity: VideoDetailLoadIdentity, priority: TaskPriority) async throws -> VideoItem {
        switch identity {
        case .bvid(let bvid):
            if !playbackOptions.usesStartupCaches {
                return try await api.fetchVideoDetail(bvid: bvid, bypassesCache: true)
            }
            return try await VideoPreloadCenter.shared.detail(
                for: bvid,
                api: api,
                priority: priority
            )
        case .aid(let aid):
            return try await api.fetchVideoDetail(aid: aid)
        }
    }

    func isCurrentDetailLoadIdentity(_ identity: VideoDetailLoadIdentity) -> Bool {
        detailLoadIdentity == identity
    }
}
