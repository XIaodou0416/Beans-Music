import SwiftUI
import UIKit

struct StatusBarStyleBridge: UIViewControllerRepresentable {
    let style: UIStatusBarStyle
    let isHidden: Bool

    func makeUIViewController(context _: Context) -> Controller {
        Controller(style: style, isHidden: isHidden)
    }

    func updateUIViewController(_ uiViewController: Controller, context _: Context) {
        uiViewController.update(style: style, isHidden: isHidden)
    }

    final class Controller: UIViewController {
        private(set) var style: UIStatusBarStyle
        private(set) var isHidden: Bool

        init(style: UIStatusBarStyle, isHidden: Bool) {
            self.style = style
            self.isHidden = isHidden
            super.init(nibName: nil, bundle: nil)
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var preferredStatusBarStyle: UIStatusBarStyle {
            style
        }

        override var prefersStatusBarHidden: Bool {
            isHidden
        }

        override var prefersHomeIndicatorAutoHidden: Bool {
            isHidden
        }

        override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
            isHidden ? .all : []
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            requestChromeUpdate()
        }

        func update(style: UIStatusBarStyle, isHidden: Bool) {
            guard self.style != style || self.isHidden != isHidden else { return }
            self.style = style
            self.isHidden = isHidden
            requestChromeUpdate()
        }

        private func requestChromeUpdate() {
            var controllers = [UIViewController]()
            var current: UIViewController? = self
            while let controller = current {
                controllers.append(controller)
                current = controller.parent
            }
            if let navigationController {
                controllers.append(navigationController)
            }
            if let tabBarController {
                controllers.append(tabBarController)
            }
            if let root = view.window?.rootViewController {
                controllers.append(root)
            }

            var updatedControllers = Set<ObjectIdentifier>()
            controllers.forEach { controller in
                guard updatedControllers.insert(ObjectIdentifier(controller)).inserted else { return }
                controller.setNeedsStatusBarAppearanceUpdate()
                controller.setNeedsUpdateOfHomeIndicatorAutoHidden()
            }
        }
    }
}
