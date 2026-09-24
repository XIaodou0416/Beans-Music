import Foundation

@MainActor
struct VideoDetailViewConfigurationActions {
    let seedVideo: VideoItem
    let playbackOptions: VideoDetailPlaybackOptions
    let dependencies: AppDependencies
    let holder: VideoDetailViewModelHolder

    func configureViewModel() {
        holder.configure(
            seedVideo: seedVideo,
            api: dependencies.api,
            libraryStore: dependencies.libraryStore,
            sessionStore: dependencies.sessionStore,
            sponsorBlockService: dependencies.sponsorBlockService,
            playbackOptions: playbackOptions
        )
    }
}
