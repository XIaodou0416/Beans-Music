import SwiftUI

struct CommentsSkeletonContent: View {
    let rowCount: Int
    let horizontalPadding: CGFloat

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { _ in
                CommentSkeletonRow()
                    .padding(.horizontal, horizontalPadding)

                Divider()
                    .padding(.leading, 58)
            }
        }
        .accessibilityLabel("正在加载评论")
    }
}
