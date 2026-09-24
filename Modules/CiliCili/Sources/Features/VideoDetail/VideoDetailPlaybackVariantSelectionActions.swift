import Foundation
import OSLog

extension VideoDetailViewModel {
    func selectPlayVariant(_ variant: PlayVariant) {
        guard !isPlaybackInvalidatedForNavigation else { return }
        guard variant.isPlayable else {
            guard variant.isAvailabilityPending else { return }
            resolveAdvertisedPlayVariant(variant)
            return
        }
        guard selectedPlayVariant?.id != variant.id else { return }
        let initialResumeTime = currentPlaybackResumeTime()
        let initialShouldResumePlayback = currentPlaybackIntent()
        let initialPlaybackRate = stablePlayerViewModel?.playbackRate ?? .x10
        let cid = selectedCID
        let token = beginManualPlayVariantSelection(for: variant)
        if switchPlayVariantInPlaceIfPossible(variant) {
            clearPlayVariantSwitchIfCurrent(token)
            return
        }
        beginPlayVariantSwitch(for: variant, token: token)
        schedulePlayVariantSwitchTask(
            to: variant,
            cid: cid,
            token: token,
            initialResumeTime: initialResumeTime,
            initialShouldResumePlayback: initialShouldResumePlayback,
            initialPlaybackRate: initialPlaybackRate
        )
    }

    private func resolveAdvertisedPlayVariant(_ variant: PlayVariant) {
        guard let cid = selectedCID else { return }
        let token = beginManualPlayVariantSelection(for: variant)
        beginPlayVariantSwitch(for: variant, token: token)
        let bvid = detail.bvid
        let page = selectedPageNumber
        let requestedQuality = variant.quality

        playVariantSwitchTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            defer {
                self.clearPlayVariantSwitchIfCurrent(token)
            }

            do {
                let requestedData = try await self.fetchPlayURLWithTimeout(
                    timeout: self.playURLFullRecoveryTimeoutNanoseconds
                ) { [self] in
                    if self.detail.isPGCEpisode {
                        return try await self.api.fetchPgcPlayURL(
                            bvid: bvid,
                            cid: cid,
                            seasonID: self.detail.pgcSeasonID,
                            epID: self.detail.pgcEpisodeID,
                            preferredQuality: requestedQuality
                        )
                    }
                    return try await self.api.fetchPlayURL(
                        bvid: bvid,
                        cid: cid,
                        page: page,
                        preferredQuality: requestedQuality
                    )
                }
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page),
                      self.playVariantSwitchToken == token,
                      self.pendingPlayVariantID == variant.id
                else { return }

                let mergedData = self.currentPlayURLData?.mergingPlayableStreams(from: requestedData) ?? requestedData
                let mergedVariants = self.sortedPlayVariants(self.playVariants(from: mergedData))
                guard let resolvedVariant = mergedVariants.first(where: {
                    $0.quality == requestedQuality && $0.isPlayable
                }) else {
                    self.playbackFallbackMessage = "该清晰度当前账号或设备不可用"
                    PlayerMetricsLog.record(
                        .qualitySupplement,
                        metricsID: bvid,
                        title: self.detail.title,
                        message: "manualAvailability unavailable q\(requestedQuality)"
                    )
                    return
                }

                self.currentPlayURLData = mergedData
                self.applyVideoListenAudioVariants(from: mergedData)
                self.playVariants = mergedVariants
                PlayerMetricsLog.record(
                    .qualitySupplement,
                    metricsID: bvid,
                    title: self.detail.title,
                    message: "manualAvailability resolved q\(requestedQuality)"
                )
                self.clearPlayVariantSwitchIfCurrent(token)
                self.selectPlayVariant(resolvedVariant)
            } catch {
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page),
                      self.playVariantSwitchToken == token
                else { return }
                self.playbackFallbackMessage = "清晰度加载失败，请稍后重试"
                PlayerMetricsLog.record(
                    .qualitySupplement,
                    metricsID: bvid,
                    title: self.detail.title,
                    message: "manualAvailability failed q\(requestedQuality) error=\(error.localizedDescription)"
                )
            }
        }
    }

    func switchPlayVariantInPlaceIfPossible(_ variant: PlayVariant) -> Bool {
        if playbackContentMode == .audioOnly,
           let playerViewModel = stablePlayerViewModel,
           selectedPlayVariant?.audioURL == variant.audioURL,
           selectedPlayVariant?.audioStream == variant.audioStream {
            selectedPlayVariant = variant
            stablePlayerIdentity = playerIdentity(for: variant)
            playbackFallbackMessage = nil
            observePlaybackErrors(playerViewModel, variant: variant)
            logSelectedPlayVariant(
                variant,
                availableVariants: playVariants,
                source: "audioOnlyQualitySelection"
            )
            return true
        }

        guard let playerViewModel = stablePlayerViewModel,
              playerViewModel.engineDiagnostics.hlsVideoVariantCount > 1,
              playerViewModel.preferVideoRenditionInCurrentItem(variant)
        else { return false }

        selectedPlayVariant = variant
        stablePlayerIdentity = playerIdentity(for: variant)
        playbackFallbackMessage = nil
        observePlaybackErrors(playerViewModel, variant: variant)
        logSelectedPlayVariant(
            variant,
            availableVariants: playVariants,
            source: "manualInPlaceQuality"
        )
        PlayerMetricsLog.record(
            .qualitySupplement,
            metricsID: detail.bvid,
            title: detail.title,
            message: "manualInPlaceQuality q\(variant.quality)"
        )
        return true
    }

    func clearPlayVariantSwitchIfCurrent(_ token: UUID) {
        guard playVariantSwitchToken == token else { return }
        playVariantSwitchTask = nil
        playVariantSwitchToken = nil
        pendingPlayVariantID = nil
        isSwitchingPlayQuality = false
    }

}
