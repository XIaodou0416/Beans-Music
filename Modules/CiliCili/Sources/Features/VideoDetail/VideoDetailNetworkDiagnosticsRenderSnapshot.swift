import Foundation

struct VideoDetailNetworkDiagnosticsRenderSnapshot: Equatable {
    var videoTitle = ""
    var metricsID = ""
    var selectedPlayVariant: PlayVariant?
    var playerViewModel: PlayerStateViewModel?
    var detailLoadElapsedMilliseconds: Int?
    var playURLElapsedMilliseconds: Int?
    var relatedElapsedMilliseconds: Int?
    var lastPlayURLSource: String?
    var resumeDiagnostics = PlaybackResumeDiagnostics.none
    var playbackFallbackMessage: String?

    init() {}

    init(viewModel: VideoDetailViewModel) {
        videoTitle = viewModel.detail.title
        metricsID = viewModel.detail.bvid
        selectedPlayVariant = viewModel.selectedPlayVariant
        playerViewModel = viewModel.stablePlayerViewModel
        detailLoadElapsedMilliseconds = viewModel.detailLoadElapsedMilliseconds
        playURLElapsedMilliseconds = viewModel.playURLElapsedMilliseconds
        relatedElapsedMilliseconds = viewModel.relatedElapsedMilliseconds
        lastPlayURLSource = viewModel.lastPlayURLSource
        resumeDiagnostics = viewModel.resumeDiagnostics
        playbackFallbackMessage = viewModel.playbackFallbackMessage
    }

    static func == (lhs: VideoDetailNetworkDiagnosticsRenderSnapshot, rhs: VideoDetailNetworkDiagnosticsRenderSnapshot) -> Bool {
        lhs.videoTitle == rhs.videoTitle
            && lhs.metricsID == rhs.metricsID
            && lhs.selectedPlayVariant == rhs.selectedPlayVariant
            && samePlayer(lhs.playerViewModel, rhs.playerViewModel)
            && lhs.detailLoadElapsedMilliseconds == rhs.detailLoadElapsedMilliseconds
            && lhs.playURLElapsedMilliseconds == rhs.playURLElapsedMilliseconds
            && lhs.relatedElapsedMilliseconds == rhs.relatedElapsedMilliseconds
            && lhs.lastPlayURLSource == rhs.lastPlayURLSource
            && lhs.resumeDiagnostics == rhs.resumeDiagnostics
            && lhs.playbackFallbackMessage == rhs.playbackFallbackMessage
    }

    private static func samePlayer(_ lhs: PlayerStateViewModel?, _ rhs: PlayerStateViewModel?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.some(left), .some(right)):
            return left === right
        default:
            return false
        }
    }
}
