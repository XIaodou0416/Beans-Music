import UIKit

extension VideoDetailSystemBackGestureBridge.Controller {
    func restoreSystemBackGestures() {
        guard parent != nil else { return }
        guard let navigationController = enclosingNavigationController() else {
            return
        }
        attachedNavigationController = navigationController

        if !preservesSystemGestureDelegates,
           let popGesture = navigationController.interactivePopGestureRecognizer {
            popGesture.isEnabled = true
            popGesture.delegate = self
        }

        guard let contentPopGesture = navigationController.interactiveContentPopGestureRecognizer else {
            return
        }
        if !preservesSystemGestureDelegates {
            contentPopGesture.isEnabled = true
            contentPopGesture.delegate = self
        }
        prioritizeSystemContentPopGesture(contentPopGesture, in: navigationController.view)
    }

    func prioritizeSystemContentPopGesture(_ contentPopGesture: UIGestureRecognizer, in rootView: UIView) {
        let contentPopID = ObjectIdentifier(contentPopGesture)
        if configuredContentPopID != contentPopID {
            configuredContentPopID = contentPopID
            configuredScrollPanIDs.removeAll()
        }

        for scrollView in scrollViews(in: rootView) {
            let panGesture = scrollView.panGestureRecognizer
            let panID = ObjectIdentifier(panGesture)
            guard configuredScrollPanIDs.insert(panID).inserted else { continue }
            panGesture.require(toFail: contentPopGesture)
        }
    }

    func detachFromSystemBackGestures() {
        guard let navigationController = attachedNavigationController else { return }
        if navigationController.interactivePopGestureRecognizer?.delegate === self {
            navigationController.interactivePopGestureRecognizer?.delegate = nil
        }
        if navigationController.interactiveContentPopGestureRecognizer?.delegate === self {
            navigationController.interactiveContentPopGestureRecognizer?.delegate = nil
        }
        attachedNavigationController = nil
        configuredContentPopID = nil
        configuredScrollPanIDs.removeAll()
    }
}
