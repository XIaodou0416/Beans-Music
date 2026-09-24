import SwiftUI

struct CommentDialogLoadingContent: View {
    var body: some View {
        CommentLoadingSkeletonList(count: 3)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
    }
}
