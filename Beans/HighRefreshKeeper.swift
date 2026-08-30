import SwiftUI
import UIKit

/// 全局高刷新率配置器。由 Info.plist 请求设备支持的最高刷新率，
/// 不再创建常驻 CADisplayLink，避免设置页和其他页面持续空转发热。
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
        _ = view
    }
}

struct HighRefreshConfigurator: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        _ = uiView
    }
}
