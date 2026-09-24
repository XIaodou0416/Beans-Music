import SwiftUI

struct CommentSkeletonLine: View {
    let width: CGFloat?
    let height: CGFloat

    init(width: CGFloat? = nil, height: CGFloat) {
        self.width = width
        self.height = height
    }

    var body: some View {
        RoundedRectangle(cornerRadius: VideoDetailSkeletonStyle.commentLineCornerRadius, style: .continuous)
            .fill(VideoDetailTheme.secondarySurface)
            .frame(width: width, height: height)
    }
}
