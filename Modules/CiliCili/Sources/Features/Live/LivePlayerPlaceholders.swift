import SwiftUI

struct LivePlayerLoadingPlaceholder: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            Color.black
            LivePlayerLoadingContent(title: title, subtitle: subtitle)
        }
    }
}

private struct LivePlayerLoadingContent: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.05)

            VStack(spacing: 4) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.90))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .padding(.horizontal, 24)
        }
    }
}

struct LivePlayerFailurePlaceholder: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)

            Text("直播加载失败")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))

            Text(message)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 28)

            Button(action: retry) {
                Label("重试", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(appTintColor)
        }
    }
}
