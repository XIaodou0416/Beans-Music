import Foundation

@MainActor
struct VideoDetailViewModelHolderCleanupActions {
    let viewModel: VideoDetailViewModel

    func makeCleanupPlayback() -> @Sendable () -> Void {
        { [viewModel] in
            Task { @MainActor [viewModel] in
                viewModel.stopPlaybackForNavigation()
            }
        }
    }
}
