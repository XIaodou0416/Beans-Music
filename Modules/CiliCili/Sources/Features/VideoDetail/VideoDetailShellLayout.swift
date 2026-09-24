import CoreGraphics
import Foundation

/// 详情页播放器和内容区共享的几何模型。
///
/// 该类型不持有 View，也不触发状态写回。SwiftUI 内容区只消费
/// `contentTopInset`，UIKit surface 只消费 `playerFrame`，从而避免滚动时
/// 通过重建内容树反馈播放器高度。
@MainActor
struct VideoDetailShellLayout: Equatable {
    static let collapsedToolbarHeight: CGFloat = 54

    let playerFrame: CGRect
    let contentFrame: CGRect
    let contentTopInset: CGFloat?
    let usesFullscreenLayout: Bool

    static func standardPlayerHeight(forWidth width: CGFloat) -> CGFloat {
        (max(width, 0) * 9 / 16).rounded()
    }

    static func supportsInteractiveCollapse(
        videoAspectRatio: CGFloat,
        isPlaybackActive: Bool = false
    ) -> Bool {
        videoAspectRatio > 0 && (!isPlaybackActive || videoAspectRatio < 0.9)
    }

    static func scrollContentMinimumHeight(
        viewportHeight: CGFloat,
        expandedPlayerHeight: CGFloat,
        minimumPlayerHeight: CGFloat
    ) -> CGFloat {
        max(viewportHeight, 0)
            + max(expandedPlayerHeight - minimumPlayerHeight, 0)
    }

    static func interactiveScrollMetrics(
        scrollOffset: CGFloat,
        expandedPlayerHeight: CGFloat,
        minimumPlayerHeight: CGFloat
    ) -> VideoDetailInteractiveScrollMetrics {
        VideoDetailInteractiveScrollMetrics(
            scrollOffset: scrollOffset,
            expandedPlayerHeight: expandedPlayerHeight,
            minimumPlayerHeight: minimumPlayerHeight
        )
    }

    static func expandedPlayerHeight(
        bounds: CGSize,
        videoAspectRatio: CGFloat
    ) -> CGFloat {
        let standard = standardPlayerHeight(forWidth: bounds.width)
        guard videoAspectRatio < 0.9 else { return standard }
        let proposed = max(bounds.height * 0.65, bounds.width)
        let maximum = max(standard, bounds.height * 0.72)
        return max(standard, min(proposed, maximum))
    }

    static func minimumPlayerHeight(
        forWidth width: CGFloat,
        isPlaybackActive: Bool
    ) -> CGFloat {
        isPlaybackActive
            ? standardPlayerHeight(forWidth: width)
            : collapsedToolbarHeight
    }

    static func resolvedPlayerHeight(
        bounds: CGSize,
        videoAspectRatio: CGFloat,
        currentPlayerHeight: CGFloat?,
        isPlaybackActive: Bool
    ) -> CGFloat {
        let expanded = expandedPlayerHeight(
            bounds: bounds,
            videoAspectRatio: videoAspectRatio
        )
        let minimum = minimumPlayerHeight(
            forWidth: bounds.width,
            isPlaybackActive: isPlaybackActive
        )
        return max(minimum, min(currentPlayerHeight ?? expanded, expanded))
    }

    static func resolve(
        bounds: CGRect,
        safeAreaTop: CGFloat,
        videoAspectRatio: CGFloat,
        currentPlayerHeight: CGFloat?,
        isPlaybackActive: Bool,
        isLandscape: Bool,
        isPortraitFullscreen: Bool
    ) -> Self {
        let usesFullscreenLayout = isLandscape || isPortraitFullscreen
        let canInteractivelyCollapse = supportsInteractiveCollapse(
            videoAspectRatio: videoAspectRatio,
            isPlaybackActive: isPlaybackActive
        )
        let playerHeight =
            usesFullscreenLayout
            ? bounds.height
            : resolvedPlayerHeight(
                bounds: bounds.size,
                videoAspectRatio: videoAspectRatio,
                currentPlayerHeight: currentPlayerHeight,
                isPlaybackActive: isPlaybackActive
            )
        if usesFullscreenLayout {
            return Self(
                playerFrame: bounds,
                contentFrame: CGRect(
                    x: bounds.minX,
                    y: bounds.maxY,
                    width: bounds.width,
                    height: max(bounds.height, 1)
                ),
                contentTopInset: nil,
                usesFullscreenLayout: true
            )
        }

        return Self(
            playerFrame: CGRect(
                x: bounds.minX,
                y: bounds.minY + max(0, safeAreaTop),
                width: bounds.width,
                height: max(playerHeight, 0)
            ),
            contentFrame: CGRect(
                x: bounds.minX,
                y: bounds.minY + max(0, safeAreaTop),
                width: bounds.width,
                height: max(bounds.height - max(0, safeAreaTop), 0)
            ),
            contentTopInset: canInteractivelyCollapse
                ? expandedPlayerHeight(
                    bounds: bounds.size,
                    videoAspectRatio: videoAspectRatio
                )
                : max(playerHeight, 0),
            usesFullscreenLayout: false
        )
    }
}

@MainActor
struct VideoDetailInteractiveScrollMetrics: Equatable {
    let scrollOffset: CGFloat
    let collapseOffset: CGFloat
    let contentOffset: CGFloat
    let collapseDistance: CGFloat

    init(
        scrollOffset: CGFloat,
        expandedPlayerHeight: CGFloat,
        minimumPlayerHeight: CGFloat
    ) {
        let normalizedScrollOffset = max(scrollOffset, 0)
        let expandedHeight = max(expandedPlayerHeight, 0)
        let minimumHeight = min(max(minimumPlayerHeight, 0), expandedHeight)
        let distance = max(expandedHeight - minimumHeight, 0)
        self.scrollOffset = normalizedScrollOffset
        collapseOffset = min(normalizedScrollOffset, distance)
        contentOffset = max(normalizedScrollOffset - distance, 0)
        collapseDistance = distance
    }

    var isPlayerCollapsed: Bool {
        collapseOffset >= collapseDistance - 0.5
    }
}
