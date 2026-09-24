import SwiftUI

extension View {
    @ViewBuilder
    func commentLoadMoreTrigger(
        if shouldAttachTask: Bool,
        id: Int,
        action: @escaping () async -> Void
    ) -> some View {
        if shouldAttachTask {
            onAppear {
                Task {
                    await action()
                }
            }
            .id(id)
        } else {
            self
        }
    }

    @ViewBuilder
    func commentPlayerGlassCapsule(showsShadow: Bool = true) -> some View {
        let glass = biliPlayerClearGlass(interactive: false, in: Capsule())
        if showsShadow {
            glass.shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
        } else {
            glass
        }
    }

    @ViewBuilder
    func commentPlayerGlassRoundedRectangle(cornerRadius: CGFloat = 12, showsShadow: Bool = true) -> some View {
        let glass = biliPlayerClearGlass(
            interactive: false,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        if showsShadow {
            glass.shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 3)
        } else {
            glass
        }
    }
}
