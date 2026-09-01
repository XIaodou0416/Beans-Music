import SwiftUI
import UIKit

/// 全局高刷新率配置器。通过窗口帧率范围请求设备支持的最高刷新率，
/// 不创建常驻 CADisplayLink，避免设置页和其他页面持续空转发热。
final class HighRefreshKeeper {
    static let shared = HighRefreshKeeper()
    static let defaultsKey = "beans.enableHighRefresh"

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
    }

    func attach(to view: UIView) {
        guard UserDefaults.standard.bool(forKey: Self.defaultsKey) else { return }
        apply(to: view)
        DispatchQueue.main.async { [weak self, weak view] in
            guard let self, let view else { return }
            self.apply(to: view)
            if let rootView = view.window?.rootViewController?.view {
                self.apply(to: rootView)
            }
        }
    }

    private func apply(to view: UIView) {
        if #available(iOS 15.0, *) {
            view.preferredFrameRateRange = CAFrameRateRange(
                minimum: 120,
                maximum: 120,
                preferred: 120
            )
        }
    }
}

struct HighRefreshConfigurator: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        HighRefreshKeeper.shared.attach(to: uiView)
    }
}
