import SwiftUI

struct DynamicFeedCard: View {
    @Environment(\.dynamicDetailNavigationPath) private var detailNavigationPath
    @Environment(\.preloadedOriginalDynamicDetails) private var preloadedOriginalDynamicDetails
    let item: DynamicFeedItem
    let api: BiliAPIClient
    let contentWidth: CGFloat?
    let usesExternalHorizontalInsets: Bool
    let allowsDetailNavigation: Bool
    let allowsOriginalDetailNavigation: Bool
    let showsActionBar: Bool
    private let display: DynamicFeedCardDisplayModel
    @State private var commentsTarget: DynamicFeedItem?
    @State private var isTextExpanded: Bool

    init(
        item: DynamicFeedItem,
        api: BiliAPIClient,
        contentWidth: CGFloat? = nil,
        usesExternalHorizontalInsets: Bool? = nil,
        allowsDetailNavigation: Bool = true,
        allowsOriginalDetailNavigation: Bool = true,
        showsActionBar: Bool = true
    ) {
        self.item = item
        self.api = api
        self.contentWidth = contentWidth
        self.usesExternalHorizontalInsets = usesExternalHorizontalInsets ?? (contentWidth != nil)
        self.allowsDetailNavigation = allowsDetailNavigation
        self.allowsOriginalDetailNavigation = allowsOriginalDetailNavigation
        self.showsActionBar = showsActionBar
        let display = DynamicFeedCardDisplayModel(item: item)
        self.display = display
        _isTextExpanded = State(initialValue: !allowsDetailNavigation)
    }

    var body: some View {
        Group {
            if let video = display.video, display.usesHomeVideoCardStyle {
                DynamicHomeVideoFeedCard(
                    video: video,
                    display: display,
                    initialIsLiked: item.isLiked,
                    contentWidth: contentWidth,
                    usesExternalHorizontalInsets: usesExternalHorizontalInsets,
                    onShowComments: showComments
                )
            } else if display.usesSeparatedDynamicLayout {
                DynamicSeparatedFeedCardContent(
                    item: item,
                    display: display,
                    contentWidth: contentWidth,
                    usesExternalHorizontalInsets: usesExternalHorizontalInsets,
                    isTextExpanded: $isTextExpanded,
                    onShowComments: showComments,
                    onOpenDetail: openDetailAction,
                    onOpenOriginalDetail: openOriginalDetailAction,
                    showsActionBar: showsActionBar
                )
            } else {
                DynamicStandardFeedCardContent(
                    item: item,
                    display: display,
                    contentWidth: contentWidth,
                    usesExternalHorizontalInsets: usesExternalHorizontalInsets,
                    isTextExpanded: $isTextExpanded,
                    onShowComments: showComments,
                    onOpenDetail: openDetailAction,
                    onOpenOriginalDetail: openOriginalDetailAction,
                    showsActionBar: showsActionBar
                )
            }
        }
        .sheet(item: $commentsTarget) { target in
            DynamicCommentsSheet(item: target, api: api)
        }
    }

    private func showComments() {
        commentsTarget = item
    }

    private var openDetailAction: (() -> Void)? {
        guard allowsDetailNavigation,
              let detailNavigationPath,
              display.supportsDetailNavigation
        else { return nil }
        return { detailNavigationPath.wrappedValue.append(DynamicDetailTarget.loaded(item)) }
    }

    private var openOriginalDetailAction: ((DynamicOriginalItem) -> Void)? {
        guard allowsOriginalDetailNavigation,
              let detailNavigationPath
        else { return nil }

        return { original in
            guard original.visible != false,
                  original.hasDisplayableContent,
                  DynamicFeedCardDisplayModel.supportsDetailNavigation(original: original)
            else { return }
            if let preloadedItem = preloadedOriginalDynamicDetails[original.idStr] {
                detailNavigationPath.wrappedValue.append(DynamicDetailTarget.loaded(preloadedItem))
            } else {
                detailNavigationPath.wrappedValue.append(DynamicDetailTarget.remote(id: original.idStr))
            }
        }
    }
}

private struct DynamicDetailNavigationPathKey: EnvironmentKey {
    static let defaultValue: Binding<NavigationPath>? = nil
}

private struct PreloadedOriginalDynamicDetailsKey: EnvironmentKey {
    static let defaultValue = [String: DynamicFeedItem]()
}

private extension EnvironmentValues {
    var dynamicDetailNavigationPath: Binding<NavigationPath>? {
        get { self[DynamicDetailNavigationPathKey.self] }
        set { self[DynamicDetailNavigationPathKey.self] = newValue }
    }

    var preloadedOriginalDynamicDetails: [String: DynamicFeedItem] {
        get { self[PreloadedOriginalDynamicDetailsKey.self] }
        set { self[PreloadedOriginalDynamicDetailsKey.self] = newValue }
    }
}

