import SwiftUI

@MainActor
struct CommentsSectionLifecycleActions {
    let autoLoads: Bool
    let beginInitialCommentsLoad: () -> Void

    func loadIfNeeded() async {
        guard autoLoads else { return }
        beginInitialCommentsLoad()
    }
}

private struct CommentsSectionLifecycleModifier: ViewModifier {
    let taskID: String
    let actions: CommentsSectionLifecycleActions

    func body(content: Content) -> some View {
        content
            .task(id: taskID) {
                await actions.loadIfNeeded()
            }
    }
}

extension View {
    func commentsSectionLifecycle(
        taskID: String,
        actions: CommentsSectionLifecycleActions
    ) -> some View {
        modifier(CommentsSectionLifecycleModifier(taskID: taskID, actions: actions))
    }
}
