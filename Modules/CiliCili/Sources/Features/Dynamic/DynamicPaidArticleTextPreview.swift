import SwiftUI

struct DynamicPaidArticleTextPreview: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let content: DynamicPaidContent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(content.title)
                .appTypography(.feedVideoTitle)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle = content.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .appTypography(.dynamicBody)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                Text(content.badgeText)
                if content.isLocked {
                    Text("需解锁")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(appTintColor)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(content.badgeText) \(content.title)")
    }
}
