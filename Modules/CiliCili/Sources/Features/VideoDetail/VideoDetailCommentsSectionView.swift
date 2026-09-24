import SwiftUI

struct CommentsSectionView: View {
    @ObservedObject var store: VideoDetailCommentsRenderStore
    let style: CommentSectionStyle
    let maxVisibleComments: Int?
    let autoLoads: Bool
    let actions: VideoDetailCommentsSectionActions
    let lifecycleActions: CommentsSectionLifecycleActions
    let verticalPadding: CGFloat

    init(
        store: VideoDetailCommentsRenderStore,
        style: CommentSectionStyle,
        maxVisibleComments: Int?,
        autoLoads: Bool = true,
        actions: VideoDetailCommentsSectionActions,
        verticalPadding: CGFloat = 9
    ) {
        self.store = store
        self.style = style
        self.maxVisibleComments = maxVisibleComments
        self.autoLoads = autoLoads
        self.actions = actions
        self.verticalPadding = verticalPadding
        lifecycleActions = CommentsSectionLifecycleActionsBuilder(
            autoLoads: autoLoads,
            beginInitialCommentsLoad: actions.beginInitialCommentsLoad
        )
        .actions
    }

    private var commentsLoadTaskID: String {
        [
            store.detail?.bvid ?? "",
            store.detail?.cid.map(String.init) ?? "cid-",
            store.detail?.pgcEpisodeID.map { "ep\($0)" } ?? "ep-",
            String(autoLoads)
        ].joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CommentsSectionHeader(
                store: store,
                style: style,
                selectCommentSort: actions.selectCommentSortAction
            )

            CommentsSectionContent(
                store: store,
                style: style,
                maxVisibleComments: maxVisibleComments,
                shouldShowLoadingPlaceholder: shouldShowLoadingPlaceholder,
                actions: actions
            )
        }
        .padding(.vertical, verticalPadding)
        .background(style == .grouped ? VideoDetailTheme.surface : Color.clear)
        .commentsSectionLifecycle(taskID: commentsLoadTaskID, actions: lifecycleActions)
    }

    private var shouldShowLoadingPlaceholder: Bool {
        store.state.isLoading || (autoLoads && store.state == .idle)
    }
}
