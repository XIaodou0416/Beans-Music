import SwiftUI

struct SettingsNavigationRow: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(appTintColor)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appTypography(.settingsRow, fallback: .subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .appTypography(.settingsSubtitle, fallback: .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct MineSettingsLabel: View {
    let title: String

    init(_ title: String, systemImage _: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
    }
}

struct PlainSettingsNavigationRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .appTypography(.settingsRow, fallback: .subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .appTypography(.settingsSubtitle, fallback: .caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct MinePlaybackPreferenceChip: View {
    let title: String

    init(title: String, systemImage _: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .appTypography(.badge, fallback: .caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color(uiColor: .separator).opacity(0.10), lineWidth: 0.5)
            }
    }
}
