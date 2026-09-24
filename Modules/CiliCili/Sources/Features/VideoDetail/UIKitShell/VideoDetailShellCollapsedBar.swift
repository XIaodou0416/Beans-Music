import SwiftUI

/// UIKit 外壳用：暂停下翻收缩时的折叠工具条。
/// 背景由 `VideoDetailRotationBridgeViewController` 的主题色遮罩提供。
struct VideoDetailShellCollapsedBar: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    @ObservedObject var playerViewModel: PlayerStateViewModel
    let opacity: Double
    let onNavigateBack: () -> Void
    let onRequestFullscreen: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onNavigateBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")

            Button {
                playerViewModel.togglePlayback()
            } label: {
                Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playerViewModel.isPlaying ? "暂停" : "播放")

            Text(playerViewModel.title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onRequestFullscreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("全屏")
        }
        .biliLiquidGlassForeground(shadowOpacity: 0.20)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appTintColor)
        .contentShape(Rectangle())
        .opacity(opacity)
    }
}
