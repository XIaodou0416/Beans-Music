import SwiftUI
import UIKit

struct VideoDetailSystemBackGestureBridge: UIViewControllerRepresentable {
    let onNavigationGestureBegan: (() -> Void)?
    let allowsSingleControllerNavigation: Bool
    let preservesSystemGestureDelegates: Bool

    init(
        onNavigationGestureBegan: (() -> Void)?,
        allowsSingleControllerNavigation: Bool = false,
        preservesSystemGestureDelegates: Bool = false
    ) {
        self.onNavigationGestureBegan = onNavigationGestureBegan
        self.allowsSingleControllerNavigation = allowsSingleControllerNavigation
        self.preservesSystemGestureDelegates = preservesSystemGestureDelegates
    }

    func makeUIViewController(context _: Context) -> Controller {
        Controller(
            onNavigationGestureBegan: onNavigationGestureBegan,
            allowsSingleControllerNavigation: allowsSingleControllerNavigation,
            preservesSystemGestureDelegates: preservesSystemGestureDelegates
        )
    }

    func updateUIViewController(_ uiViewController: Controller, context _: Context) {
        uiViewController.onNavigationGestureBegan = onNavigationGestureBegan
        uiViewController.allowsSingleControllerNavigation = allowsSingleControllerNavigation
        uiViewController.preservesSystemGestureDelegates = preservesSystemGestureDelegates
        if onNavigationGestureBegan == nil {
            uiViewController.detachFromSystemBackGestures()
        } else {
            uiViewController.restoreSystemBackGestures()
        }
    }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        var configuredContentPopID: ObjectIdentifier?
        var configuredScrollPanIDs = Set<ObjectIdentifier>()
        weak var attachedNavigationController: UINavigationController?
        var onNavigationGestureBegan: (() -> Void)?
        var allowsSingleControllerNavigation: Bool
        var preservesSystemGestureDelegates: Bool

        init(
            onNavigationGestureBegan: (() -> Void)?,
            allowsSingleControllerNavigation: Bool,
            preservesSystemGestureDelegates: Bool
        ) {
            self.onNavigationGestureBegan = onNavigationGestureBegan
            self.allowsSingleControllerNavigation = allowsSingleControllerNavigation
            self.preservesSystemGestureDelegates = preservesSystemGestureDelegates
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func loadView() {
            view = ClearPassthroughView()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if parent == nil {
                detachFromSystemBackGestures()
                onNavigationGestureBegan = nil
            } else {
                restoreSoon()
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            restoreSystemBackGestures()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            guard !preservesSystemGestureDelegates else { return }
            restoreSystemBackGestures()
        }

        private func restoreSoon() {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.parent != nil else { return }
                self.restoreSystemBackGestures()
            }
        }
    }
}

final class ClearPassthroughView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
