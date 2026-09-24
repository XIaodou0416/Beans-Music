import SwiftUI

extension DanmakuSettingsSheet {
    var settingsSummary: String {
        if store.isDanmakuEnabled {
            return "当前使用 \(store.danmakuSettings.displayArea.title)，字号 \(Int((store.danmakuSettings.fontScale * 100).rounded()))%，不透明度 \(Int((store.danmakuSettings.opacity * 100).rounded()))%。"
        }
        return "弹幕已关闭，播放时不会显示滚动评论。"
    }

    var fontScaleBinding: Binding<Double> {
        Binding(
            get: { store.danmakuSettings.fontScale },
            set: { newValue in
                var settings = store.danmakuSettings
                settings.fontScale = newValue
                updateDanmakuSettings(settings)
            }
        )
    }

    var opacityBinding: Binding<Double> {
        Binding(
            get: { store.danmakuSettings.opacity },
            set: { newValue in
                var settings = store.danmakuSettings
                settings.opacity = newValue
                updateDanmakuSettings(settings)
            }
        )
    }

    var displayAreaBinding: Binding<DanmakuDisplayArea> {
        Binding(
            get: { store.danmakuSettings.displayArea },
            set: { newValue in
                var settings = store.danmakuSettings
                settings.displayArea = newValue
                updateDanmakuSettings(settings)
            }
        )
    }

    var hidesDanmakuInPortraitBinding: Binding<Bool> {
        Binding(
            get: { store.danmakuSettings.hidesInPortrait },
            set: { newValue in
                var settings = store.danmakuSettings
                settings.hidesInPortrait = newValue
                updateDanmakuSettings(settings)
            }
        )
    }

    var fontWeightBinding: Binding<DanmakuFontWeightOption> {
        Binding(
            get: { store.danmakuSettings.fontWeight },
            set: { newValue in
                var settings = store.danmakuSettings
                settings.fontWeight = newValue
                updateDanmakuSettings(settings)
            }
        )
    }
}
