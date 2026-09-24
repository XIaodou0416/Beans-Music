import SwiftUI

@MainActor
struct VideoDetailDanmakuSettingsSheetHost: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    let actions: VideoDetailDanmakuSheetActions

    var body: some View {
        DanmakuSettingsSheet(
            store: viewModel.danmakuSettingsRenderStore,
            toggleDanmaku: actions.toggleDanmaku,
            updateDanmakuSettings: actions.updateDanmakuSettings
        )
        .presentationDetents([.medium])
    }
}
