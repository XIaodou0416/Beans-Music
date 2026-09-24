import SwiftUI

struct VideoDetailPlayURLFailedNotice: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VideoDetailPlayURLRetryButton(
                title: "播放地址加载失败，点击重试",
                systemImage: "arrow.clockwise",
                retry: retry
            )

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
