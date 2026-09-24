import Foundation

struct VideoDetailPlayerPlaceholderRenderSnapshot: Equatable {
    var playURLState: LoadingState = .idle
    var selectedPlayVariant: PlayVariant?
    var isDetailLoading = false
    var isDetailLoaded = false
    var failedMessage: String?

    init() {}

    init(playback: VideoDetailPlaybackRenderSnapshot) {
        playURLState = playback.playURLState
        selectedPlayVariant = playback.selectedPlayVariant
        isDetailLoading = playback.isDetailLoading
        isDetailLoaded = playback.isDetailLoaded
        failedMessage = playback.failedMessage
    }
}
