import Foundation

struct VideoDetailPlaybackRenderSnapshot: Equatable {
    var historyVideo: VideoItem?
    var historyCID: Int?
    var duration: TimeInterval?
    var pages: [VideoPage] = []
    var selectedCID: Int?
    var playURLState: LoadingState = .idle
    var selectedPlayVariant: PlayVariant?
    var isDetailLoading = false
    var isDetailLoaded = false
    var failedMessage: String?
    var isDanmakuEnabled = true
    var qualityInlineButtonTitle = "清晰度"
    var qualityAccessoryButtonTitle = "清晰度"
    var qualityButtonSystemImage = "slider.horizontal.3"
    var qualityMenuItems: [VideoDetailPlaybackQualityMenuItem] = []
    var isSwitchingPlayQuality = false

    init(
        historyVideo: VideoItem? = nil,
        historyCID: Int? = nil,
        duration: TimeInterval? = nil,
        pages: [VideoPage] = [],
        selectedCID: Int? = nil,
        playURLState: LoadingState = .idle,
        selectedPlayVariant: PlayVariant? = nil,
        isDetailLoading: Bool = false,
        isDetailLoaded: Bool = false,
        failedMessage: String? = nil,
        isDanmakuEnabled: Bool = true,
        qualityInlineButtonTitle: String = "清晰度",
        qualityAccessoryButtonTitle: String = "清晰度",
        qualityButtonSystemImage: String = "slider.horizontal.3",
        qualityMenuItems: [VideoDetailPlaybackQualityMenuItem] = [],
        isSwitchingPlayQuality: Bool = false
    ) {
        self.historyVideo = historyVideo
        self.historyCID = historyCID
        self.duration = duration
        self.pages = pages
        self.selectedCID = selectedCID
        self.playURLState = playURLState
        self.selectedPlayVariant = selectedPlayVariant
        self.isDetailLoading = isDetailLoading
        self.isDetailLoaded = isDetailLoaded
        self.failedMessage = failedMessage
        self.isDanmakuEnabled = isDanmakuEnabled
        self.qualityInlineButtonTitle = qualityInlineButtonTitle
        self.qualityAccessoryButtonTitle = qualityAccessoryButtonTitle
        self.qualityButtonSystemImage = qualityButtonSystemImage
        self.qualityMenuItems = qualityMenuItems
        self.isSwitchingPlayQuality = isSwitchingPlayQuality
    }

    init(viewModel: VideoDetailViewModel) {
        self = VideoDetailPlaybackRenderSnapshotFactory(viewModel: viewModel).snapshot
    }
}
