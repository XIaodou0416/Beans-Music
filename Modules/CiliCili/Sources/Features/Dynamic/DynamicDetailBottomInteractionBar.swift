import SwiftUI

struct DynamicDetailBottomInteractionBar: ToolbarContent {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.appThemeTintColor) private var appTintColor

    let display: DynamicFeedCardDisplayModel
    let initialIsLiked: Bool
    let initialLikeCount: Int
    let commentCount: Int
    let canComment: Bool
    let openComment: () -> Void

    @State private var likeState: DynamicLikeDisplayState
    @State private var isMutatingLike = false
    @State private var errorMessage: String?

    init(
        display: DynamicFeedCardDisplayModel,
        initialIsLiked: Bool,
        initialLikeCount: Int,
        commentCount: Int,
        canComment: Bool,
        openComment: @escaping () -> Void
    ) {
        self.display = display
        self.initialIsLiked = initialIsLiked
        self.initialLikeCount = initialLikeCount
        self.commentCount = commentCount
        self.canComment = canComment
        self.openComment = openComment
        _likeState = State(initialValue: DynamicLikeDisplayState(
            isLiked: initialIsLiked,
            likeCount: initialLikeCount
        ))
    }

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            likeButton
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            commentButton
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            shareButton
        }
    }

    private var likeButton: some View {
        Button(action: toggleLike) {
            Image(systemName: likeState.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                .font(.body)
        }
        .controlSize(.small)
        .imageScale(.medium)
        .foregroundStyle(likeState.isLiked ? appTintColor : .primary)
        .disabled(isMutatingLike)
        .accessibilityLabel(likeState.isLiked ? "取消点赞" : "点赞")
        .accessibilityValue("\(likeState.isLiked ? "已点赞" : "未点赞")，\(likeState.likeCount) 个赞")
        .accessibilityAddTraits(likeState.isLiked ? .isSelected : [])
        .accessibilityIdentifier("dynamic.detail.composer.like")
        .dynamicCommentHitArea(.control)
        .onChange(of: sourceLikeState) { _, state in
            guard !isMutatingLike else { return }
            likeState = state
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "请稍后重试")
        }
    }

    private var commentButton: some View {
        Button(action: openComment) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "bubble.left")
                    .font(.body)
                Text("点击发送电波")
                    .font(.body)
            }
            .padding(.horizontal, 6)
        }
        .controlSize(.small)
        .imageScale(.medium)
        .foregroundStyle(.primary)
        .buttonBorderShape(.capsule)
        .accessibilityLabel("评论")
        .accessibilityValue("共 \(commentCount) 条")
        .accessibilityIdentifier("dynamic.detail.composer.comment")
        .disabled(!canComment)
        .dynamicCommentHitArea(.control)
    }

    private var shareButton: some View {
        ShareLink(item: dynamicShareURL) {
            Image(systemName: "square.and.arrow.up")
                .font(.body)
        }
        .controlSize(.small)
        .imageScale(.medium)
        .foregroundStyle(.primary)
        .accessibilityLabel("分享动态")
        .accessibilityIdentifier("dynamic.detail.composer.share")
        .dynamicCommentHitArea(.control)
    }

    private var dynamicShareURL: URL {
        URL(string: "https://t.bilibili.com/\(display.dynamicID)")!
    }

    private var sourceLikeState: DynamicLikeDisplayState {
        DynamicLikeDisplayState(isLiked: initialIsLiked, likeCount: initialLikeCount)
    }

    private func toggleLike() {
        let account = sessionStore.credentialSnapshot(
            for: .interaction,
            multiAccountEnabled: libraryStore.multiAccountExperimentEnabled
        )
        guard account.isLoggedIn, !isMutatingLike else {
            errorMessage = account.isLoggedIn ? nil : "请先登录账号"
            return
        }

        let previousState = likeState
        let targetState = previousState.toggled()
        isMutatingLike = true
        likeState = targetState
        Task { @MainActor in
            do {
                try await dependencies.api.setDynamicLike(
                    dynamicID: display.dynamicID,
                    liked: targetState.isLiked
                )
                Haptics.success()
            } catch {
                likeState = previousState
                errorMessage = error.localizedDescription
            }
            isMutatingLike = false
        }
    }
}
