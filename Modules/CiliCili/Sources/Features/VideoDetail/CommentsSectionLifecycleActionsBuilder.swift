import Foundation

@MainActor
struct CommentsSectionLifecycleActionsBuilder {
    let autoLoads: Bool
    let beginInitialCommentsLoad: () -> Void

    var actions: CommentsSectionLifecycleActions {
        CommentsSectionLifecycleActions(
            autoLoads: autoLoads,
            beginInitialCommentsLoad: beginInitialCommentsLoad
        )
    }
}
