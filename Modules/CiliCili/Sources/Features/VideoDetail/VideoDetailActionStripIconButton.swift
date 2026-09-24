import SwiftUI

struct VideoDetailActionStripIconButton: View {
    let accessibilityTitle: String
    let systemImage: String
    let foregroundStyle: Color
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VideoDetailActionStripIconLabel(
                systemImage: systemImage,
                foregroundStyle: foregroundStyle
            )
        }
        .buttonBorderShape(.circle)
        .controlSize(.mini)
        .biliGlassButtonStyle()
        .contentShape(Circle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.52 : 1)
        .accessibilityLabel(accessibilityTitle)
    }
}
