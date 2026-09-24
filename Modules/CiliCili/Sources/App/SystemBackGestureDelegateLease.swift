import UIKit

@MainActor
final class SystemBackGestureDelegateLease {
    private weak var navigationController: UINavigationController?
    private weak var ownerObject: AnyObject?
    private var inheritedEdgePopDelegate: UIGestureRecognizerDelegate?
    private var inheritedContentPopDelegate: UIGestureRecognizerDelegate?

    func acquire(
        in navigationController: UINavigationController,
        owner: UIGestureRecognizerDelegate
    ) {
        let ownerObject = owner as AnyObject
        if self.navigationController !== navigationController || self.ownerObject !== ownerObject {
            release()
            self.navigationController = navigationController
            self.ownerObject = ownerObject
            inheritedEdgePopDelegate = navigationController.interactivePopGestureRecognizer?.delegate
            inheritedContentPopDelegate = navigationController.interactiveContentPopGestureRecognizer?.delegate
        }

        if let edgePopGesture = navigationController.interactivePopGestureRecognizer {
            edgePopGesture.isEnabled = true
            edgePopGesture.delegate = owner
        }
        if let contentPopGesture = navigationController.interactiveContentPopGestureRecognizer {
            contentPopGesture.isEnabled = true
            contentPopGesture.delegate = owner
        }
    }

    func release() {
        guard let navigationController, let ownerObject else {
            reset()
            return
        }

        if let edgePopGesture = navigationController.interactivePopGestureRecognizer,
           Self.isOwned(edgePopGesture.delegate, by: ownerObject) {
            edgePopGesture.delegate = inheritedEdgePopDelegate
        }
        if let contentPopGesture = navigationController.interactiveContentPopGestureRecognizer,
           Self.isOwned(contentPopGesture.delegate, by: ownerObject) {
            contentPopGesture.delegate = inheritedContentPopDelegate
        }
        reset()
    }

    private func reset() {
        navigationController = nil
        ownerObject = nil
        inheritedEdgePopDelegate = nil
        inheritedContentPopDelegate = nil
    }

    private static func isOwned(
        _ delegate: UIGestureRecognizerDelegate?,
        by ownerObject: AnyObject
    ) -> Bool {
        guard let delegate else { return false }
        return delegate as AnyObject === ownerObject
    }
}
