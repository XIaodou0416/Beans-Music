import SwiftUI

struct DanmakuSettingsSheetContent: View {
    @ObservedObject var store: VideoDetailDanmakuSettingsRenderStore
    let summary: String
    let displayAreaBinding: Binding<DanmakuDisplayArea>
    let hidesDanmakuInPortraitBinding: Binding<Bool>
    let fontScaleBinding: Binding<Double>
    let fontWeightBinding: Binding<DanmakuFontWeightOption>
    let opacityBinding: Binding<Double>
    let toggleDanmaku: () -> Void

    var body: some View {
        Form {
            DanmakuSettingsHeaderFormSection(
                store: store,
                summary: summary,
                toggleDanmaku: toggleDanmaku
            )

            DanmakuSettingsDisplayAreaSection(displayArea: displayAreaBinding)

            DanmakuSettingsPortraitVisibilitySection(
                hidesDanmakuInPortrait: hidesDanmakuInPortraitBinding
            )

            DanmakuSettingsTextSection(
                settings: store.danmakuSettings,
                fontScale: fontScaleBinding,
                fontWeight: fontWeightBinding
            )

            DanmakuSettingsOpacitySection(
                settings: store.danmakuSettings,
                opacity: opacityBinding
            )
        }
    }
}
