import SwiftUI

struct PlayerNativeGlassIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String?
    let metrics: PlayerNativeControlMetrics
    let action: () -> Void

    init(
        systemName: String,
        accessibilityLabel: String,
        accessibilityIdentifier: String? = nil,
        metrics: PlayerNativeControlMetrics,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.metrics = metrics
        self.action = action
    }

    @ViewBuilder
    var body: some View {
        if let accessibilityIdentifier {
            button.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .frame(
                    width: metrics.controlHeight,
                    height: metrics.controlHeight
                )
        }
        .biliPlayerCompactGlassCircle(metrics: metrics)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconSize: CGFloat {
        metrics.iconSize
    }
}
