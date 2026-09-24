import SwiftUI

extension HomeFeedScrollPreferenceModifier {
    func updateFeedContainerWidth(_ width: CGFloat) {
        viewportState = scrollActions.updateFeedContainerWidth(width, state: viewportState)
    }

    func updateViewportHeight(_ height: CGFloat) {
        viewportState = scrollActions.updateViewportHeight(
            height,
            state: viewportState
        )
    }
}
