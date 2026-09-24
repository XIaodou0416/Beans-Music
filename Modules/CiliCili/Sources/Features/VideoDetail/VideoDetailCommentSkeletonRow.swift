import SwiftUI

struct CommentSkeletonRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: VideoDetailSkeletonStyle.commentRowSpacing) {
            Circle()
                .fill(VideoDetailTheme.secondarySurface)
                .frame(
                    width: VideoDetailSkeletonStyle.commentAvatarSize,
                    height: VideoDetailSkeletonStyle.commentAvatarSize
            )

            VStack(alignment: .leading, spacing: VideoDetailSkeletonStyle.commentLineSpacing) {
                CommentSkeletonHeaderLine()
                CommentSkeletonBodyLines()
                CommentSkeletonReplyLine()
            }
        }
        .padding(.vertical, VideoDetailSkeletonStyle.commentRowVerticalPadding)
    }
}
