import SwiftUI
import UIKit

extension View {
    @ViewBuilder
    func nativeNavigationSearch(
        text: Binding<String>,
        isPresented: Binding<Bool>,
        isKeyboardVisible: Binding<Bool> = .constant(false),
        isEnabled: Bool,
        prompt: String,
        title: String = "",
        onSubmit: @escaping () -> Void
    ) -> some View {
        if isEnabled {
            background {
                NativeNavigationSearchBridge(
                    text: text,
                    isPresented: isPresented,
                    isKeyboardVisible: isKeyboardVisible,
                    isEnabled: true,
                    prompt: prompt,
                    title: title,
                    onSubmit: onSubmit
                )
                .frame(width: 0, height: 0)
            }
        } else {
            self
        }
    }
}

private struct NativeNavigationSearchBridge: UIViewControllerRepresentable {
    @Binding var text: String
    @Binding var isPresented: Bool
    @Binding var isKeyboardVisible: Bool
    let isEnabled: Bool
    let prompt: String
    let title: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        context.coordinator.owner = controller
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        context.coordinator.owner = controller
        controller.update(
            text: $text,
            isPresented: $isPresented,
            isKeyboardVisible: $isKeyboardVisible,
            isEnabled: isEnabled,
            prompt: prompt,
            title: title,
            onSubmit: onSubmit,
            delegate: context.coordinator
        )
    }

    final class Coordinator: NSObject, UISearchResultsUpdating, UISearchBarDelegate {
        weak var owner: Controller?

        func updateSearchResults(for searchController: UISearchController) {
            owner?.syncText(searchController.searchBar.text)
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange _: String) {
            owner?.syncText(searchBar.text)
        }

        func searchBarTextDidBeginEditing(_: UISearchBar) {
            owner?.setKeyboardVisible(true)
            owner?.setPresented(true)
        }

        func searchBarTextDidEndEditing(_: UISearchBar) {
            owner?.setKeyboardVisible(false)
        }

        func searchBarCancelButtonClicked(_: UISearchBar) {
            owner?.setKeyboardVisible(false)
            owner?.setPresented(false)
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            owner?.syncText(searchBar.text)
            owner?.setKeyboardVisible(false)
            owner?.setPresented(false)
            owner?.submit()
        }
    }

    final class Controller: UIViewController {
        private var textBinding: Binding<String>?
        private var isPresentedBinding: Binding<Bool>?
        private var isKeyboardVisibleBinding: Binding<Bool>?
        private var onSubmit: (() -> Void)?
        private var navigationTitleText = ""
        private var isEnabled = false
        private weak var installedNavigationItem: UINavigationItem?
        private var searchController: UISearchController?
        private var restoredNavigationTitle: String?
        private var restoredNavigationTitleView: UIView?
        private var installedNavigationTitleView: UIView?

        override func loadView() {
            view = ClearPassthroughView()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if parent == nil {
                removeSearchController()
            } else {
                installSoon()
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            installSearchController()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            installSearchController()
        }

        func update(
            text: Binding<String>,
            isPresented: Binding<Bool>,
            isKeyboardVisible: Binding<Bool>,
            isEnabled: Bool,
            prompt: String,
            title: String,
            onSubmit: @escaping () -> Void,
            delegate: UISearchResultsUpdating & UISearchBarDelegate
        ) {
            textBinding = text
            isPresentedBinding = isPresented
            isKeyboardVisibleBinding = isKeyboardVisible
            self.isEnabled = isEnabled
            navigationTitleText = title
            self.onSubmit = onSubmit

            let controller = searchController ?? makeSearchController(delegate: delegate)
            searchController = controller
            controller.searchBar.placeholder = prompt
            if controller.searchBar.text != text.wrappedValue,
               controller.searchBar.searchTextField.markedTextRange == nil {
                controller.searchBar.text = text.wrappedValue
            }
            let shouldPresent = isEnabled && isPresented.wrappedValue
            if controller.isActive != shouldPresent {
                controller.isActive = shouldPresent
            }
            if isEnabled {
                installSearchController()
            } else {
                removeSearchController()
            }
        }

        func syncText(_ value: String?) {
            guard isEnabled,
                  searchController?.isActive == true,
                  let textBinding else { return }
            let value = value ?? ""
            guard textBinding.wrappedValue != value else { return }
            textBinding.wrappedValue = value
        }

        func setPresented(_ value: Bool) {
            isPresentedBinding?.wrappedValue = value
        }

        func setKeyboardVisible(_ value: Bool) {
            guard isKeyboardVisibleBinding?.wrappedValue != value else { return }
            isKeyboardVisibleBinding?.wrappedValue = value
        }

        func submit() {
            onSubmit?()
        }

        private func makeSearchController(
            delegate: UISearchResultsUpdating & UISearchBarDelegate
        ) -> UISearchController {
            let controller = UISearchController(searchResultsController: nil)
            controller.searchResultsUpdater = delegate
            controller.searchBar.delegate = delegate
            controller.searchBar.autocapitalizationType = .none
            controller.searchBar.autocorrectionType = .no
            controller.searchBar.returnKeyType = .search
            controller.obscuresBackgroundDuringPresentation = false
            controller.hidesNavigationBarDuringPresentation = false
            return controller
        }

        private func installSoon() {
            DispatchQueue.main.async { [weak self] in
                self?.installSearchController()
            }
        }

        private func installSearchController() {
            guard isEnabled,
                  let searchController,
                  let navigationController = enclosingNavigationController(),
                  let navigationItem = navigationController.topViewController?.navigationItem
            else {
                return
            }

            if installedNavigationItem !== navigationItem {
                if let oldItem = installedNavigationItem,
                   oldItem.searchController === searchController {
                    oldItem.searchController = nil
                    oldItem.title = restoredNavigationTitle
                    oldItem.titleView = restoredNavigationTitleView
                }
                restoredNavigationTitle = navigationItem.title
                restoredNavigationTitleView = navigationItem.titleView
                navigationItem.titleView = nil
                navigationItem.searchController = searchController
                installedNavigationItem = navigationItem
            }
            if !navigationTitleText.isEmpty {
                navigationItem.title = navigationTitleText
                if installedNavigationTitleView == nil {
                    let titleLabel = UILabel()
                    titleLabel.font = .preferredFont(forTextStyle: .headline)
                    titleLabel.textColor = .label
                    titleLabel.textAlignment = .center
                    titleLabel.text = navigationTitleText
                    titleLabel.isAccessibilityElement = true
                    titleLabel.accessibilityLabel = navigationTitleText
                    titleLabel.sizeToFit()
                    installedNavigationTitleView = titleLabel
                }
                if let installedNavigationTitleView {
                    navigationItem.titleView = installedNavigationTitleView
                }
            }
            navigationItem.preferredSearchBarPlacement = .stacked
            navigationItem.searchBarPlacementAllowsToolbarIntegration = false
            navigationItem.hidesSearchBarWhenScrolling = false
            navigationController.view.setNeedsLayout()
            DispatchQueue.main.async { [weak self, weak navigationItem] in
                guard let self,
                      let navigationItem,
                      self.isEnabled,
                      self.installedNavigationItem === navigationItem,
                      !self.navigationTitleText.isEmpty else {
                    return
                }
                navigationItem.title = self.navigationTitleText
            }
        }

        private func removeSearchController() {
            setKeyboardVisible(false)
            guard let searchController else { return }
            if installedNavigationItem?.searchController === searchController {
                installedNavigationItem?.searchController = nil
                installedNavigationItem?.title = restoredNavigationTitle
                installedNavigationItem?.titleView = restoredNavigationTitleView
            }
            installedNavigationItem = nil
            restoredNavigationTitle = nil
            restoredNavigationTitleView = nil
            installedNavigationTitleView = nil
        }

        private func enclosingNavigationController() -> UINavigationController? {
            var controller: UIViewController? = self
            while let current = controller {
                if let navigationController = current as? UINavigationController {
                    return navigationController
                }
                if let navigationController = current.navigationController {
                    return navigationController
                }
                controller = current.parent
            }

            var responder: UIResponder? = view
            while let current = responder {
                if let navigationController = current as? UINavigationController {
                    return navigationController
                }
                responder = current.next
            }
            return nil
        }

    }
}
