import SwiftUI

struct ErrorStateView: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let title: String
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        BiliContentStateSurface(
            title: title,
            message: message,
            systemImage: "exclamationmark.triangle",
            tint: .orange
        ) {
            if let retry {
                Button(action: retry) {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(appTintColor)
            }
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        BiliContentStateSurface(
            title: title,
            message: message,
            systemImage: systemImage,
            tint: .secondary
        )
    }
}

struct InlineLoadingStateView: View {
    var title: String
    var systemImage: String = "arrow.triangle.2.circlepath"

    var body: some View {
        HStack(spacing: 9) {
            ProgressView()
                .controlSize(.small)

            Label(title, systemImage: systemImage)
                .labelStyle(.titleOnly)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityLabel(title)
    }
}
