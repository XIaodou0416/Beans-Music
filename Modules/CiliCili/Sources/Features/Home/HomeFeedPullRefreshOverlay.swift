import SwiftUI

enum HomePullRefreshLayout {
    static let refreshingTopInset: CGFloat = 52

    static func topInset(isRefreshing: Bool) -> CGFloat {
        isRefreshing ? refreshingTopInset : 0
    }

}

struct HomeFeedPullRefreshOverlay: View {
    let pullDistance: CGFloat
    let triggerDistance: CGFloat
    let isRefreshing: Bool
    @State private var suppressesPullProgress = false
    @State private var refreshCompletionSuppressionID = 0

    var body: some View {
        HomePullRefreshIndicator(
            pullDistance: pullDistance,
            triggerDistance: triggerDistance,
            isRefreshing: isRefreshing,
            suppressesPullProgress: suppressesPullProgress
        )
        .padding(.top, 6)
        .allowsHitTesting(false)
        .onChange(of: isRefreshing) { wasRefreshing, isRefreshing in
            refreshCompletionSuppressionID &+= 1
            suppressesPullProgress = wasRefreshing && !isRefreshing
        }
        .task(id: refreshCompletionSuppressionID) {
            guard suppressesPullProgress else { return }
            try? await Task.sleep(for: .milliseconds(360))
            guard !Task.isCancelled else { return }
            suppressesPullProgress = false
        }
    }
}

private struct HomeFeedPullRefreshLayoutModifier: ViewModifier {
    let pullDistance: CGFloat
    let triggerDistance: CGFloat
    let isRefreshing: Bool
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isEnabled {
                    HomeFeedPullRefreshOverlay(
                        pullDistance: pullDistance,
                        triggerDistance: triggerDistance,
                        isRefreshing: isRefreshing
                    )
                }
            }
            .animation(.smooth(duration: 0.18), value: isEnabled)
    }
}

extension View {
    func homeFeedPullRefreshLayout(
        pullDistance: CGFloat,
        triggerDistance: CGFloat,
        isRefreshing: Bool,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            HomeFeedPullRefreshLayoutModifier(
                pullDistance: pullDistance,
                triggerDistance: triggerDistance,
                isRefreshing: isRefreshing,
                isEnabled: isEnabled
            )
        )
    }

    @ViewBuilder
    func nativePullRefresh(
        isEnabled: Bool,
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        if isEnabled {
            refreshable(action: action)
        } else {
            self
        }
    }
}
