import SwiftUI

struct VideoDetailActionStripFollowControl: View {
    let isFollowing: Bool
    let canFollow: Bool
    let isMutating: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if isFollowing {
                Button(action: action) {
                    VideoDetailActionStripFollowLabel(isFollowing: isFollowing)
                }
                .buttonBorderShape(.capsule)
                .controlSize(.mini)
                .disabled(!canFollow || isMutating)
                .opacity((canFollow && !isMutating) ? 1 : 0.58)
                .accessibilityLabel(isFollowing ? "已关注" : "关注")
                .biliGlassButtonStyle()
            } else {
                Button(action: action) {
                    VideoDetailActionStripFollowLabel(isFollowing: isFollowing)
                }
                .buttonBorderShape(.capsule)
                .controlSize(.mini)
                .disabled(!canFollow || isMutating)
                .opacity((canFollow && !isMutating) ? 1 : 0.58)
                .accessibilityLabel(isFollowing ? "已关注" : "关注")
                .biliGlassButtonStyle(prominent: true)
            }
        }
    }
}

private struct VideoDetailActionStripFollowLabel: View {
    let isFollowing: Bool

    var body: some View {
        Text(isFollowing ? "已关注" : "关注")
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(maxWidth: .infinity)
            .frame(height: VideoDetailActionStrip.Metrics.followHeight)
    }
}
