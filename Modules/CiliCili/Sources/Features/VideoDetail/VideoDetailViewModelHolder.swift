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
        let viewModel = VideoDetailViewModel(
            seedVideo: seedVideo,
            api: api,
            libraryStore: libraryStore,
            sessionStore: sessionStore,
            sponsorBlockService: sponsorBlockService,
            playbackOptions: playbackOptions
        )
        if playbackOptions != .performanceTest {
            viewModel.playbackContentMode = CiliCiliPlaybackExperience.current.playerContentMode
        }
        return viewModel
    }

    private func installViewModel(_ viewModel: VideoDetailViewModel) {
        self.viewModel = viewModel
        cleanupPlayback = VideoDetailViewModelHolderCleanupActions(
            viewModel: viewModel
        )
        .makeCleanupPlayback()
    }
}
