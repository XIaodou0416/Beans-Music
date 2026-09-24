import Combine
import Foundation

@MainActor
final class VideoDetailViewModelHolder: ObservableObject {
    @Published var viewModel: VideoDetailViewModel?
    private var cleanupPlayback: (@Sendable () -> Void)?

    func configure(
        seedVideo: VideoItem,
        api: BiliAPIClient,
        libraryStore: LibraryStore,
        sessionStore: SessionStore,
        sponsorBlockService: SponsorBlockService,
        playbackOptions: VideoDetailPlaybackOptions = VideoDetailPlaybackOptions()
    ) {
        guard viewModel == nil else { return }
        installViewModel(
            makeViewModel(
                seedVideo: seedVideo,
                api: api,
                libraryStore: libraryStore,
                sessionStore: sessionStore,
                sponsorBlockService: sponsorBlockService,
                playbackOptions: playbackOptions
            )
        )
    }

    deinit {
        cleanupPlayback?()
    }

    private func makeViewModel(
        seedVideo: VideoItem,
        api: BiliAPIClient,
        libraryStore: LibraryStore,
        sessionStore: SessionStore,
        sponsorBlockService: SponsorBlockService,
        playbackOptions: VideoDetailPlaybackOptions
    ) -> VideoDetailViewModel {
        VideoDetailViewModel(
            seedVideo: seedVideo,
            api: api,
            libraryStore: libraryStore,
            sessionStore: sessionStore,
            sponsorBlockService: sponsorBlockService,
            playbackOptions: playbackOptions
        )
    }

    private func installViewModel(_ viewModel: VideoDetailViewModel) {
        self.viewModel = viewModel
        cleanupPlayback = VideoDetailViewModelHolderCleanupActions(
            viewModel: viewModel
        )
        .makeCleanupPlayback()
    }
}
