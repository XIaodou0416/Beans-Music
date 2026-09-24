import SwiftUI

struct DanmakuSettingsOpacitySection: View {
    let settings: DanmakuSettings
    @Binding var opacity: Double

    var body: some View {
        Section("透明度") {
            DanmakuSettingsSlider(
                title: "不透明度",
                systemImage: "circle.lefthalf.filled",
                value: $opacity,
                range: 0.25...1.0,
                step: 0.05,
                valueText: "\(Int((settings.opacity * 100).rounded()))%"
            )
        }
    }
}
