import Foundation

@MainActor
struct HomeFeedScreenLifecycleModifierActions {
    let actions: HomeFeedScreenLifecycleHostActions

    func start() async {
        await actions.start()
    }

    func handleVideosChanged() {
        actions.handleVideosChanged()
    }
}
