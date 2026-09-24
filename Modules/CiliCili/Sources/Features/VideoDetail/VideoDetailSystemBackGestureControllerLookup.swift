import UIKit

extension VideoDetailSystemBackGestureBridge.Controller {
    func scrollViews(in rootView: UIView) -> [UIScrollView] {
        var result = [UIScrollView]()
        var stack = rootView.subviews
        while let view = stack.popLast() {
            if let scrollView = view as? UIScrollView {
                result.append(scrollView)
            }
            stack.append(contentsOf: view.subviews)
        }
        return result
    }

    func enclosingNavigationController() -> UINavigationController? {
        if let navigationController {
            return navigationController
        }

        var current = parent
        while let viewController = current {
            if let navigationController = viewController as? UINavigationController {
                return navigationController
            }
            if let navigationController = viewController.navigationController {
                return navigationController
            }
            current = viewController.parent
        }

        var responder: UIResponder? = view
        while let current = responder {
            if let viewController = current as? UIViewController,
               let navigationController = viewController.navigationController {
                return navigationController
            }
            responder = current.next
        }
        return nil
    }
}
