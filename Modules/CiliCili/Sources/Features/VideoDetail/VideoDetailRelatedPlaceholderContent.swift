import SwiftUI

struct VideoDetailRelatedPlaceholderContent: View {
    let layout: VideoDetailRelatedListLayout
    let state: LoadingState
    let didTimeOut: Bool
    let actions: VideoDetailRelatedPlaceholderActions

    init(
        layout: VideoDetailRelatedListLayout,
        state: LoadingState,
        didTimeOut: Bool,
        retryRelated: @escaping () async -> Void
    ) {
        self.layout = layout
        self.state = state
        self.didTimeOut = didTimeOut
        actions = VideoDetailRelatedPlaceholderActions(retryRelated: retryRelated)
    }

    var body: some View {
        if case .failed(let message) = state {
            RelatedVideoRetryState(
                message: didTimeOut ? "相关推荐加载超时，可以稍后重试。" : message
            ) { actions.retry() }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.vertical, VideoDetailRelatedStyle.retryVerticalPadding)
        } else {
            VideoDetailRelatedPlaceholderList(layout: layout)
            .padding(.horizontal, layout.horizontalPadding)
            .allowsHitTesting(false)
        }
    }
}
