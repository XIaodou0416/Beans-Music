import SwiftUI

struct DynamicHomeVideoFeedCard: View {
    let video: VideoItem
    let display: DynamicFeedCardDisplayModel
    let initialIsLiked: Bool
    let contentWidth: CGFloat?
    let usesExternalHorizontalInsets: Bool
    let onShowComments: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            authorHeader
                .padding(.horizontal, horizontalContentInset)

            VideoRouteLink(video) {
                VStack(alignment: .leading, spacing: 9) {
                    VStack(alignment: .leading, spacing: 0) {
                        DynamicVideoTitleText(
                            video.title,
                            style: .feed,
                            lineLimit: 1
                        )
                    }
                    .padding(.horizontal, horizontalContentInset)

                    if let videoDisplay = display.videoDisplay {
                        DynamicFeedVideoCover(video: video, display: videoDisplay)
                    }
                }
                .contentShape(Rectangle())
            }

            DynamicFeedActionBar(
                display: display,
                initialIsLiked: initialIsLiked,
                initialLikeCount: display.initialLikeCount,
                onShowComments: onShowComments
            )
        }
        .padding(.top, 5)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("鐟欏棝顣?\(video.title)")
    }

    private var authorHeader: some View {
        DynamicFeedAuthorHeader(display: display)
    }

    private var horizontalContentInset: CGFloat {
        usesExternalHorizontalInsets ? 0 : 12
    }
}
