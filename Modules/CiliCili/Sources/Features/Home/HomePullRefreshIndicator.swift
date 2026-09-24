import SwiftUI

struct HomePullRefreshIndicator: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let pullDistance: CGFloat
    let triggerDistance: CGFloat
    let isRefreshing: Bool
    let suppressesPullProgress: Bool

    private var progress: CGFloat {
        Self.normalizedProgress(
            pullDistance: pullDistance,
            triggerDistance: triggerDistance
        )
    }

    private var isVisible: Bool {
        Self.shouldShowIndicator(
            progress: progress,
            isRefreshing: isRefreshing,
            suppressesPullProgress: suppressesPullProgress
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isRefreshing)) { timeline in
            ZStack {
                if isVisible {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(appTintColor)
                        .rotationEffect(
                            .degrees(
                                Self.rotationDegrees(
                                    progress: progress,
                                    isRefreshing: isRefreshing,
                                    date: timeline.date
                                )
                            )
                        )
                        .frame(width: 36, height: 36)
                        .biliRegularGlassEffect(interactive: false, in: Circle())
                        .scaleEffect(0.86 + progress * 0.14)
                        .transition(.opacity.combined(with: .scale(scale: 0.82)))
                }
            }
        }
        .frame(width: 36, height: 36)
        .offset(y: isVisible ? min(max(pullDistance * 0.18, 0), 14) : -8)
        .animation(.smooth(duration: 0.18), value: isVisible)
        .animation(
            isRefreshing
                ? .smooth(duration: 0.18)
                : .smooth(duration: 0.2),
            value: isRefreshing
        )
        .animation(.easeOut(duration: 0.12), value: progress)
        .accessibilityLabel(isRefreshing ? "正在刷新" : "下拉刷新")
        .accessibilityValue(isRefreshing ? "" : "\(Int((progress * 100).rounded()))%")
        .accessibilityHidden(!isVisible)
    }

    static func normalizedProgress(
        pullDistance: CGFloat,
        triggerDistance: CGFloat
    ) -> CGFloat {
        guard triggerDistance > 0 else { return 0 }
        return min(max(pullDistance / triggerDistance, 0), 1)
    }

    static func shouldShowIndicator(
        progress: CGFloat,
        isRefreshing: Bool,
        suppressesPullProgress: Bool
    ) -> Bool {
        isRefreshing || (!suppressesPullProgress && progress > 0.08)
    }

    static func rotationDegrees(
        progress: CGFloat,
        isRefreshing: Bool,
        date: Date
    ) -> Double {
        guard isRefreshing else {
            return Double(progress) * 270
        }
        let rotationDuration = 0.8
        let phase = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: rotationDuration)
        return phase / rotationDuration * 360
    }
}
