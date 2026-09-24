import Foundation

extension VideoDetailViewModel {
    func waitUntilHLSRenditionPrebuildCanStart(bvid: String, cid: Int) async -> Bool {
        let didPresentPlayback = await waitForFirstFrameOrFailure()
        guard didPresentPlayback,
              canContinueHLSRenditionPrebuild(bvid: bvid, cid: cid)
        else { return false }

        try? await Task.sleep(nanoseconds: Self.hlsRenditionPrebuildDelayNanoseconds)
        return canContinueHLSRenditionPrebuild(bvid: bvid, cid: cid)
            && stablePlayerViewModel != nil
    }

    func canContinueHLSRenditionPrebuild(bvid: String, cid: Int) -> Bool {
        !Task.isCancelled
            && !isPlaybackInvalidatedForNavigation
            && detail.bvid == bvid
            && selectedCID == cid
            && stablePlayerViewModel?.isBuffering != true
    }
}
