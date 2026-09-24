import SwiftUI

struct VideoDetailViewContentResolver: View {
    @EnvironmentObject private var dependencies: AppDependencies
    let seedVideo: VideoItem
    @ObservedObject var runtimeSettings: VideoDetailRuntimeSettingsStore
    @ObservedObject var viewModel: VideoDetailViewModel
    @Binding var selectedContentTab: VideoDetailContentTab
    @Binding var sheetRoute: VideoDetailSheetRoute?
    @Binding var pendingCommentAnchor: VideoCommentAnchor?
    @Binding var isShowingDanmakuSettings: Bool
    @Binding var isShowingFavoriteFolders: Bool
    @Binding var isShowingCoinPicker: Bool
    @Binding var isShowingNetworkDiagnostics: Bool
    let onNavigateBack: () -> Void
    @State private var commentComposerTarget: DynamicCommentComposerTarget?
    @State private var commentComposerDrafts = [String: RichCommentDraft]()

    var body: some View {
        VideoDetailShellRepresentable(
            seedVideo: seedVideo,
            viewModel: viewModel,
            runtimeSettings: runtimeSettings,
            selectedContentTab: $selectedContentTab,
            sheetRoute: $sheetRoute,
            isShowingDanmakuSettings: $isShowingDanmakuSettings,
            isShowingFavoriteFolders: $isShowingFavoriteFolders,
            isShowingCoinPicker: $isShowingCoinPicker,
            isShowingNetworkDiagnostics: $isShowingNetworkDiagnostics,
            onOpenCommentComposer: openCommentComposer(for:),
            onNavigateBack: onNavigateBack
        )
        .ignoresSafeArea()
        .videoDetailSheets(
            viewModel: viewModel,
            libraryStore: dependencies.libraryStore,
            sheetState: VideoDetailSheetState(
                route: $sheetRoute,
                isShowingFavoriteFolders: $isShowingFavoriteFolders,
                isShowingCoinPicker: $isShowingCoinPicker,
                isShowingDanmakuSettings: $isShowingDanmakuSettings,
                isShowingNetworkDiagnostics: $isShowingNetworkDiagnostics
            ),
            submitReply: videoCommentSubmitAction
        )
        .background {
            RichCommentComposerPresenter(
                target: $commentComposerTarget,
                draft: commentComposerDraftBinding,
                api: dependencies.api,
                submit: { target, message, pictures in
                    try await submitComment(target: target, message: message, pictures: pictures)
                }
            )
            .allowsHitTesting(false)
        }
        .task(id: commentAnchorTaskID) {
            await presentPendingCommentIfPossible()
        }
    }

    private func openCommentComposer(for comment: Comment?) {
        guard viewModel.commentTarget != nil else { return }
        commentComposerTarget = comment.map { .reply(root: $0, parent: $0) } ?? .dynamic
    }

    private var videoCommentSubmitAction: (
        DynamicCommentComposerTarget,
        String,
        [DynamicCommentImage]?
    ) async throws -> Void {
        { target, message, pictures in
            try await submitComment(target: target, message: message, pictures: pictures)
        }
    }

    private func commentComposerDraftBinding(
        for target: DynamicCommentComposerTarget
    ) -> Binding<RichCommentDraft> {
        Binding(
            get: { commentComposerDrafts[target.id] ?? RichCommentDraft(replyTarget: target) },
            set: { commentComposerDrafts[target.id] = $0 }
        )
    }

    private func submitComment(
        target composerTarget: DynamicCommentComposerTarget,
        message: String,
        pictures: [DynamicCommentImage]?
    ) async throws {
        guard let target = viewModel.commentTarget else { throw BiliAPIError.missingPayload }
        try await dependencies.api.addDynamicComment(
            oid: target.oid,
            type: target.type,
            message: message,
            root: composerTarget.rootID,
            parent: composerTarget.parentID,
            pictures: pictures
        )
        await viewModel.retryComments()
    }

    private var commentAnchorTaskID: String {
        guard let pendingCommentAnchor else { return "none" }
        return [
            String(pendingCommentAnchor.rootID),
            pendingCommentAnchor.secondaryID.map(String.init) ?? "-",
            viewModel.commentTarget?.contextKey ?? "pending-detail"
        ].joined(separator: "|")
    }

    @MainActor
    private func presentPendingCommentIfPossible() async {
        guard let pendingCommentAnchor,
              viewModel.commentTarget != nil
        else {
            return
        }

        let anchor = pendingCommentAnchor
        let loadedThread = await viewModel.loadCommentRoot(for: anchor)
        guard !Task.isCancelled,
              self.pendingCommentAnchor == anchor
        else {
            return
        }

        self.pendingCommentAnchor = nil
        selectedContentTab = .comments
        guard let loadedThread else { return }
        sheetRoute = .commentThread(
            VideoDetailCommentThreadSheetPresentation(
                rootComment: loadedThread.rootComment,
                secondaryID: loadedThread.focusedReplyID
            )
        )
    }
}

struct VideoDetailInitialContentResolver: View {
    let seedVideo: VideoItem
    @Binding var selectedContentTab: VideoDetailContentTab
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot
    let onNavigateBack: () -> Void
    let lifecycleActions: VideoDetailViewContentLifecycleActions

    var body: some View {
        VideoDetailInitialContent(
            seedVideo: seedVideo,
            selectedContentTab: $selectedContentTab,
            runtimeSettings: runtimeSettings,
            onNavigateBack: onNavigateBack
        )
        .task {
            lifecycleActions.configureInitialViewModelIfNeeded()
        }
    }
}
