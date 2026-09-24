import SwiftUI

struct BiliMediaPlaceholder: View {
    enum Style: Equatable {
        case video
        case image

        var systemImage: String {
            switch self {
            case .video:
                return "play.rectangle.fill"
            case .image:
                return "photo.fill"
            }
        }
    }

    var style: Style = .video
    var phase: RemoteImageLoadingPhase = .loading
    var showsSpinner = false
    var iconSize: CGFloat = 20

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.tertiarySystemFill).opacity(0.74),
                    Color(.secondarySystemFill).opacity(0.52)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ZStack {
                Circle()
                    .fill(Color(.systemBackground).opacity(0.46))
                    .frame(width: iconSize * 2.05, height: iconSize * 2.05)

                Image(systemName: phase == .failed ? "exclamationmark.triangle.fill" : style.systemImage)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(phase == .failed ? Color.orange : Color.secondary.opacity(0.72))
            }

            if phase == .failed {
                Text("加载失败")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Color(.systemBackground).opacity(0.42), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 9)
            }

            if showsSpinner, phase != .failed {
                ProgressView()
                    .controlSize(.small)
                    .tint(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(10)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if phase == .failed {
            return style == .video ? "视频封面加载失败" : "图片加载失败"
        }
        return style == .video ? "正在加载视频封面" : "正在加载图片"
    }
}
