import SwiftUI

struct DynamicCommentRepliesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let rootComment: Comment
    @ObservedObject var replyStore: DynamicCommentReplyStore
    let api: BiliAPIClient
    let submitReply: (DynamicCommentComposerTarget, String, [DynamicCommentImage]?) async throws -> Void
    @State private var dialogReply: Comment?
    @State private var composerTarget: DynamicCommentComposerTarget?
    @State private var richCommentDrafts = [String: RichCommentDraft]()

    var body: some View {
        CommentOwnerProfileNavigationContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DynamicCommentReplyRootView(
                        comment: rootComment,
                        reply: {
                            composerTarget = .reply(root: rootComment, parent: rootComment)
                        }
                    )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                    Divider()

                    DynamicCommentRepliesContent(
                        rootComment: rootComment,
                        replyStore: replyStore,
                        highlightedReplyID: nil,
                        showDialog: { reply in
                            dialogReply = reply
                        },
                        replyToComment: { reply in
                            composerTarget = .reply(root: rootComment, parent: reply)
                        }
                    )
                }
            }
            .defersRemoteImageLoadsDuringFastScroll()
            .hiddenInlineNavigationTitle()
            .nativeTopScrollEdgeEffect()
            .task {
                await replyStore.loadReplies(for: rootComment)
            }
        }
        .commentSheetPresentation(
            onDismiss: { dismiss() },
            onRefresh: { Task { await replyStore.reloadReplies(for: rootComment) } }
        )
        .sheet(item: $dialogReply) { reply in
            DynamicCommentDialogSheet(
                rootComment: rootComment,
                focusReply: reply,
                replyStore: replyStore,
                api: api,
                submitReply: submitReply
            )
        }
        .background {
            RichCommentComposerPresenter(
                target: $composerTarget,
                draft: richCommentDraftBinding,
                api: api,
                submit: { submissionTarget, message, pictures in
                    try await submitReply(submissionTarget, message, pictures)
                    await replyStore.reloadReplies(for: rootComment)
                }
            )
            .allowsHitTesting(false)
        }
    }

    private func richCommentDraftBinding(for target: DynamicCommentComposerTarget) -> Binding<RichCommentDraft> {
        Binding(
            get: { richCommentDrafts[target.id] ?? RichCommentDraft(replyTarget: target) },
            set: { richCommentDrafts[target.id] = $0 }
        )
    }
}

private struct DynamicCommentDialogSheet: View {
    @Environment(\.dismiss) private var dismiss
    let rootComment: Comment
    let focusReply: Comment
    let replyStore: DynamicCommentReplyStore
    let api: BiliAPIClient
    let submitReply: (DynamicCommentComposerTarget, String, [DynamicCommentImage]?) async throws -> Void
    @State private var composerTarget: DynamicCommentComposerTarget?
    @State private var richCommentDrafts = [String: RichCommentDraft]()

    var body: some View {
        CommentOwnerProfileNavigationContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DynamicCommentReplyRootView(
                        comment: rootComment,
                        reply: {
                            composerTarget = .reply(root: rootComment, parent: rootComment)
                        }
                    )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                    Divider()

                    DynamicCommentDialogContent(
                        rootComment: rootComment,
                        focusReply: focusReply,
                        replyToComment: { reply in
                            composerTarget = .reply(root: rootComment, parent: reply)
                        },
                        replyStore: replyStore
                    )
                }
            }
            .defersRemoteImageLoadsDuringFastScroll()
            .hiddenInlineNavigationTitle()
            .nativeTopScrollEdgeEffect()
            .task {
                await replyStore.loadDialog(for: rootComment, reply: focusReply)
            }
        }
        .commentSheetPresentation(
            onDismiss: { dismiss() },
            onRefresh: { Task { await replyStore.reloadDialog(for: rootComment, reply: focusReply) } }
        )
        .background {
            RichCommentComposerPresenter(
                target: $composerTarget,
                draft: richCommentDraftBinding,
                api: api,
                submit: { submissionTarget, message, pictures in
                    try await submitReply(submissionTarget, message, pictures)
                    await replyStore.reloadDialog(for: rootComment, reply: focusReply)
                }
            )
            .allowsHitTesting(false)
        }
    }

    private func richCommentDraftBinding(for target: DynamicCommentComposerTarget) -> Binding<RichCommentDraft> {
        Binding(
            get: { richCommentDrafts[target.id] ?? RichCommentDraft(replyTarget: target) },
            set: { richCommentDrafts[target.id] = $0 }
        )
    }
}
