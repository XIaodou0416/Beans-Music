import QuartzCore
import SwiftUI
import UIKit

/// 全局高刷新率保持器，配合 Info.plist 请求设备支持的最高刷新率。
final class HighRefreshKeeper {
    static let shared = HighRefreshKeeper()
    static let defaultsKey = "beans.enableHighRefresh"

    private var displayLink: CADisplayLink?
    private var wasRunningBeforeTemporaryPause = false

    private init() {}

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [defaultsKey: true])
        UserDefaults.standard.set(true, forKey: defaultsKey)
    }

    func configureFromDefaults() {
        configure(enabled: UserDefaults.standard.bool(forKey: Self.defaultsKey))
    }

    func configure(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.defaultsKey)
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func attach(to view: UIView) {
        _ = view
        start()
    }

    /// 设置页展开大量控件时暂停空转的显示链接，避免低系统滚动时额外占用主线程。
    func suspendTemporarily() {
        guard displayLink != nil else { return }
        wasRunningBeforeTemporaryPause = true
        stop()
    }

    func resumeAfterTemporaryPause() {
        guard wasRunningBeforeTemporaryPause else { return }
        wasRunningBeforeTemporaryPause = false
        guard UserDefaults.standard.bool(forKey: Self.defaultsKey) else { return }
        start()
    }

    private func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        if #available(iOS 15.0, *) {
            let maximum = Float(min(120, max(60, UIScreen.main.maximumFramesPerSecond)))
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: maximum >= 120 ? 120 : maximum,
                maximum: maximum,
                preferred: maximum
            )
        } else {
            link.preferredFramesPerSecond = 120
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
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
