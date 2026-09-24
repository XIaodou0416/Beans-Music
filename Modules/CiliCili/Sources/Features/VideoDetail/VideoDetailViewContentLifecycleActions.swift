import Foundation

@MainActor
struct VideoDetailViewContentLifecycleActions {
    let configureViewModel: @MainActor () -> Void

    func configureInitialViewModelIfNeeded() {
        configureViewModel()
    }
}
