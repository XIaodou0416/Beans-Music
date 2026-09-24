import UIKit

extension VideoDetailSystemBackGestureBridge.Controller {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigationController = attachedNavigationController ?? enclosingNavigationController(),
              allowsSingleControllerNavigation || navigationController.viewControllers.count > 1,
              navigationController.transitionCoordinator == nil
        else {
            return false
        }

        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
            return true
        }

        let velocity = panGesture.velocity(in: navigationController.view)
        guard velocity.x > 0 && abs(velocity.x) > abs(velocity.y) else {
            return false
        }
        onNavigationGestureBegan?()
        return true
    }
}
