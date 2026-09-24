import Foundation

struct VideoDetailInteractionRenderSnapshot: Equatable {
    var interactionState = VideoInteractionState()
    var interactionMessage: String?
    var isMutatingInteraction = false
    var isMutatingLike = false
    var isMutatingCoin = false
    var isMutatingFavorite = false
    var isMutatingFollow = false
    var playbackFallbackMessage: String?
}

struct VideoDetailFavoriteFolderRenderSnapshot: Equatable {
    var favoriteFolders: [FavoriteFolder] = []
    var favoriteFolderState: LoadingState = .idle
    var isMutatingInteraction = false

    init() {}

    init(viewModel: VideoDetailViewModel) {
        favoriteFolders = viewModel.favoriteFolders
        favoriteFolderState = viewModel.favoriteFolderState
        isMutatingInteraction = viewModel.isMutatingFavorite
    }
}

struct VideoDetailDisplayMetrics: Equatable {
    var publishDateText = "-"
    var publishDateSubtitleText: String?
    var likeTitle = "-"
    var coinTitle = "-"
    var favoriteTitle = "-"
    var canFavorite = false

    init() {}

    init(video: VideoItem) {
        publishDateText = BiliFormatters.publishDate(video.pubdate)
        publishDateSubtitleText = publishDateText == "-" ? nil : "投稿于 \(publishDateText)"
        likeTitle = BiliFormatters.compactCount(video.stat?.like)
        coinTitle = BiliFormatters.compactCount(video.stat?.coin)
        favoriteTitle = BiliFormatters.compactCount(video.stat?.favorite)
        canFavorite = video.aid != nil
    }
}
