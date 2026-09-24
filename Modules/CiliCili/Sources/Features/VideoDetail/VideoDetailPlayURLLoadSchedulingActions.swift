import Foundation

extension VideoDetailViewModel {
    func schedulePlayURLLoadIfNeeded() {
        guard !isPlaybackInvalidatedForNavigation,
              selectedPlayVariant == nil,
              !playURLState.isLoading
        else { return }
        trackBackgroundTask(
            Task(priority: .userInitiated) { [weak self] in
                await self?.loadPlayURLIfNeeded()
            }
        )
    }
}
