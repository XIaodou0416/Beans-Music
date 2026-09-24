import SwiftUI

struct HomeFeedScrollPreferenceModifier: ViewModifier {
    @Binding var viewportState: HomeFeedViewportState
    let scrollActions: HomeFeedScrollActions

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(HomeFeedWidthPreferenceKey.self, perform: updateFeedContainerWidth)
            .onPreferenceChange(HomeViewportHeightPreferenceKey.self, perform: updateViewportHeight)
    }
}

extension View {
    func homeFeedScrollPreferenceHandling(
        viewportState: Binding<HomeFeedViewportState>,
        scrollActions: HomeFeedScrollActions
    ) -> some View {
        modifier(
            HomeFeedScrollPreferenceModifier(
                viewportState: viewportState,
                scrollActions: scrollActions
            )
        )
    }
}
