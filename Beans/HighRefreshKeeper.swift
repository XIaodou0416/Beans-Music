import QuartzCore
import SwiftUI
import UIKit

/// 全局高刷新率保持器，配合 Info.plist 请求设备支持的最高刷新率。
final class HighRefreshKeeper {
    static let shared = HighRefreshKeeper()
    static let defaultsKey = "beans.enableHighRefresh"

    private weak var attachedScene: UIWindowScene?
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
        if let scene = view.window?.windowScene {
            attachedScene = scene
            applyPreferredFrameRate(to: scene)
        } else {
            // The representable can be updated before UIKit attaches its view.
            // The host view calls us again from didMoveToWindow.
            startLegacyDisplayLinkIfNeeded()
        }
    }

    /// 设置页展开大量控件时暂停空转的显示链接，避免低系统滚动时额外占用主线程。
    func suspendTemporarily() {
        guard attachedScene != nil || displayLink != nil else { return }
        wasRunningBeforeTemporaryPause = true
        if #available(iOS 15.0, *), let attachedScene {
            attachedScene.preferredFrameRateRange = .default
        }
        stopLegacyDisplayLink()
    }

    func resumeAfterTemporaryPause() {
        guard wasRunningBeforeTemporaryPause else { return }
        wasRunningBeforeTemporaryPause = false
        guard UserDefaults.standard.bool(forKey: Self.defaultsKey) else { return }
        start()
    }

    private func start() {
        if #available(iOS 15.0, *), let attachedScene {
            applyPreferredFrameRate(to: attachedScene)
        } else {
            startLegacyDisplayLinkIfNeeded()
        }
    }

    private func applyPreferredFrameRate(to scene: UIWindowScene) {
        guard UserDefaults.standard.bool(forKey: Self.defaultsKey) else {
            scene.preferredFrameRateRange = .default
            return
        }
        if #available(iOS 15.0, *) {
            let maximum = Float(min(120, max(60, UIScreen.main.maximumFramesPerSecond)))
            scene.preferredFrameRateRange = CAFrameRateRange(
                minimum: maximum >= 120 ? 120 : maximum,
                maximum: maximum,
                preferred: maximum
            )
            stopLegacyDisplayLink()
        } else {
            startLegacyDisplayLinkIfNeeded()
        }
    }

    private func startLegacyDisplayLinkIfNeeded() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stop() {
        if #available(iOS 15.0, *), let attachedScene {
            attachedScene.preferredFrameRateRange = .default
        }
        stopLegacyDisplayLink()
    }

    private func stopLegacyDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        // Pre-iOS 15 has no scene frame-rate preference API. Keeping this
        // lightweight display link preserves the legacy high-refresh request.
    }
}

private final class HighRefreshHostView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        HighRefreshKeeper.shared.attach(to: self)
    }
}

struct HighRefreshConfigurator: UIViewRepresentable {
    @Environment(\.beansSettingsPerformanceMode) private var settingsPerformanceMode

    func makeUIView(context: Context) -> UIView {
        let view = HighRefreshHostView(frame: .zero)
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
