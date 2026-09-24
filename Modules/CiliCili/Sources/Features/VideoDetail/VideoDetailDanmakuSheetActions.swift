import Foundation

@MainActor
struct VideoDetailDanmakuSheetActions {
    weak var viewModel: VideoDetailViewModel?

    func toggleDanmaku() {
        viewModel?.toggleDanmaku()
    }

    func updateDanmakuSettings(_ settings: DanmakuSettings) {
        viewModel?.updateDanmakuSettings(settings)
    }
}