extension View {
    func dynamicDetailDestinations(
        path: Binding<NavigationPath>,
        api: BiliAPIClient,
        preloadedOriginalDetails: [String: DynamicFeedItem] = [:]
    ) -> some View {
        navigationDestination(for: DynamicDetailTarget.self) { target in
            DynamicDetailDestination(
                target: target,
                api: api,
                navigationPath: path
            )
            .environment(\.preloadedOriginalDynamicDetails, preloadedOriginalDetails)
        }
        .environment(\.dynamicDetailNavigationPath, path)
        .environment(\.preloadedOriginalDynamicDetails, preloadedOriginalDetails)
    }
}

enum DynamicDetailTarget: Identifiable, Hashable {
    case loaded(DynamicFeedItem)
    case remote(id: String)

    var id: String {
        switch self {
        case .loaded(let item):
            return "loaded:\(item.idStr)"
        case .remote(let id):
            return "remote:\(id)"
        }
    }
}

private struct DynamicDetailDestination: View {
    let target: DynamicDetailTarget
    let api: BiliAPIClient
    let navigationPath: Binding<NavigationPath>
    @State private var remoteItem: DynamicFeedItem?
    @State private var loadedDetailItem: DynamicFeedItem?
    @State private var errorMessage: String?
    @State private var retryID = 0
    @State private var isNavigationTitleHidden = false

