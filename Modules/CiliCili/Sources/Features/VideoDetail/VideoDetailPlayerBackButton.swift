import SwiftUI

struct VideoDetailPlayerBackButton: View {
    @Environment(\.playerNativeControlMetrics) private var controlMetrics
    let action: () -> Void
    var usesGlass = true

    var body: some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            Image(systemName: "chevron.left")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(
                    width: controlMetrics.controlHeight,
                    height: controlMetrics.controlHeight
                )
        }
        .modifier(
            VideoDetailPlayerBackButtonSurface(
                usesGlass: usesGlass,
                metrics: controlMetrics
            )
        )
        .frame(width: 44, height: controlMetrics.controlHeight, alignment: .leading)
        .biliPlayerExpandedHitTarget(horizontal: 0, vertical: verticalHitPadding)
        .accessibilityLabel("返回")
    }

    private var verticalHitPadding: CGFloat {
        max((44 - controlMetrics.controlHeight) / 2, 8)
    }

    private var iconSize: CGFloat {
        controlMetrics.iconSize
    }
}

private struct VideoDetailPlayerBackButtonSurface: ViewModifier {
    let usesGlass: Bool
    let metrics: PlayerNativeControlMetrics

    func body(content: Content) -> some View {
        if usesGlass {
            content.biliPlayerCompactGlassCircle(metrics: metrics)
        } else {
            content
                .buttonStyle(.plain)
                .contentShape(Circle())
        }
    }
}
