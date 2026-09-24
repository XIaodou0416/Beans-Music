import Foundation

extension VideoDetailViewModel {
    func makeStablePlayerViewModel(
        variant: PlayVariant,
        alternateVideoRenditions: [PlayerVideoRenditionSource],
        resumeTime: TimeInterval
    ) -> PlayerStateViewModel {
        let isAudioOnly = playbackContentMode == .audioOnly
        let listenAudioVariant = isAudioOnly ? resolvedVideoListenAudioVariant : nil
        let playbackTitle: String = {
            guard isAudioOnly,
                  (detail.pages?.count ?? 0) > 1,
                  let part = selectedPage?.part?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !part.isEmpty
            else { return detail.title }
            return part
        }()
        return PlayerStateViewModel(
            videoURL: isAudioOnly ? nil : variant.videoURL,
            audioURL: listenAudioVariant?.url ?? variant.audioURL,
            videoStream: isAudioOnly ? nil : variant.videoStream,
            audioStream: listenAudioVariant?.stream ?? variant.audioStream,
            alternateVideoRenditions: isAudioOnly ? [] : alternateVideoRenditions,
            title: playbackTitle,
            authorName: detail.owner?.name,
            referer: "https://www.bilibili.com/video/\(detail.bvid)",
            durationHint: resumeDurationHint(for: selectedCID),
            resumeTime: resumeTime,
            startupResumePolicy: resumeTime > 0.25 ? .immediate : .deferred,
            dynamicRange: isAudioOnly ? .sdr : variant.dynamicRange,
            cdnPreference: libraryStore.effectivePlaybackCDNPreference,
            metricsID: detail.bvid,
            httpHeaders: BiliHLSManifestBuilder.httpHeaders(
                referer: "https://www.bilibili.com/video/\(detail.bvid)",
                cookieHeader: sessionStore.cookieHeader()
            ),
            artworkURL: playbackTransitionCoverURL(),
            playbackContentMode: playbackContentMode
        )
    }

    func configureStablePlayerStartupCallbacks(_ playerViewModel: PlayerStateViewModel) {
        playerViewModel.onExplicitPlaybackStartRequested = { [weak self, weak playerViewModel] in
            guard let self,
                  let playerViewModel,
                  self.stablePlayerViewModel === playerViewModel
            else { return }
            self.isAwaitingInitialManualPlayback = false
            self.isAwaitingRelatedVideoReturnPlayback = false
        }
        playerViewModel.restoreUserInterfaceForPictureInPictureStop = { [weak self, weak playerViewModel] in
            guard let self,
                  let playerViewModel,
                  self.stablePlayerViewModel === playerViewModel
            else { return false }
            guard !self.canActivatePlaybackAfterNavigation else { return true }
            return await PictureInPictureRestoreCoordinator.shared.restorePlaybackUI(for: self.detail)
        }
        playerViewModel.onPlaybackFailureWithReason = { [weak self, weak playerViewModel] message, reason in
            guard let self,
                  let playerViewModel,
                  self.stablePlayerViewModel === playerViewModel,
                  let variant = self.selectedPlayVariant
            else { return }
            self.finishPlaybackStartupWaiters(with: .failed)
            if self.restoreCompatibleVideoListenAudioAfterFailure(message) {
                return
            }
            if self.restoreVideoAfterVideoListenFailure(message) {
                return
            }
            self.handlePlaybackError(
                message ?? PlayerEngineError.unsupportedMedia.localizedDescription,
                reason: reason,
                for: variant
            )
        }
        playerViewModel.onBufferingPressure = { [weak self, weak playerViewModel] count in
            guard let self,
                  let playerViewModel,
                  self.stablePlayerViewModel === playerViewModel
            else { return }
            self.handleBufferingPressure(count)
        }
        playerViewModel.onFirstFramePresented = { [weak self, weak playerViewModel] in
            guard let self,
                  let playerViewModel,
                  self.stablePlayerViewModel === playerViewModel
            else { return }
            self.isSwitchingVideoListenMode = false
            self.finishPlaybackStartupWaiters(with: .firstFrame)
            self.clearTransientPlaybackRecoveryMessageAfterFirstFrame()
            self.releasePlaybackTransitionPlayer(after: Self.playbackTransitionReleaseDelayNanoseconds)
            self.updateVideoListenRemoteNavigationAvailability(for: playerViewModel)
            self.scheduleVideoListenContinuationPreload()
        }
        playerViewModel.onPlaybackEnded = { [weak self, weak playerViewModel] in
            guard let self,
                  let playerViewModel,
                  self.stablePlayerViewModel === playerViewModel
            else { return }
            self.handleVideoListenPlaybackEnded()
        }
        playerViewModel.onNextTrackRequested = { [weak self, weak playerViewModel] in
            guard let self,
                  let playerViewModel,
                  self.stablePlayerViewModel === playerViewModel
            else { return }
            self.advanceVideoListenPlayback(direction: .next, reason: .systemControl)
        }
        playerViewModel.onPreviousTrackRequested = { [weak self, weak playerViewModel] in
            guard let self,
                  let playerViewModel,
                  self.stablePlayerViewModel === playerViewModel
            else { return }
            if playerViewModel.currentTime > 5 {
                playerViewModel.seek(to: 0)
                playerViewModel.play()
                return
            }
            self.advanceVideoListenPlayback(direction: .previous, reason: .systemControl)
        }
        updateVideoListenRemoteNavigationAvailability(for: playerViewModel)
    }

    private func clearTransientPlaybackRecoveryMessageAfterFirstFrame() {
        guard let message = playbackFallbackMessage, !message.isEmpty else { return }
        guard message.hasPrefix("当前线路播放失败")
                || message.hasPrefix("杜比视界当前不可播放")
                || message.hasPrefix("HDR 当前不可播放")
        else { return }
        playbackFallbackMessage = nil
    }
}
