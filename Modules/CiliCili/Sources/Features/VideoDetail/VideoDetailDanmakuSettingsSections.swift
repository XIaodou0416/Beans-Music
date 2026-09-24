import SwiftUI

struct DanmakuSettingsHeaderFormSection: View {
    @ObservedObject var store: VideoDetailDanmakuSettingsRenderStore
    let summary: String
    let toggleDanmaku: () -> Void

    var body: some View {
        Section {
            DanmakuSettingsHeaderSectionContent(
                isDanmakuEnabled: store.isDanmakuEnabled,
                settings: store.danmakuSettings,
                summary: summary,
                toggleDanmaku: toggleDanmaku
            )
        }
    }
}
