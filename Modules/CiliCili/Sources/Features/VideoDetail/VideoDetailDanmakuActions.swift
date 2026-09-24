import Foundation

extension VideoDetailViewModel {
    func scheduleDanmakuLoadIfNeeded(force: Bool = false) {
        guard !isPlaybackInvalidatedForNavigation else { return }
        guard let cid = selectedCID else {
            resetDanmakuLoad(clearItems: true)
            return
        }
        guard isDanmakuEnabled else {
            resetDanmakuLoad(clearItems: true)
            return
        }
        let playbackTime = stablePlayerViewModel?.currentTime ?? 0
        scheduleDanmakuSegmentsAfterFirstFrameIfNeeded(cid: cid, around: playbackTime, force: force)
    }

    func updateDanmakuPlaybackTime(_ playbackTime: TimeInterval, underLoad: Bool = false) {
        guard !isPlaybackInvalidatedForNavigation,
              isDanmakuEnabled,
              let cid = selectedCID
        else { return }
        isDanmakuUnderPlaybackLoad = underLoad
        scheduleDanmakuSegmentsAfterFirstFrameIfNeeded(cid: cid, around: playbackTime, force: false)
    }

    func scheduleDanmakuSegmentsAfterFirstFrameIfNeeded(cid: Int, around playbackTime: TimeInterval, force: Bool) {
        guard stablePlayerViewModel?.hasPresentedPlayback != true else {
            scheduleDanmakuSegments(cid: cid, around: playbackTime, force: force)
            return
        }

        if force {
            resetDanmakuLoad(clearItems: true)
        }
        danmakuStartupLoadTask?.cancel()
        let token = UUID()
        let generation = danmakuLoadGeneration
        danmakuStartupLoadToken = token
        danmakuStartupLoadTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                self.clearDanmakuStartupLoadTaskIfCurrent(token)
            }
            guard let release = await self.waitForPlaybackStartupRelease(acceptsFailure: false),
                  case .firstFrame = release,
                  !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.selectedCID == cid,
                  self.isDanmakuEnabled,
                  self.danmakuLoadGeneration == generation
            else { return }
            let currentPlaybackTime = self.stablePlayerViewModel?.currentTime ?? playbackTime
            self.scheduleDanmakuSegments(
                cid: cid,
                around: currentPlaybackTime,
                force: false,
                generation: generation
            )
        }
    }
}
