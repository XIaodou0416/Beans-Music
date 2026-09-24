import Foundation

extension VideoDetailViewModel {
    func retryPlayURL() async {
        guard !isPlaybackTerminatedForNavigation else { return }
        isPlaybackInvalidatedForNavigation = false
        await loadPlayURL()
    }

    func loadPlayURLIfNeeded() async {
        guard !isPlaybackTerminatedForNavigation,
              !isPlaybackInvalidatedForNavigation,
              selectedPlayVariant == nil,
              !playURLState.isLoading
        else { return }
        await loadPlayURL()
    }
}
