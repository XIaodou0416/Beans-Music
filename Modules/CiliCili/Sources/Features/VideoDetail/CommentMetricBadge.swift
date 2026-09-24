import SwiftUI

nonisolated struct CommentLikeDisplayState: Equatable, Sendable {
    let isLiked: Bool
    let likeCount: Int

    func toggled() -> Self {
        Self(
            isLiked: !isLiked,
            likeCount: max(0, likeCount + (isLiked ? -1 : 1))
        )
    }
}

struct CommentLikeTarget: Equatable, Sendable {
    let oid: String
    let type: Int
    let referer: String

    init?(oid: String?, type: Int?, referer: String) {
        guard let oid = oid?.trimmingCharacters(in: .whitespacesAndNewlines),
              !oid.isEmpty,
              let type,
              type > 0
        else {
            return nil
        }
        self.oid = oid
        self.type = type
        self.referer = referer
    }
}

private struct CommentLikeTargetKey: EnvironmentKey {
    static let defaultValue: CommentLikeTarget? = nil
}

extension EnvironmentValues {
    var commentLikeTarget: CommentLikeTarget? {
        get { self[CommentLikeTargetKey.self] }
        set { self[CommentLikeTargetKey.self] = newValue }
    }
}

extension View {
    func commentLikeTarget(oid: String?, type: Int?, referer: String) -> some View {
        environment(
            \.commentLikeTarget,
            CommentLikeTarget(oid: oid, type: type, referer: referer)
        )
    }
}

struct CommentMetricBadge: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let text: String
    let systemImage: String
    let isHighlighted: Bool

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .foregroundStyle(isHighlighted ? appTintColor : .secondary)
            .frame(height: 24)
    }
}

struct CommentLikeButton: View {
    @Environment(\.commentLikeTarget) private var target
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore

    let comment: Comment

    @State private var displayState: CommentLikeDisplayState
    @State private var isMutating = false
    @State private var errorMessage: String?

    init(comment: Comment) {
        self.comment = comment
        _displayState = State(initialValue: Self.state(for: comment))
    }

    var body: some View {
        Group {
            if target != nil {
                Button(action: toggleLike) {
                    badge
                }
                .buttonStyle(.plain)
                .disabled(isMutating)
                .accessibilityLabel(displayState.isLiked ? "取消点赞评论" : "点赞评论")
                .accessibilityValue("\(displayState.likeCount) 个赞")
            } else {
                badge
            }
        }
        .onChange(of: sourceState) { _, newValue in
            guard !isMutating else { return }
            displayState = newValue
        }
        .alert("评论点赞", isPresented: showsError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "操作失败")
        }
        .dynamicCommentHitArea(.control)
    }

    private var badge: some View {
        CommentMetricBadge(
            text: BiliFormatters.compactCount(displayState.likeCount),
            systemImage: displayState.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
            isHighlighted: displayState.isLiked
        )
        .contentShape(Rectangle())
    }

    private var sourceState: CommentLikeDisplayState {
        Self.state(for: comment)
    }

    private var showsError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func toggleLike() {
        guard !isMutating, let target else { return }
        let account = dependencies.sessionStore.credentialSnapshot(
            for: .interaction,
            multiAccountEnabled: libraryStore.multiAccountExperimentEnabled
        )
        guard account.isLoggedIn else {
            errorMessage = "请先登录互动账号"
            return
        }

        Haptics.light()
        let previousState = displayState
        let targetState = previousState.toggled()
        isMutating = true
        withAnimation(.snappy(duration: 0.2)) {
            displayState = targetState
        }

        Task { @MainActor in
            do {
                try await dependencies.api.setCommentLike(
                    oid: target.oid,
                    type: target.type,
                    rpid: comment.rpid,
                    liked: targetState.isLiked,
                    referer: target.referer
                )
                Haptics.success()
            } catch {
                withAnimation(.snappy(duration: 0.2)) {
                    displayState = previousState
                }
                errorMessage = "操作失败：\(error.localizedDescription)"
            }
            isMutating = false
        }
    }

    private static func state(for comment: Comment) -> CommentLikeDisplayState {
        CommentLikeDisplayState(
            isLiked: comment.likeState == 1,
            likeCount: max(0, comment.like ?? 0)
        )
    }
}
