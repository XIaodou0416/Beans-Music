import SwiftUI

struct PlayerSeekPreviewOverlay: View {
    let presentation: PlayerSeekPreviewPresentation

    var body: some View {
        VStack(spacing: 6) {
            if presentation.isCancelPending {
                Text("松开手指，取消进退")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            } else {
                previewImage

                Text(timeText)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .monospacedDigit()
            }
        }
        .biliLiquidGlassForeground(shadowOpacity: 0.20)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .biliPlayerClearGlass(interactive: false, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.isCancelPending ? "松开手指，取消进退" : timeText)
    }

    @ViewBuilder
    private var previewImage: some View {
        if let image = presentation.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: previewWidth, height: previewHeight)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else if presentation.isLoading {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.black.opacity(0.18))

                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                    .accessibilityHidden(true)
            }
            .frame(width: previewWidth, height: previewHeight)
        }
    }

    private var previewWidth: CGFloat {
        160
    }

    private var previewHeight: CGFloat {
        let aspectRatio = presentation.imageAspectRatio ?? (16.0 / 9.0)
        guard aspectRatio > 0 else { return 90 }
        return min(max(previewWidth / aspectRatio, 64), 112)
    }

    private var timeText: String {
        "\(formatDuration(presentation.currentTime)) / \(formatDuration(presentation.duration))"
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        let seconds = max(Int(value.rounded()), 0)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}
