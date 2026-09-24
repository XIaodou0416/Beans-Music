import SwiftUI

struct RelatedVideoRetryState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: VideoDetailRelatedStyle.retrySpacing) {
            Label("相关推荐加载失败", systemImage: "rectangle.stack.badge.exclamationmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Button {
                retry()
            } label: {
                Label("重新加载", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
    }
}
