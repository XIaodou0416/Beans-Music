import SwiftUI

struct VideoDetailRelatedSectionContent: View {
    let relatedItems: [VideoDetailRelatedDisplayItem]
    let layout: VideoDetailRelatedListLayout
    let state: LoadingState
    let didTimeOut: Bool
    let retryRelated: () async -> Void
    let listActions: VideoDetailRelatedListActions

    var body: some View {
        VStack(alignment: .leading, spacing: VideoDetailRelatedStyle.sectionSpacing) {
            VideoDetailRelatedHeader(isLoading: showsLoadingPlaceholder)
                .padding(.horizontal, layout.horizontalPadding)

            if !relatedItems.isEmpty {
                VideoDetailRelatedList(
                    items: relatedItems,
                    layout: layout,
                    actions: listActions
                )
                .padding(.horizontal, layout.horizontalPadding)
                .transition(.opacity)
            } else {
                VideoDetailRelatedPlaceholderContent(
                    layout: layout,
                    state: state,
                    didTimeOut: didTimeOut,
                    retryRelated: retryRelated
                )
            }
        }
    }

    private var showsLoadingPlaceholder: Bool {
        relatedItems.isEmpty && (state == .idle || state.isLoading)
    }
}
