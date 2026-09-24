import Foundation

extension VideoDetailViewModel {
    func scheduleFullDetailLoadIfNeeded(
        priority: TaskPriority = .utility,
        waitsForFirstFrame: Bool = false
    ) {
        guard !detail.isPGCEpisode else { return }
        guard !isPlaybackInvalidatedForNavigation, detailLoadingTask == nil else { return }
        let token = UUID()
        detailLoadingToken = token
        detailLoadingTask = Task(priority: priority) { [weak self] in
            guard let self else { return }
            defer {
                self.clearDetailLoadingTaskIfCurrent(token)
            }
            if waitsForFirstFrame {
                guard let release = await self.waitForPlaybackStartupRelease(acceptsFailure: true),
                      !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation
                else { return }
                if case .firstFrame = release {
                    try? await Task.sleep(nanoseconds: 220_000_000)
                    guard !Task.isCancelled, !self.isPlaybackInvalidatedForNavigation else { return }
                }
            }
            await self.loadFullDetailAndMetadata(priority: priority)
        }
    }
}
