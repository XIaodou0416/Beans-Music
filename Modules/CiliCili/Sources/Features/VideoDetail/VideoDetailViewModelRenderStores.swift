import Foundation

struct VideoDetailViewModelRenderStores {
    let comments = VideoDetailCommentsRenderStore()
    let related = VideoDetailRelatedRenderStore()
    let interaction = VideoDetailInteractionRenderStore()
    let playback = VideoDetailPlaybackRenderStore()
    let commentThread = VideoDetailCommentThreadRenderStore()
    let favoriteFolder = VideoDetailFavoriteFolderRenderStore()
    let danmakuSettings = VideoDetailDanmakuSettingsRenderStore()
    let danmaku = VideoDetailDanmakuRenderStore()
    let networkDiagnostics = VideoDetailNetworkDiagnosticsRenderStore()
    let description = VideoDetailDescriptionRenderStore()
    let playerIdentity = VideoDetailPlayerIdentityRenderStore()
}

extension VideoDetailViewModel {
    func setContentRenderUpdatesDeferred(_ deferred: Bool) {
        renderStores.comments.setUpdatesDeferred(deferred)
        renderStores.related.setUpdatesDeferred(deferred)
        renderStores.interaction.setUpdatesDeferred(deferred)
        renderStores.description.setUpdatesDeferred(deferred)
        renderStores.playback.pageSelectorStore.setUpdatesDeferred(deferred)
    }

    func setPlaybackRenderUpdatesDeferred(_ deferred: Bool) {
        renderStores.playback.setUpdatesDeferred(deferred)
    }

    var commentsRenderStore: VideoDetailCommentsRenderStore {
        renderStores.comments
    }

    var relatedRenderStore: VideoDetailRelatedRenderStore {
        renderStores.related
    }

    var interactionRenderStore: VideoDetailInteractionRenderStore {
        renderStores.interaction
    }

    var playbackRenderStore: VideoDetailPlaybackRenderStore {
        renderStores.playback
    }

    var commentThreadRenderStore: VideoDetailCommentThreadRenderStore {
        renderStores.commentThread
    }

    var favoriteFolderRenderStore: VideoDetailFavoriteFolderRenderStore {
        renderStores.favoriteFolder
    }

    var danmakuSettingsRenderStore: VideoDetailDanmakuSettingsRenderStore {
        renderStores.danmakuSettings
    }

    var danmakuRenderStore: VideoDetailDanmakuRenderStore {
        renderStores.danmaku
    }

    var networkDiagnosticsRenderStore: VideoDetailNetworkDiagnosticsRenderStore {
        renderStores.networkDiagnostics
    }

    var descriptionRenderStore: VideoDetailDescriptionRenderStore {
        renderStores.description
    }

    var playerIdentityRenderStore: VideoDetailPlayerIdentityRenderStore {
        renderStores.playerIdentity
    }
}
