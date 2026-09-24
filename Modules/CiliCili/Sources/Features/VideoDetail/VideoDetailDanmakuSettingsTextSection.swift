import SwiftUI

struct DanmakuSettingsTextSection: View {
    let settings: DanmakuSettings
    @Binding var fontScale: Double
    @Binding var fontWeight: DanmakuFontWeightOption

    var body: some View {
        Section("文字") {
            DanmakuSettingsSlider(
                title: "字体大小",
                systemImage: "textformat.size",
                value: $fontScale,
                range: 0.7...1.45,
                step: 0.05,
                valueText: "\(Int((settings.fontScale * 100).rounded()))%"
            )

            Picker(selection: $fontWeight) {
                ForEach(DanmakuFontWeightOption.allCases) { weight in
                    Text(weight.title).tag(weight)
                }
            } label: {
                Label("字体粗细", systemImage: "bold")
            }
            .pickerStyle(.navigationLink)
        }
    }
}
