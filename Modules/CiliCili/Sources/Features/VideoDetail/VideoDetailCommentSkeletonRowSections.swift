import SwiftUI

struct CommentSkeletonHeaderLine: View {
    var body: some View {
        HStack(spacing: VideoDetailSkeletonStyle.commentLineSpacing) {
            CommentSkeletonLine(
                width: VideoDetailSkeletonStyle.commentNameWidth,
                height: VideoDetailSkeletonStyle.commentNameHeight
            )
            CommentSkeletonLine(
                width: VideoDetailSkeletonStyle.commentMetaWidth,
                height: VideoDetailSkeletonStyle.commentMetaHeight
            )
            Spacer(minLength: VideoDetailSkeletonStyle.commentLineSpacing)
            CommentSkeletonLine(
                width: VideoDetailSkeletonStyle.commentLikeWidth,
                height: VideoDetailSkeletonStyle.commentMetaHeight
            )
        }
    }
}

struct CommentSkeletonBodyLines: View {
    var body: some View {
        VStack(alignment: .leading, spacing: VideoDetailSkeletonStyle.commentLineSpacing) {
            CommentSkeletonLine(height: VideoDetailSkeletonStyle.commentBodyHeight)
            CommentSkeletonLine(
                width: VideoDetailSkeletonStyle.commentBodyShortWidth,
                height: VideoDetailSkeletonStyle.commentBodyHeight
            )
        }
    }
}

struct CommentSkeletonReplyLine: View {
    var body: some View {
        CommentSkeletonLine(
            width: VideoDetailSkeletonStyle.commentReplyWidth,
            height: VideoDetailSkeletonStyle.commentReplyHeight
        )
    }
}
