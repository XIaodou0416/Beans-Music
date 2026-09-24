import Foundation

struct VideoDetailDanmakuSettingsRenderSnapshot: Equatable {
    var isDanmakuEnabled = true
    var danmakuSettings = DanmakuSettings.default

    init() {}

    init(viewModel: VideoDetailViewModel) {
        isDanmakuEnabled = viewModel.isDanmakuEnabled
        danmakuSettings = viewModel.danmakuSettings
    }
}

struct VideoDetailDanmakuRenderSnapshot: Equatable {
    var items: [DanmakuItem] = []
    var itemsRevision = 0
    var isDanmakuEnabled = true
    var effectiveSettings = DanmakuSettings.default

    init() {}

    init(viewModel: VideoDetailViewModel) {
        items = viewModel.danmakuItems
        itemsRevision = viewModel.danmakuItemsRevision
        isDanmakuEnabled = viewModel.isDanmakuEnabled
        effectiveSettings = viewModel.effectiveDanmakuSettings
    }

    static func == (
        lhs: VideoDetailDanmakuRenderSnapshot,
        rhs: VideoDetailDanmakuRenderSnapshot
    ) -> Bool {
        lhs.itemsRevision == rhs.itemsRevision
            && lhs.isDanmakuEnabled == rhs.isDanmakuEnabled
            && lhs.effectiveSettings == rhs.effectiveSettings
    }
}
