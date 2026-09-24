import SwiftUI

struct DanmakuSettingsHeaderSectionContent: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let isDanmakuEnabled: Bool
    let settings: DanmakuSettings
    let summary: String
    let toggleDanmaku: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("弹幕", systemImage: isDanmakuEnabled ? "text.bubble.fill" : "text.bubble")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isDanmakuEnabled ? appTintColor : .secondary)

                Spacer(minLength: 8)

                Toggle(
                    "启用弹幕",
                    isOn: Binding(
                        get: { isDanmakuEnabled },
                        set: { isEnabled in
                            if isDanmakuEnabled != isEnabled {
                                toggleDanmaku()
                            }
                        }
                    )
                )
                .labelsHidden()
            }

            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                DanmakuSettingsChip(
                    title: settings.displayArea.title,
                    systemImage: "rectangle.inset.filled"
                )
                DanmakuSettingsChip(
                    title: "\(Int((settings.fontScale * 100).rounded()))%",
                    systemImage: "textformat.size"
                )
                DanmakuSettingsChip(
                    title: "\(Int((settings.opacity * 100).rounded()))%",
                    systemImage: "circle.lefthalf.filled"
                )
            }
        }
        .padding(.vertical, 2)
    }
}
