import SwiftUI

enum HomePullRefreshGeometry {
    static func distance(contentOffsetY: CGFloat, contentInsetTop: CGFloat) -> CGFloat {
        max(0, -(contentOffsetY + contentInsetTop))
    }

    static func isUserInteracting(_ phase: ScrollPhase) -> Bool {
        phase == .tracking || phase == .interacting
    }
}

private struct HomePullRefreshTrackingModifier: ViewModifier {
    let isEnabled: Bool
    let onChange: @MainActor (CGFloat, Bool) -> Void
    @State private var pullDistance: CGFloat = 0
    @State private var isUserInteracting = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    HomePullRefreshGeometry.distance(
                        contentOffsetY: geometry.contentOffset.y,
                        contentInsetTop: geometry.contentInsets.top
                    )
                } action: { _, newDistance in
                    pullDistance = newDistance
                    onChange(newDistance, isUserInteracting)
                }
                .onScrollPhaseChange { _, newPhase in
                    let newIsUserInteracting = HomePullRefreshGeometry.isUserInteracting(newPhase)
                    isUserInteracting = newIsUserInteracting
                    onChange(pullDistance, newIsUserInteracting)
                }
        } else {
            content
        }
    }
}

extension View {
    func customPullRefreshTracking(
        isEnabled: Bool = true,
        onChange: @escaping @MainActor (CGFloat, Bool) -> Void
    ) -> some View {
        modifier(
            HomePullRefreshTrackingModifier(
                isEnabled: isEnabled,
                onChange: onChange
            )
        )
    }
}
