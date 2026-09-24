import SwiftUI

struct DynamicCommentsSheet: View {
    let item: DynamicFeedItem
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: DynamicCommentsViewModel
    @StateObject private var runtimeSettings = DynamicCommentsRuntimeSettingsStore()
    @State private var replySheetComment: Comment?
    @State private var composerTarget: DynamicCommentComposerTarget?
    @State private var richCommentDrafts = [String: RichCommentDraft]()

    init(item: DynamicFeedItem, api: BiliAPIClient) {
        self.item = item
        _viewModel = StateObject(wrappedValue: DynamicCommentsViewModel(item: item, api: api))
    }

    var body: some View {
        CommentOwnerProfileNavigationContainer {
            ScrollView {
                DynamicCommentsSheetContent(
                    viewModel: viewModel,
                    highlightedCommentID: nil,
                    selectSort: selectCommentSort,
                    showReplies: { comment in
                        replySheetComment = comment
                    },
                    dividerHorizontalPadding: 0,
                    replyToComment: { comment in
                        composerTarget = .reply(root: comment, parent: comment)
                    }
                )
            }
            .defersRemoteImageLoadsDuringFastScroll()
            .accessibilityIdentifier("dynamic.comments.scroll")
            .hiddenInlineNavigationTitle()
            .nativeTopScrollEdgeEffect()
            .task {
                runtimeSettings.bind(dependencies.libraryStore)
                viewModel.setBlocksGoodsComments(runtimeSettings.blocksGoodsComments)
                await viewModel.loadInitial()
            }
        }
        .environment(
            \.dynamicCommentHitAreaVisualizationEnabled,
            libraryStore.dynamicCommentHitAreaVisualizationExperimentEnabled
        )
        .environment(\.commentContentOwnerMID, item.author?.mid)
        .commentLikeTarget(
            oid: item.commentOID,
            type: item.commentType,
            referer: "https://t.bilibili.com/\(item.idStr)"
        )
        .onChange(of: runtimeSettings.blocksGoodsComments) { _, isEnabled in
            viewModel.setBlocksGoodsComments(isEnabled)
        }
        .commentSheetPresentation(
            onDismiss: { dismiss() },
            onRefresh: { Task { await viewModel.reload() } }
        )
        .sheet(item: $replySheetComment) { comment in
            DynamicCommentRepliesSheet(
                rootComment: comment,
                replyStore: viewModel.replyStore,
                api: dependencies.api,
                submitReply: submitReplyAction
            )
                .environment(
                    \.dynamicCommentHitAreaVisualizationEnabled,
                    libraryStore.dynamicCommentHitAreaVisualizationExperimentEnabled
                )
                .environment(\.commentContentOwnerMID, item.author?.mid)
                .commentLikeTarget(
                    oid: item.commentOID,
                    type: item.commentType,
                    referer: "https://t.bilibili.com/\(item.idStr)"
                )
        }
        .background {
            RichCommentComposerPresenter(
                target: $composerTarget,
                draft: richCommentDraftBinding,
                api: dependencies.api,
                submit: submitReplyAction
            )
            .allowsHitTesting(false)
        }
    }

    private func selectCommentSort(_ sort: CommentSort) {
        Task { await viewModel.selectSort(sort) }
    }

    private func richCommentDraftBinding(for target: DynamicCommentComposerTarget) -> Binding<RichCommentDraft> {
        Binding(
            get: { richCommentDrafts[target.id] ?? RichCommentDraft(replyTarget: target) },
            set: { richCommentDrafts[target.id] = $0 }
        )
    }

    private var submitReplyAction: (DynamicCommentComposerTarget, String, [DynamicCommentImage]?) async throws -> Void {
        { target, message, pictures in
            guard let oid = item.commentOID, let type = item.commentType else {
                throw BiliAPIError.missingPayload
            }
            try await dependencies.api.addDynamicComment(
                oid: oid,
                type: type,
                message: message,
                root: target.rootID,
                parent: target.parentID,
                pictures: pictures
            )
            await viewModel.reload()
        }
    }
}
