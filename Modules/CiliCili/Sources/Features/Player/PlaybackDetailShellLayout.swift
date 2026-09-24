import CoreGraphics
import Foundation

enum PlaybackDetailRotationTiming {
    static let recoverySettleDelay: TimeInterval = 0.10
    static let portraitFullscreenDuration: TimeInterval = 0.42
}

/// UIKit 播放详情页共享的基础几何。
///
/// 视频详情会在此基础上叠加滚动收缩和竖屏视频全屏；直播则使用标准的
/// 16:9 顶部播放器。两者的普通竖屏与横屏全屏结构保持一致。
struct PlaybackDetailShellLayout {
    let playerFrame: CGRect
    let contentFrame: CGRect
    let contentTopInset: CGFloat?

    init(
        bounds: CGRect,
        safeAreaTop: CGFloat,
        playerHeight: CGFloat,
        contentTopInset: CGFloat,
        usesFullscreenLayout: Bool
    ) {
        if usesFullscreenLayout {
            playerFrame = bounds
            contentFrame = CGRect(
                x: bounds.minX,
                y: bounds.maxY,
                width: bounds.width,
                height: max(bounds.height, 1)
            )
            self.contentTopInset = nil
            return
        }

        let topInset = min(max(safeAreaTop, 0), bounds.height)
        let resolvedPlayerHeight = max(playerHeight, 0)
        playerFrame = CGRect(
            x: bounds.minX,
            y: bounds.minY + topInset,
            width: bounds.width,
            height: resolvedPlayerHeight
        )
        contentFrame = CGRect(
            x: bounds.minX,
            y: bounds.minY + topInset,
            width: bounds.width,
            height: max(bounds.height - topInset, 0)
        )
        self.contentTopInset = max(contentTopInset, 0)
    }

    static func standardPlayerHeight(for width: CGFloat) -> CGFloat {
        (max(width, 0) * 9 / 16).rounded()
    }
}
