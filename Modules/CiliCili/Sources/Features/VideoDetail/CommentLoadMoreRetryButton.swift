import SwiftUI

struct CommentLoadMoreRetryButton: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        Button(action: retry) {
            Label("评论加载失败，点按重试", systemImage: "arrow.clockwise")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .accessibilityHint(message)
    }
}
