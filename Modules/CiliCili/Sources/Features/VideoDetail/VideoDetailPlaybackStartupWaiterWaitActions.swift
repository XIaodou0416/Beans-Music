import Foundation

extension VideoDetailViewModel {
    func waitForFirstFrameOrFailure() async -> Bool {
        await waitForPlaybackStartupRelease(acceptsFailure: false) == .firstFrame
    }

    func waitForPlaybackStartupRelease(acceptsFailure: Bool) async -> VideoDetailPlaybackStartupRelease? {
        guard !Task.isCancelled, !isPlaybackInvalidatedForNavigation else { return nil }
        if let release = immediatePlaybackStartupRelease(acceptsFailure: acceptsFailure) {
            return release
        }
        if isPlaybackStartupFailed {
            return nil
        }

        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled, !isPlaybackInvalidatedForNavigation else {
                    continuation.resume(returning: nil)
                    return
                }
                if let release = immediatePlaybackStartupRelease(acceptsFailure: acceptsFailure) {
                    continuation.resume(returning: release)
                    return
                }
                if isPlaybackStartupFailed {
                    continuation.resume(returning: nil)
                    return
                }
                playbackStartupWaiters[waiterID] = VideoDetailPlaybackStartupWaiter(
                    acceptsFailure: acceptsFailure,
                    continuation: continuation
                )
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancelPlaybackStartupWaiter(waiterID)
            }
        }
    }
}
