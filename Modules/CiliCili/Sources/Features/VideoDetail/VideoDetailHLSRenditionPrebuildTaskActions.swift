import Foundation

extension VideoDetailViewModel {
    func runHLSRenditionPrebuild(
        candidates: [PlayVariant],
        bvid: String,
        cid: Int,
        page: Int?,
        generation: Int
    ) async {
        defer {
            clearHLSRenditionPrebuildTaskIfCurrent(generation: generation)
        }
        guard !Task.isCancelled,
              !isPlaybackInvalidatedForNavigation,
              hlsRenditionPrebuildGeneration == generation,
              await waitUntilHLSRenditionPrebuildCanStart(bvid: bvid, cid: cid),
              !Task.isCancelled,
              !isPlaybackInvalidatedForNavigation,
              hlsRenditionPrebuildGeneration == generation
        else { return }

        let playbackTime = currentPlaybackResumeTime()
        for (index, candidate) in candidates.enumerated() {
            guard !Task.isCancelled,
                  !isPlaybackInvalidatedForNavigation,
                  hlsRenditionPrebuildGeneration == generation,
                  canContinueHLSRenditionPrebuild(bvid: bvid, cid: cid)
            else { break }
            if index > 0 {
                try? await Task.sleep(nanoseconds: Self.hlsRenditionPrebuildStepNanoseconds)
                guard !Task.isCancelled,
                      !isPlaybackInvalidatedForNavigation,
                      hlsRenditionPrebuildGeneration == generation,
                      canContinueHLSRenditionPrebuild(bvid: bvid, cid: cid)
                else { break }
            }
            let didWarm = await warmHLSRenditionPrebuildCandidate(
                candidate,
                bvid: bvid,
                cid: cid,
                page: page,
                playbackTime: playbackTime
            )
            guard !Task.isCancelled,
                  !isPlaybackInvalidatedForNavigation,
                  hlsRenditionPrebuildGeneration == generation
            else { break }
            recordHLSRenditionPrebuildResult(candidate: candidate, didWarm: didWarm)
        }
    }
}
