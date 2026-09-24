import SwiftUI

typealias DynamicCommentAvatar = CommentAvatar
typealias DynamicCommentMetricBadge = CommentMetricBadge

struct DynamicCommentImageGrid: View {
    let images: [DynamicImageItem]

    var body: some View {
        if images.isEmpty {
            EmptyView()
        } else {
            CompactDynamicImageMosaicGrid(
                images: images,
                accessibilityName: "评论图片",
                placeholderFill: Color(.secondarySystemGroupedBackground)
            )
            .dynamicCommentHitArea(.control)
        }
    }
}
