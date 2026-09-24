// Mount the upstream comment components without constructing a video player.
import SwiftUI

public struct CiliCiliAudioCommentsHost: View {
    private let bvid: String
    public init(bvid: String) { self.bvid = bvid }
    public var body: some View {
        AudioCommentsLoader(bvid: bvid).modifier(CiliCiliEnvironment())
    }
}

private struct AudioCommentsLoader: View {
    let bvid: String
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: VideoDetailViewModel?
    @State private var error: String?
    @State private var retry = 0

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    AudioCommentsContent(viewModel: viewModel)
                } else if let error {
                    ErrorStateView(title: "评论加载失败", message: error) { retry += 1 }
                } else {
                    ProgressView("正在加载评论")
                }
            }
            .navigationTitle("视频评论")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } } }
            .videoDestinations()
        }
        .task(id: "\(bvid)|\(retry)") {
            guard viewModel == nil else { return }
            error = nil
            do {
                let detail = try await dependencies.api.fetchVideoDetail(bvid: bvid)
                try Task.checkCancellation()
                let model = VideoDetailViewModel(
                    seedVideo: detail, api: dependencies.api, libraryStore: dependencies.libraryStore,
                    sessionStore: dependencies.sessionStore, sponsorBlockService: dependencies.sponsorBlockService
                )
                viewModel = model
                await model.loadInitialCommentsIfNeeded()
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct AudioCommentsContent: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var sheet: VideoDetailSheetRoute?
    @State private var composer: DynamicCommentComposerTarget?
    @State private var drafts: [String: RichCommentDraft] = [:]

    var body: some View {
        ScrollView {
            CommentsSectionView(
                store: viewModel.commentsRenderStore, style: .plain, maxVisibleComments: nil, autoLoads: false,
                actions: VideoDetailCommentsSectionActions(
                    beginInitialCommentsLoad: {}, selectCommentSort: viewModel.selectCommentSort,
                    retryComments: viewModel.retryComments, loadMoreComments: viewModel.loadMoreComments,
                    showReplies: { sheet = .commentThread(.init(rootComment: $0, secondaryID: nil)) },
                    replyToComment: { composer = .reply(root: $0, parent: $0) }, showAllComments: nil
                )
            )
        }
        .environment(\.commentContentOwnerMID, viewModel.detail.owner?.mid)
        .commentLikeTarget(oid: viewModel.commentTarget?.oid, type: viewModel.commentTarget?.type,
                           referer: "https://www.bilibili.com/video/\(viewModel.detail.bvid)")
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button("刷新评论", systemImage: "arrow.clockwise") { Task { await viewModel.retryComments() } }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button("发表评论", systemImage: "square.and.pencil") { composer = .dynamic }
            }
        }
        .videoDetailSheets(viewModel: viewModel, libraryStore: dependencies.libraryStore,
            sheetState: VideoDetailSheetState(
                route: $sheet, isShowingFavoriteFolders: .constant(false), isShowingCoinPicker: .constant(false),
                isShowingDanmakuSettings: .constant(false), isShowingNetworkDiagnostics: .constant(false)
            ), submitReply: submit
        )
        .background {
            RichCommentComposerPresenter(target: $composer, draft: draft, api: dependencies.api, submit: submit)
                .allowsHitTesting(false)
        }
    }

    private func draft(for target: DynamicCommentComposerTarget) -> Binding<RichCommentDraft> {
        Binding(get: { drafts[target.id] ?? RichCommentDraft(replyTarget: target) },
                set: { drafts[target.id] = $0 })
    }

    private func submit(_ target: DynamicCommentComposerTarget, _ message: String, _ pictures: [DynamicCommentImage]?) async throws {
        guard let commentTarget = viewModel.commentTarget else { throw BiliAPIError.missingPayload }
        try await dependencies.api.addDynamicComment(
            oid: commentTarget.oid, type: commentTarget.type, message: message,
            root: target.rootID, parent: target.parentID, pictures: pictures
        )
        await viewModel.retryComments()
    }
}
