import SwiftUI
import UIKit
import QuartzCore

/// 全局高刷新率保持器。配合 Info.plist 的 CADisableMinimumFrameDurationOnPhone 强制请求 120Hz。
final class HighRefreshKeeper {
    static let shared = HighRefreshKeeper()
    static let defaultsKey = "beans.enableHighRefresh"

    private weak var hostView: UIView?

    private init() {}

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [defaultsKey: true])
        UserDefaults.standard.set(true, forKey: defaultsKey)
    }

    func configureFromDefaults() {
        configure(enabled: true)
    }

    func configure(enabled: Bool) {
        UserDefaults.standard.set(true, forKey: Self.defaultsKey)
        apply()
    }

    func attach(to view: UIView) {
        hostView = view
        apply()
    }

    func start() {
        configure(enabled: true)
    }

    func stop() {
        configure(enabled: true)
    }

    private func apply() {
        guard let hostView else { return }
        guard #available(iOS 15.0, *) else { return }

        let screenMaximum = Float(max(60, UIScreen.main.maximumFramesPerSecond))
        let preferred = min(screenMaximum, 120)
        let minimum: Float = preferred >= 120 ? 80 : preferred
        let range = CAFrameRateRange(minimum: minimum, maximum: preferred, preferred: preferred)

        // Xcode 26 no longer exposes preferredFrameRateRange on UIView/ UIWindow.
        // The frame-rate preference belongs to the window scene.
        hostView.window?.windowScene?.preferredFrameRateRange = range
    }
}

struct HighRefreshConfigurator: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            HighRefreshKeeper.shared.attach(to: view)
            HighRefreshKeeper.shared.configure(enabled: true)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            HighRefreshKeeper.shared.attach(to: uiView)
            HighRefreshKeeper.shared.configure(enabled: true)
        }
    }
}
