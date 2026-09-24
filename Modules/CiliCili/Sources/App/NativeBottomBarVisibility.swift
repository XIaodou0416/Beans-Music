import SwiftUI
import UIKit

extension View {
    @ViewBuilder
    func coordinatesRootTabBarTransitions(
        isDetailPresented: Bool,
        isEnabled: Bool = true
    ) -> some View {
        if isEnabled {
            background(
                NativeRootTabBarTransitionSource(isDetailPresented: isDetailPresented)
            )
        } else {
            self
        }
    }
}

private struct NativeRootTabBarTransitionSource: UIViewControllerRepresentable {
    let isDetailPresented: Bool

    func makeUIViewController(context _: Context) -> Controller {
        Controller(isDetailPresented: isDetailPresented)
    }

    func updateUIViewController(_ controller: Controller, context _: Context) {
        controller.update(isDetailPresented: isDetailPresented)
    }

    final class Controller: UIViewController {
        private var isDetailPresented: Bool
        private var reconcileTask: Task<Void, Never>?

        init(isDetailPresented: Bool) {
            self.isDetailPresented = isDetailPresented
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func loadView() {
            let view = UIView(frame: .zero)
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            self.view = view
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            reconcile(animated: false)
        }

        func update(isDetailPresented: Bool) {
            guard self.isDetailPresented != isDetailPresented else { return }
            self.isDetailPresented = isDetailPresented
            reconcileSoon()
        }

        private func reconcileSoon() {
            reconcileTask?.cancel()
            reconcileTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled,
                      let self,
                      self.viewIfLoaded?.window != nil,
                      let navigationController = self.selectedNavigationController() else { return }
                let animated = navigationController.transitionCoordinator != nil
                self.setRootTabBarHidden(self.isDetailPresented, animated: animated)
            }
        }

        private func reconcile(animated: Bool) {
            guard viewIfLoaded?.window != nil,
                  selectedNavigationController() != nil else { return }
            setRootTabBarHidden(isDetailPresented, animated: animated)
        }

        private func setRootTabBarHidden(_ hidden: Bool, animated: Bool) {
            guard let tabBarController = enclosingTabBarController(),
                  tabBarController.isTabBarHidden != hidden else { return }
            tabBarController.setTabBarHidden(hidden, animated: animated)
        }

        private func enclosingTabBarController() -> UITabBarController? {
            if let tabBarController { return tabBarController }
            var responder: UIResponder? = view
            while let current = responder {
                if let tabBarController = current as? UITabBarController { return tabBarController }
                responder = current.next
            }
            return nil
        }

        private func selectedNavigationController() -> UINavigationController? {
            guard let selected = enclosingTabBarController()?.selectedViewController else { return nil }
            return navigationController(in: selected)
        }

        private func navigationController(in controller: UIViewController) -> UINavigationController? {
            if let navigationController = controller as? UINavigationController {
                return navigationController
            }
            for child in controller.children {
                if let navigationController = navigationController(in: child) {
                    return navigationController
                }
            }
            return nil
        }
    }
}
