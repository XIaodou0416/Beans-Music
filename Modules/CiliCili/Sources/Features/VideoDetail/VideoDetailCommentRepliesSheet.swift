import SwiftUI

struct CommentRepliesSheet: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss
    let rootComment: Comment
    @ObservedObject var store: VideoDetailCommentThreadRenderStore
    let initialReplyID: Int?
    let loadReplies: (Comment) async -> Void
    let reloadReplies: (Comment) async -> Void
    let loadMoreReplies: (Comment) async -> Void
    let loadDialog: (Comment, Comment) async -> Void
    let reloadDialog: (Comment, Comment) async -> Void
    let submitReply: (DynamicCommentComposerTarget, String, [DynamicCommentImage]?) async throws -> Void
    @State private var dialogReply: Comment?
    @State private var composerTarget: DynamicCommentComposerTarget?
    @State private var richCommentDrafts = [String: RichCommentDraft]()
    @State private var didPresentInitialReply = false

    init(
        rootComment: Comment,
        store: VideoDetailCommentThreadRenderStore,
        initialReplyID: Int? = nil,
        loadReplies: @escaping (Comment) async -> Void,
        reloadReplies: @escaping (Comment) async -> Void,
        loadMoreReplies: @escaping (Comment) async -> Void,
        loadDialog: @escaping (Comment, Comment) async -> Void,
        reloadDialog: @escaping (Comment, Comment) async -> Void,
        submitReply: @escaping (
            DynamicCommentComposerTarget,
            String,
            [DynamicCommentImage]?
        ) async throws -> Void
    ) {
        self.rootComment = rootComment
        self.store = store
        self.initialReplyID = initialReplyID
        self.loadReplies = loadReplies
        self.reloadReplies = reloadReplies
        self.loadMoreReplies = loadMoreReplies
        self.loadDialog = loadDialog
        self.reloadDialog = reloadDialog
        self.submitReply = submitReply
    }

    var body: some View {
        CommentOwnerProfileNavigationContainer {
            CommentRepliesSheetContentHost(
                rootComment: rootComment,
                store: store,
                reloadReplies: reloadReplies,
                loadMoreReplies: loadMoreReplies,
                showDialog: showDialog,
                loadReplies: loadReplies
            )
        }
        .environment(\.videoCommentReplyComposerAction, replyComposerAction)
        .commentSheetPresentation(
            onDismiss: { dismiss() },
            onRefresh: { Task { await reloadReplies(rootComment) } }
        )
        .sheet(item: $dialogReply) { reply in
            CommentDialogSheet(
                rootComment: rootComment,
                focusReply: reply,
                store: store,
                loadDialog: loadDialog,
                reloadDialog: reloadDialog,
                submitReply: submitReply
            )
        }
        .background {
            RichCommentComposerPresenter(
                target: $composerTarget,
                draft: richCommentDraftBinding,
                api: dependencies.api,
                submit: { target, message, pictures in
                    try await submitReply(target, message, pictures)
                    await reloadReplies(rootComment)
                }
            )
            .allowsHitTesting(false)
        }
        .onChange(of: replyIDs) { _, _ in
            presentInitialReplyIfAvailable()
        }
        .onAppear {
            presentInitialReplyIfAvailable()
        }
    }

    private func showDialog(_ reply: Comment) {
        dialogReply = reply
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

    private var replyIDs: [Int] {
        store.replies(for: rootComment).map(\.id)
    }

    private func presentInitialReplyIfAvailable() {
        guard !didPresentInitialReply,
              dialogReply == nil,
              let initialReplyID,
              let reply = store.replies(for: rootComment).first(where: { $0.id == initialReplyID })
        else {
            return
        }
        didPresentInitialReply = true
        dialogReply = reply
    }
}
