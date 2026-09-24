import SwiftUI

struct DanmakuSettingsDisplayAreaSection: View {
    @Binding var displayArea: DanmakuDisplayArea

    var body: some View {
        Section("显示区域") {
            Picker("覆盖范围", selection: $displayArea) {
                ForEach(DanmakuDisplayArea.allCases) { area in
                    Text(area.title).tag(area)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .accessibilityIdentifier("ui.videoDetail.sheet.danmakuSettings.displayArea")
        }
    }
}

struct DanmakuSettingsPortraitVisibilitySection: View {
    @Binding var hidesDanmakuInPortrait: Bool

    var body: some View {
        Section("竖屏播放") {
            Toggle("竖屏时隐藏弹幕", isOn: $hidesDanmakuInPortrait)
                .accessibilityIdentifier("ui.videoDetail.sheet.danmakuSettings.hidesInPortrait")
        }
    }
}
