import Foundation

extension VideoDetailViewModel {
    func warmHLSRenditionPrebuildCandidate(
        _ candidate: PlayVariant,
        bvid: String,
        cid: Int,
        page: Int?,
        playbackTime: TimeInterval
    ) async -> Bool {
        if playbackTime > 0.25 {
            return await VideoPreloadCenter.shared.warmVariantAroundSeek(
                candidate,
                bvid: bvid,
                cid: cid,
                page: page,
                playbackTime: playbackTime,
                timeout: Self.hlsRenditionPrebuildTimeout
            )
        }

        return await VideoPreloadCenter.shared.warmVariantAndWaitCached(
            candidate,
            bvid: bvid,
            cid: cid,
            page: page,
            delay: 0,
            timeout: Self.hlsRenditionPrebuildTimeout
        )
    }
}
