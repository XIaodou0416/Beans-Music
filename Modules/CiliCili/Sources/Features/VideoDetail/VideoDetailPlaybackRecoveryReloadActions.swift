import Foundation

extension VideoDetailViewModel {
    func playbackFailurePrefersPlayURLReload(_ message: String) -> Bool {
        message.contains("播放地址已过期")
            || message.contains("重新获取播放地址")
    }

    func playbackFailurePrefersPlayURLReload(
        _ message: String,
        reason: HLSBridgeFailureReason?
    ) -> Bool {
        if let reason {
            switch reason.category {
            case .authDenied, .urlExpired:
                return true
            case .rangeUnsupported, .rateLimited, .serverUnavailable, .timeout, .network,
                 .invalidResponse, .codecUnsupported, .hardwareDecodeRejected, .decoderFailed,
                 .terminalStall, .cancelled, .unknown:
                break
            }
        }
        return playbackFailurePrefersPlayURLReload(message)
    }

    @discardableResult
    func schedulePlaybackRecoveryReload(
        after message: String,
        failedVariant: PlayVariant,
        reason: HLSBridgeFailureReason? = nil
    ) -> Bool {
        guard playbackRecoveryAttemptCount < Self.playbackRecoveryReloadAttemptLimit,
              !playURLState.isLoading,
              !isPlaybackInvalidatedForNavigation
        else { return false }
        playbackRecoveryAttemptCount += 1
        let attempt = playbackRecoveryAttemptCount
        let resumeTime = currentPlaybackResumeTime()
        let shouldResumePlayback = currentPlaybackIntent()
        let playbackRate = stablePlayerViewModel?.playbackRate ?? .x10
        let aid = detail.aid
        let bvid = detail.bvid
        let cid = selectedCID
        let failedVariantID = failedVariant.id
        cancelPlaybackRecoveryReloadTask(advancesGeneration: false)
        let generation = advancePlaybackRecoveryReloadGeneration()
        playbackFallbackMessage = playbackRecoveryReloadMessage(
            attempt: attempt,
            message: message,
            reason: reason
        )
        PlayerMetricsLog.record(
            .failed,
            metricsID: bvid,
            title: detail.title,
            message: "recoveryReload attempt=\(attempt) q=\(failedVariant.quality) \(playbackRecoveryReasonDescription(reason)) error=\(message)"
        )
        recordPlaybackRecoveryStage(
            "reloadScheduled",
            status: "started",
            attempt: attempt,
            failedVariant: failedVariant,
            reason: reason,
            extraParts: [
                "resume=\(String(format: "%.2fs", resumeTime))",
                "autoplay=\(shouldResumePlayback)"
            ]
        )
        selectedPlayVariant = nil
        stablePlayerViewModel?.stop()
        stablePlayerViewModel = nil
        clearPlaybackTransitionPlayer()
        stablePlayerIdentity = nil
        stablePlayerErrorCancellable = nil
        stablePlayerFirstFrameCancellable = nil
        syncPlayerIdentityRenderStore()
        finishPlaybackStartupWaiters(with: nil)
        playURLState = .idle
        playbackRecoveryReloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.clearPlaybackRecoveryReloadTaskIfCurrent(generation: generation)
            }
            guard self.isCurrentPlaybackRecoveryReload(
                generation: generation,
                aid: aid,
                bvid: bvid,
                cid: cid,
                failedVariantID: failedVariantID,
                allowsClearedVariant: true
            ) else { return }
            await PlayURLCache.shared.invalidate(bvid: bvid)
            await VideoPreloadCenter.shared.invalidatePlayURLCache(for: bvid)
            await self.api.clearCachedPlayURLFailures(bvid: bvid)
            self.recordPlaybackRecoveryStage(
                "cacheInvalidated",
                status: "done",
                attempt: attempt,
                failedVariant: failedVariant,
                reason: reason
            )
            guard self.isCurrentPlaybackRecoveryReload(
                generation: generation,
                aid: aid,
                bvid: bvid,
                cid: cid,
                failedVariantID: failedVariantID,
                allowsClearedVariant: true
            ) else { return }
            self.cancelStartupPlayURLTask()
            self.recordPlaybackRecoveryStage(
                "playURLReloadStart",
                status: "started",
                attempt: attempt,
                failedVariant: failedVariant,
                reason: reason
            )
            await self.loadPlayURL(mode: .playbackRecovery)
            guard !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.playbackRecoveryReloadGeneration == generation,
                  self.isCurrentVideoContext(aid: aid, bvid: bvid),
                  self.selectedCID == cid,
                  self.selectedPlayVariant?.isPlayable == true
            else { return }
            self.recordPlaybackRecoveryStage(
                "playerRecreated",
                status: "started",
                attempt: attempt,
                failedVariant: failedVariant,
                reason: reason,
                extraParts: [
                    "selectedQ=\(self.selectedPlayVariant?.quality ?? 0)"
                ]
            )
            self.updateStablePlayerViewModelIfNeeded(
                resumeTimeOverride: resumeTime,
                shouldResumePlayback: shouldResumePlayback,
                playbackRateOverride: playbackRate
            )
        }
        return true
    }

    private func playbackRecoveryReloadMessage(
        attempt: Int,
        message: String,
        reason: HLSBridgeFailureReason?
    ) -> String {
        if let reason {
            switch reason.category {
            case .authDenied:
                return "播放鉴权失效，正在重新获取播放地址（第 \(attempt) 次）"
            case .urlExpired:
                return "播放地址可能已过期，正在重新获取播放地址（第 \(attempt) 次）"
            case .rateLimited:
                return "当前 CDN 被临时限制，正在换线重试（第 \(attempt) 次）"
            case .rangeUnsupported, .serverUnavailable, .timeout, .network, .invalidResponse,
                 .codecUnsupported, .hardwareDecodeRejected, .decoderFailed, .terminalStall,
                 .cancelled, .unknown:
                break
            }
        }
        return playbackFailurePrefersPlayURLReload(message)
            ? "播放地址可能已过期，正在重新获取播放地址（第 \(attempt) 次）"
            : "当前线路播放失败，正在重新获取播放地址（第 \(attempt) 次）"
    }

    private func playbackRecoveryReasonDescription(_ reason: HLSBridgeFailureReason?) -> String {
        guard let reason else { return "reason=unknown" }
        var parts = [
            "reason=\(reason.category.rawValue)",
            "layer=\(reason.layer.rawValue)"
        ]
        if let statusCode = reason.statusCode {
            parts.append("status=\(statusCode)")
        }
        if let host = reason.urlHost, !host.isEmpty {
            parts.append("host=\(host)")
        }
        if let rangeDescription = reason.rangeDescription, !rangeDescription.isEmpty {
            parts.append("range=\(rangeDescription)")
        }
        return parts.joined(separator: " ")
    }
}
