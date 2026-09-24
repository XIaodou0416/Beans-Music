import SwiftUI

struct CommentDialogSheet: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss
    let rootComment: Comment
    let focusReply: Comment
    @ObservedObject var store: VideoDetailCommentThreadRenderStore
    let reloadDialog: (Comment, Comment) async -> Void
    let actions: CommentDialogSheetActions
    let submitReply: (DynamicCommentComposerTarget, String, [DynamicCommentImage]?) async throws -> Void
    @State private var composerTarget: DynamicCommentComposerTarget?
    @State private var richCommentDrafts = [String: RichCommentDraft]()

    init(
        rootComment: Comment,
        focusReply: Comment,
        store: VideoDetailCommentThreadRenderStore,
        loadDialog: @escaping (Comment, Comment) async -> Void,
        reloadDialog: @escaping (Comment, Comment) async -> Void,
        submitReply: @escaping (
            DynamicCommentComposerTarget,
            String,
            [DynamicCommentImage]?
        ) async throws -> Void
    ) {
        self.rootComment = rootComment
        self.focusReply = focusReply
        self.store = store
        self.reloadDialog = reloadDialog
        self.submitReply = submitReply
        actions = CommentDialogSheetActionsBuilder(
            rootComment: rootComment,
            focusReply: focusReply,
            loadDialog: loadDialog
        )
        .actions
    }

    var body: some View {
        CommentOwnerProfileNavigationContainer {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        CommentReplyRootView(comment: rootComment)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                        Divider()

                        CommentDialogContent(
                            rootComment: rootComment,
                            focusReply: focusReply,
                            store: store,
                            reloadDialog: reloadDialog
                        )
                    }
                }
                .defersRemoteImageLoadsDuringFastScroll()
                .hiddenInlineNavigationTitle()
                .nativeTopScrollEdgeEffect()
                .commentSheetLoadLifecycle(load: actions.load)
                .onAppear {
                    scrollToFocusedReply(using: proxy)
                }
                .onChange(of: dialogReplyIDs) { _, _ in
                    scrollToFocusedReply(using: proxy)
                }
            }
        }
        .environment(\.videoCommentReplyComposerAction, replyComposerAction)
        .commentSheetPresentation(
            onDismiss: { dismiss() },
            onRefresh: { Task { await reloadDialog(rootComment, focusReply) } }
        )
        .background {
            RichCommentComposerPresenter(
                target: $composerTarget,
                draft: richCommentDraftBinding,
                api: dependencies.api,
                submit: { target, message, pictures in
                    try await submitReply(target, message, pictures)
                    await reloadDialog(rootComment, focusReply)
                }
            )
            .allowsHitTesting(false)
        }
    }

    private var dialogReplyIDs: [Int] {
        store.dialogSnapshot(for: rootComment, reply: focusReply).items.map(\.id)
    }

    private func openReplyComposer(for parent: Comment) {
        composerTarget = .reply(root: rootComment, parent: parent)
    }

    private var replyComposerAction: (Comment) -> Void {
        return { parent in openReplyComposer(for: parent) }
    }

    private func richCommentDraftBinding(for target: DynamicCommentComposerTarget) -> Binding<RichCommentDraft> {
        Binding(
            get: { richCommentDrafts[target.id] ?? RichCommentDraft(replyTarget: target) },
            set: { richCommentDrafts[target.id] = $0 }
        )
    }

    private func scrollToFocusedReply(using proxy: ScrollViewProxy) {
        guard dialogReplyIDs.contains(focusReply.id) else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(focusReply.id, anchor: .center)
        }
    }
}
