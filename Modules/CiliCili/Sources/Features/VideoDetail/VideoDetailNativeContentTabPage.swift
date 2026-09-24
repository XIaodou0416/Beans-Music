import SwiftUI

struct VideoDetailNativeContentTabPage<Content: View>: View {
    let tab: VideoDetailContentTab
    let layoutWidth: CGFloat
    let topInset: CGFloat
    var scrollAdjustment: VideoDetailScrollAdjustment?
    let onScrollOffsetChange: ((VideoDetailContentTab, CGFloat) -> Void)?
    let content: (VideoDetailContentTab) -> Content

    var body: some View {
        VideoDetailNativeScrollTabPage(
            tab: tab,
            layoutWidth: layoutWidth,
            topInset: topInset,
            scrollAdjustment: scrollAdjustment,
            onScrollOffsetChange: onScrollOffsetChange,
            content: content
        )
    }
}
