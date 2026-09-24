import Foundation

extension VideoDetailViewModel {
    func scheduleHLSRenditionPrebuildAfterFirstFrameIfNeeded(
        startupVariant: PlayVariant?,
        targetVariant: PlayVariant?,
        cid: Int?,
        page: Int?
    ) {
        cancelHLSRenditionPrebuildTask(advancesGeneration: false)
        let prebuildGeneration = advanceHLSRenditionPrebuildGeneration()
        guard playbackContentMode == .video,
              !isPlaybackInvalidatedForNavigation,
              let cid,
              let startupVariant,
              startupVariant.audioURL != nil,
              hlsRenditionPrebuildLimit > 0
        else { return }
        let bvid = detail.bvid
        let candidates = hlsRenditionPrebuildCandidates(
            startupVariant: startupVariant,
            targetVariant: targetVariant
        )
        guard !candidates.isEmpty else { return }
        recordHLSRenditionPrebuildQueued(candidates)
        hlsRenditionPrebuildTask = Task(priority: .utility) { [weak self, candidates] in
            guard let self else { return }
            await self.runHLSRenditionPrebuild(
                candidates: candidates,
                bvid: bvid,
                cid: cid,
                page: page,
                generation: prebuildGeneration
            )
        }
    }
}
