import Foundation

extension VideoDetailViewModel {
    func prepareForUserSeek(toProgress progress: Double) {
        guard !isPlaybackInvalidatedForNavigation,
              let variant = selectedPlayVariant,
              variant.isPlayable,
              let cid = selectedCID
        else { return }
        let duration = stablePlayerViewModel?.displayDuration
            ?? resumeDurationHint(for: cid)
            ?? detail.duration.map(TimeInterval.init)
        guard let duration, duration > 0 else { return }

        let targetTime = min(max(progress, 0), 1) * duration
        lastUserSeekAt = Date()
        guard playbackContentMode == .video else { return }
        let targetSegment = danmakuSegmentIndex(for: targetTime)
        let targetScheduleKey = danmakuScheduleKey(cid: cid, playbackTime: targetTime, segmentIndex: targetSegment)
        if lastDanmakuScheduleKey != targetScheduleKey {
            resetDanmakuLoad(clearItems: true)
        }
        isDanmakuUnderPlaybackLoad = true
        scheduleDanmakuSegmentsAfterFirstFrameIfNeeded(cid: cid, around: targetTime, force: false)

        let bvid = detail.bvid
        let page = selectedPageNumber
        let warmupPlan = seekWarmupPlan(primary: variant)
        let warmupVariants = warmupPlan.variants
        let warmupKey = seekWarmupKey(
            bvid: bvid,
            cid: cid,
            page: page,
            variants: warmupVariants,
            playbackTime: targetTime
        )
        guard shouldScheduleSeekWarmup(for: warmupKey) else { return }

        let formattedTargetTime = String(format: "%.2fs", targetTime)
        let token = UUID()
        let task = Task(priority: .userInitiated) { [weak self, warmupVariants, warmupPlan, formattedTargetTime] in
            defer {
                Task { @MainActor [weak self] in
                    self?.clearSeekWarmupIfCurrent(for: warmupKey, token: token)
                }
            }
            let didWarm = await VideoPreloadCenter.shared.warmVariantsAroundSeek(
                warmupVariants,
                bvid: bvid,
                cid: cid,
                page: page,
                playbackTime: targetTime
            )
            await MainActor.run {
                guard let self,
                      !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.seekWarmupTokens[warmupKey] == token,
                      self.detail.bvid == bvid,
                      self.selectedCID == cid
                else { return }
                PlayerMetricsLog.record(
                    .seek,
                    metricsID: bvid,
                    title: self.detail.title,
                    message: "warm target=\(formattedTargetTime) q=\(Self.hlsQualitySummary(warmupVariants.map(\.quality))) limit=\(warmupPlan.variantLimit) profile=\(self.playbackAdaptationProfile.diagnosticTitle) reason=\(warmupPlan.pressureReason) \(didWarm ? "hit" : "timeout")"
                )
                self.finishSeekWarmup(for: warmupKey, token: token, didWarm: didWarm)
            }
        }
        seekWarmupTokens[warmupKey] = token
        seekWarmupTasks[warmupKey] = task
        seekWarmupTaskOrder.append(warmupKey)
    }

}
