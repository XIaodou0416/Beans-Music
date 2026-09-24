import SwiftUI

struct CommentDialogEmptyContent: View {
    var body: some View {
        EmptyStateView(
            title: "暂无对话",
            systemImage: "text.bubble",
            message: "暂时没有找到这条回复的上下文。"
        )
        .padding(16)
    }
}
