import QuartzCore
import SwiftUI
import UIKit

/// 全局高刷新率保持器，配合 Info.plist 请求设备支持的最高刷新率。
final class HighRefreshKeeper {
    static let shared = HighRefreshKeeper()

    private var displayLink: CADisplayLink?
    private var wasRunningBeforeTemporaryPause = false
    private var isStarting = false
    private init() {}

    /// 始终按设备支持的最高刷新率创建一个共享 display link。
    /// 应用不再暴露“强制高刷新率”开关，避免旧开关状态导致启动重入或闪退。
    func startIfNeeded() {
        start()
    }

    func attach(to view: UIView) {
        _ = view
        start()
    }

    /// 设置页展开大量控件时暂停刷新率请求，避免额外占用主线程。
    func suspendTemporarily() {
        guard displayLink != nil else { return }
        wasRunningBeforeTemporaryPause = true
        stop()
    }

    func resumeAfterTemporaryPause() {
        guard wasRunningBeforeTemporaryPause else { return }
        wasRunningBeforeTemporaryPause = false
        start()
    }

    private func start() {
        guard displayLink == nil, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = preferredFrameRateRange
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private var preferredFrameRateRange: CAFrameRateRange {
        let maximum = Float(min(120, max(60, UIScreen.main.maximumFramesPerSecond)))
        let minimum: Float = maximum >= 120 ? 120 : 60
        return CAFrameRateRange(minimum: minimum, maximum: maximum, preferred: maximum)
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {}
}

struct HighRefreshConfigurator: UIViewRepresentable {
    @Environment(\.beansSettingsPerformanceMode) private var settingsPerformanceMode

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if settingsPerformanceMode || PlaybackRenderGate.shared.isSuppressed {
            HighRefreshKeeper.shared.suspendTemporarily()
        } else {
            HighRefreshKeeper.shared.attach(to: uiView)
        }
    }
}