    var body: some View {
        Group {
            switch target {
            case .loaded(let item):
                DynamicDetailView(
                    item: loadedDetailItem ?? item,
                    api: api,
                    navigationPath: navigationPath,
                    isNavigationTitleHidden: $isNavigationTitleHidden
                )
                .task(id: item.idStr) {
                    await refreshLoadedDetail(id: item.idStr)
                }
            case .remote(let id):
                if let remoteItem {
                    DynamicDetailView(
                        item: remoteItem,
                        api: api,
                        navigationPath: navigationPath,
                        isNavigationTitleHidden: $isNavigationTitleHidden
                    )
                } else {
                    Group {
                        if let errorMessage {
                            ErrorStateView(title: "动态详情加载失败", message: errorMessage) {
                                retryID &+= 1
                            }
                            .padding(24)
                        } else {
                            ProgressView("正在加载动态详情")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .task(id: retryID) {
                        errorMessage = nil
                        do {
                            remoteItem = try await api.fetchDynamicDetail(id: id)
                        } catch is CancellationError {
                            return
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("动态详情")
                    .opacity(isNavigationTitleHidden ? 0 : 1)
                    .accessibilityHidden(isNavigationTitleHidden)
            }
        }
        .toolbarBackground(.automatic, for: .navigationBar)
    }

    private func refreshLoadedDetail(id: String) async {
        do {
            loadedDetailItem = try await api.fetchDynamicDetail(id: id)
        } catch is CancellationError {
            return
        } catch {
            // The feed item remains usable when a background state refresh fails.
        }
    }
}

private struct DynamicDetailView: View {
    let item: DynamicFeedItem
    let api: BiliAPIClient
    let navigationPath: Binding<NavigationPath>
    @Binding private var isNavigationTitleHidden: Bool
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var commentsViewModel: DynamicCommentsViewModel
    @State private var replySheetComment: Comment?
    @State private var richCommentComposerTarget: DynamicCommentComposerTarget?
    @State private var richCommentDrafts = [String: RichCommentDraft]()
    @State private var pullRefreshDistance: CGFloat = 0
    @State private var isPullRefreshing = false
    @State private var pullRefreshActions = HomeFeedRefreshActions()
    @State private var detailContentWidth: CGFloat?
    private let display: DynamicFeedCardDisplayModel

    init(
        item: DynamicFeedItem,
        api: BiliAPIClient,
        navigationPath: Binding<NavigationPath>,
        isNavigationTitleHidden: Binding<Bool>
    ) {
        self.item = item
        self.api = api
        self.navigationPath = navigationPath
        self._isNavigationTitleHidden = isNavigationTitleHidden
        self.display = DynamicFeedCardDisplayModel(item: item)
        _commentsViewModel = StateObject(wrappedValue: DynamicCommentsViewModel(item: item, api: api))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DynamicFeedCard(
                    item: item,
                    api: api,
                    contentWidth: detailContentWidth,
                    usesExternalHorizontalInsets: false,
                    allowsDetailNavigation: false,
                    showsActionBar: false
                )
                .environment(\.dynamicDetailNavigationPath, navigationPath)
                .padding(.top, 12)
                .padding(.bottom, 16)

                Divider()

                DynamicCommentsSheetContent(
                    viewModel: commentsViewModel,
                    highlightedCommentID: nil,
                    selectSort: selectCommentSort,
                    showReplies: { comment in
                        replySheetComment = comment
                    },
                    replyToComment: replyToCommentAction
                )
                .padding(.top, 10)
                .accessibilityIdentifier("dynamic.detail.inlineComments")
            }
        }
        .defersRemoteImageLoadsDuringFastScroll()
        .accessibilityIdentifier("dynamic.detail.scroll")
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onGeometryChange(for: CGFloat.self) { geometry in
            max(floor(geometry.size.width - 24), 0)
        } action: { _, width in
            guard width > 1 else { return }
            detailContentWidth = width
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 18
        } action: { _, isHidden in
            guard isNavigationTitleHidden != isHidden else { return }
            withAnimation(.smooth(duration: 0.18)) {
                isNavigationTitleHidden = isHidden
            }
        }
        .customPullRefreshTracking(
            isEnabled: libraryStore.usesCustomPullRefresh,
            onChange: handlePullRefreshChange
        )
        .nativePullRefresh(
            isEnabled: libraryStore.usesNativePullRefresh,
            action: refreshDetail
        )
        .homeFeedPullRefreshLayout(
            pullDistance: pullRefreshDistance,
            triggerDistance: CGFloat(libraryStore.homeRefreshTriggerDistance),
            isRefreshing: isPullRefreshing,
            isEnabled: libraryStore.usesCustomPullRefresh
        )
        .background(Color(.systemBackground))
        .toolbar {
            if richCommentComposerTarget == nil {
                DynamicDetailBottomInteractionBar(
                    display: display,
                    initialIsLiked: item.isLiked,
                    initialLikeCount: display.initialLikeCount,
                    commentCount: commentsViewModel.displayedReplyCount ?? 0,
                    canComment: commentsViewModel.canLoadComments,
                    openComment: {
                        richCommentComposerTarget = .dynamic
                    }
                )
            }
        }
        .toolbar(
            richCommentComposerTarget != nil
                ? .hidden
                : .automatic,
            for: .bottomBar
        )
        .background {
            RichCommentComposerPresenter(
                target: $richCommentComposerTarget,
                draft: richCommentDraftBinding,
                api: api,
                submit: { submissionTarget, message, pictures in
                    try await submitComment(submissionTarget, message, pictures: pictures)
                }
            )
            .allowsHitTesting(false)
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
        .task {
            commentsViewModel.setBlocksGoodsComments(libraryStore.blocksGoodsComments)
            await commentsViewModel.loadInitial()
        }
        .onChange(of: libraryStore.blocksGoodsComments) { _, isEnabled in
            commentsViewModel.setBlocksGoodsComments(isEnabled)
        }
        .sheet(item: $replySheetComment) { comment in
            DynamicCommentRepliesSheet(
                rootComment: comment,
                replyStore: commentsViewModel.replyStore,
                api: api,
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
    }

    private func selectCommentSort(_ sort: CommentSort) {
        Task { await commentsViewModel.selectSort(sort) }
    }

    private func handlePullRefreshChange(
        pullDistance: CGFloat,
        isUserInteracting: Bool
    ) {
        pullRefreshDistance = pullDistance
        guard libraryStore.usesCustomPullRefresh else { return }
        pullRefreshActions.handleConfiguredPullRefresh(
            pullDistance: pullDistance,
            triggerDistance: CGFloat(libraryStore.homeRefreshTriggerDistance),
            isUserInteracting: isUserInteracting,
            isRefreshing: isPullRefreshing
        ) {
            isPullRefreshing = true
            defer { isPullRefreshing = false }
            await commentsViewModel.reload()
            return commentsViewModel.state == .loaded
        }
    }

    private func refreshDetail() async {
        await commentsViewModel.reload()
    }

    private func submitComment(
        _ target: DynamicCommentComposerTarget,
        _ message: String,
        pictures: [DynamicCommentImage]? = nil
    ) async throws {
        guard let oid = item.commentOID, let type = item.commentType else {
            throw BiliAPIError.missingPayload
        }
        try await api.addDynamicComment(
            oid: oid,
            type: type,
            message: message,
            root: target.rootID,
            parent: target.parentID,
            pictures: pictures
        )
        commentsViewModel.registerSubmittedComment()
        await commentsViewModel.reload()
    }

    private var replyToCommentAction: (Comment) -> Void {
        { comment in
            let target = DynamicCommentComposerTarget.reply(root: comment, parent: comment)
            richCommentComposerTarget = target
        }
    }

    private var submitReplyAction: (DynamicCommentComposerTarget, String, [DynamicCommentImage]?) async throws -> Void {
        { target, message, pictures in
            try await submitComment(target, message, pictures: pictures)
        }
    }

    private func richCommentDraftBinding(for target: DynamicCommentComposerTarget) -> Binding<RichCommentDraft> {
        Binding(
            get: { richCommentDrafts[target.id] ?? RichCommentDraft(replyTarget: target) },
            set: { richCommentDrafts[target.id] = $0 }
        )
    }
}
