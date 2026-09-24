import SwiftUI

struct CommentsSectionContent: View {
    @ObservedObject var store: VideoDetailCommentsRenderStore
    let style: CommentSectionStyle
    let maxVisibleComments: Int?
    let shouldShowLoadingPlaceholder: Bool
    let actions: VideoDetailCommentsSectionActions

    var body: some View {
        CommentsSectionContentStateView(
            state: contentState,
            store: store,
            style: style,
            maxVisibleComments: maxVisibleComments,
            actions: actions
        )
    }

    private var contentState: CommentsSectionContentState {
        CommentsSectionContentState(
            store: store,
            shouldShowLoadingPlaceholder: shouldShowLoadingPlaceholder
        )
    }
}
