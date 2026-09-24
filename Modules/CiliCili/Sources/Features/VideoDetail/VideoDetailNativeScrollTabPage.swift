import SwiftUI

struct VideoDetailScrollAdjustment: Equatable {
    let tab: VideoDetailContentTab
    let offset: CGFloat
    let token: Int
}

struct VideoDetailNativeScrollTabPage<Content: View>: View {
    let tab: VideoDetailContentTab
    let layoutWidth: CGFloat
    let topInset: CGFloat
    var scrollAdjustment: VideoDetailScrollAdjustment?
    let onScrollOffsetChange: ((VideoDetailContentTab, CGFloat) -> Void)?
    let content: (VideoDetailContentTab) -> Content

    var body: some View {
        PlaybackDetailScrollPage(
            layoutWidth: layoutWidth,
            topInset: topInset,
            background: VideoDetailTheme.background,
            scrollAdjustment: pageScrollAdjustment,
            onScrollOffsetChange: onScrollOffsetChange.map { action in
                { offset in action(tab, offset) }
            },
            content: {
                content(tab)
            }
        )
        .defersRemoteImageLoadsDuringFastScroll()
    }

    private var pageScrollAdjustment: PlaybackDetailScrollAdjustment? {
        guard let scrollAdjustment, scrollAdjustment.tab == tab else {
            return nil
        }
        return PlaybackDetailScrollAdjustment(
            offset: scrollAdjustment.offset,
            token: scrollAdjustment.token
        )
    }
}
