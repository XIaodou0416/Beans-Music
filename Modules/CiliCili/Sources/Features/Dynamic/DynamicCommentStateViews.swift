import SwiftUI

struct DynamicCommentPlainEmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }
}

struct DynamicCommentErrorView: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                Text("评论加载失败")
                    .font(.subheadline.weight(.semibold))
            }

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Button(action: retry) {
                Label("重试", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .dynamicCommentGlassButtonStyle()
            .controlSize(.small)
            .buttonBorderShape(.capsule)
            .tint(appTintColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .dynamicCommentGlassCard()
    }
}

extension View {
    func dynamicCommentGlassButtonStyle(prominent: Bool = false) -> some View {
        biliGlassButtonStyle(prominent: prominent)
    }

    @ViewBuilder
    func dynamicCommentGlassCard() -> some View {
        clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .biliGlassEffect(
                interactive: false,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
    }
}
