import SwiftUI

struct AccountMessageCenterView: View {
    @ObservedObject var viewModel: AccountMessageCenterViewModel
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var showsDiagnostics = false

    var body: some View {
        List {
            if sessionStore.isLoggedIn {
                Section {
                    NavigationLink {
                        AccountPrivateMessageSessionsView(viewModel: viewModel)
                    } label: {
                        AccountMessageCategoryRow(
                            title: "私信",
                            systemImage: "bubble.left.and.bubble.right",
                            unreadText: viewModel.privateMessageUnreadBadgeText
                        )
                    }

                    NavigationLink {
                        AccountMessageInboxView(viewModel: viewModel)
                    } label: {
                        AccountMessageCategoryRow(
                            title: "全部通知",
                            systemImage: "tray.full",
                            unreadText: viewModel.unreadSummary.badgeText()
                        )
                    }

                    ForEach(AccountMessageCategory.allCases) { category in
                        NavigationLink {
                            AccountMessageFeedView(category: category, viewModel: viewModel)
                        } label: {
                            AccountMessageCategoryRow(
                                category: category,
                                unreadText: viewModel.unreadBadgeText(for: category)
                            )
                        }
                    }

                    NavigationLink {
                        AccountMessageFollowersView(viewModel: viewModel)
                    } label: {
                        AccountMessageCategoryRow(
                            title: "新增粉丝",
                            systemImage: "person.badge.plus",
                            unreadText: nil
                        )
                    }
                }
            } else {
                Section {
                    LibraryEmptyRow(title: "登录后可查看账号消息", systemImage: "person.crop.circle")
                }
            }
        }
        .navigationTitle("通知")
        .toolbarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
        .nativeTopScrollEdgeEffect()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.markAllNotificationsRead() }
                } label: {
                    if viewModel.isMarkingAllRead {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.circle")
                    }
                }
                .disabled(
                    !sessionStore.isLoggedIn
                        || viewModel.unreadSummary.total == 0
                        || viewModel.isMarkingAllRead
                )
                .accessibilityLabel("通知全部已读")

                Button {
                    Task { await viewModel.refreshUnread(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(!sessionStore.isLoggedIn || viewModel.unreadState.isLoading)
                .accessibilityLabel("刷新账号消息")

                Button {
                    showsDiagnostics = true
                } label: {
                    Image(systemName: "waveform.path.ecg")
                }
                .accessibilityLabel("账号消息诊断")
            }
        }
        .task(id: sessionStore.playbackCredentialVersion) {
            guard sessionStore.isLoggedIn else { return }
            await viewModel.refreshUnread()
        }
        .refreshable {
            await viewModel.refreshUnread(force: true)
        }
        .sheet(isPresented: $showsDiagnostics) {
            AccountMessageDiagnosticsView(store: viewModel.diagnosticsStore)
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { viewModel.actionErrorMessage != nil },
                set: { if !$0 { viewModel.clearActionError() } }
            )
        ) {
            Button("好") { viewModel.clearActionError() }
        } message: {
            Text(viewModel.actionErrorMessage ?? "请稍后重试")
        }
    }
}

private struct AccountMessageInboxView: View {
    @ObservedObject var viewModel: AccountMessageCenterViewModel
    @EnvironmentObject private var sessionStore: SessionStore

    @State private var filter: AccountMessageInboxFilter = .all
    @State private var searchText = ""
    @State private var pendingDeletion: AccountMessageItem?

    var body: some View {
        List {
            content
        }
        .hiddenInlineNavigationTitle()
        .nativeTopScrollEdgeEffect()
        .searchable(text: $searchText, prompt: "搜索已加载消息")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("筛选", selection: $filter) {
                        ForEach(AccountMessageInboxFilter.allCases) { option in
                            Label(option.title, systemImage: option.systemImage)
                                .tag(option)
                        }
                    }
                } label: {
                    Image(systemName: filter == .all ? "line.3.horizontal.decrease.circle" : filter.systemImage)
                }
                .accessibilityLabel("筛选：\(filter.title)")
            }
        }
        .task {
            await viewModel.loadAllIfNeeded()
        }
        .refreshable {
            await viewModel.refreshAll()
        }
        .confirmationDialog(
            "删除这条通知？",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingDeletion {
                Button("删除", role: .destructive) {
                    self.pendingDeletion = nil
                    Task { await viewModel.delete(pendingDeletion) }
                }
            }
            Button("取消", role: .cancel) {
                pendingDeletion = nil
            }
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { viewModel.actionErrorMessage != nil },
                set: { if !$0 { viewModel.clearActionError() } }
            )
        ) {
            Button("好") { viewModel.clearActionError() }
        } message: {
            Text(viewModel.actionErrorMessage ?? "请稍后重试")
        }
    }

    @ViewBuilder
    private var content: some View {
        if !sessionStore.isLoggedIn {
            Section {
                LibraryEmptyRow(title: "登录后可查看账号消息", systemImage: "person.crop.circle")
            }
        } else {
            ForEach(viewModel.loadedFeedErrorMessages, id: \.self) { message in
                Section {
                    LibraryErrorRow(title: "部分消息加载失败", message: message) {
                        Task { await viewModel.refreshAll() }
                    }
                }
            }

            if filteredItems.isEmpty {
                Section {
                    if viewModel.isLoadingAllFeeds {
                        LibraryLoadingRow(title: "正在加载通知")
                    } else {
                        LibraryEmptyRow(
                            title: searchText.isEmpty ? "没有符合筛选的通知" : "没有找到相关通知",
                            systemImage: searchText.isEmpty ? filter.systemImage : "magnifyingglass"
                        )
                    }
                }
            } else {
                let newItems = filteredItems.filter(viewModel.isNew)
                let earlierItems = filteredItems.filter { !viewModel.isNew($0) }

                if !newItems.isEmpty {
                    Section("新消息") {
                        messageRows(newItems)
                    }
                }
                if !earlierItems.isEmpty {
                    Section(newItems.isEmpty ? "消息" : "更早") {
                        messageRows(earlierItems)
                    }
                }
            }

            ForEach(viewModel.loadMoreErrorsForInbox(filter: filter), id: \.self) { message in
                Section {
                    LibraryErrorRow(title: "加载更多失败", message: message) {
                        Task { await viewModel.loadMoreForInbox(filter: filter) }
                    }
                }
            }

            if viewModel.isLoadingMoreForInbox(filter: filter) {
                Section {
                    LibraryLoadingRow(title: "正在加载更多通知")
                }
            } else if viewModel.hasMoreForInbox(filter: filter) {
                Section {
                    LibraryLoadMoreTriggerRow(title: "加载更多") {
                        Task { await viewModel.loadMoreForInbox(filter: filter) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageRows(_ items: [AccountMessageItem]) -> some View {
        ForEach(items) { item in
            AccountMessageFeedRow(item: item, viewModel: viewModel)
                .contextMenu {
                    if item.category == .like, item.serverID != nil {
                        Button {
                            Task { await viewModel.toggleLikeNotification(item) }
                        } label: {
                            Label(
                                item.isLikeNotificationMuted ? "接收点赞提醒" : "停止点赞提醒",
                                systemImage: item.isLikeNotificationMuted ? "bell" : "bell.slash"
                            )
                        }
                    }
                    if item.canDelete {
                        Button(role: .destructive) {
                            pendingDeletion = item
                        } label: {
                            Label("删除通知", systemImage: "trash")
                        }
                    }
                }
        }
    }

    private var filteredItems: [AccountMessageItem] {
        viewModel.filteredItems(filter: filter, searchText: searchText)
    }
}

struct AccountMessageFeedView: View {
    let category: AccountMessageCategory
    @ObservedObject var viewModel: AccountMessageCenterViewModel
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var pendingDeletion: AccountMessageItem?

    var body: some View {
        List {
            content
        }
        .hiddenInlineNavigationTitle()
        .nativeTopScrollEdgeEffect()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.refresh(category) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(!sessionStore.isLoggedIn || feed.state.isLoading)
                .accessibilityLabel("刷新\(category.title)")
            }
        }
        .task {
            await viewModel.loadIfNeeded(category)
        }
        .refreshable {
            await viewModel.refresh(category)
        }
        .confirmationDialog(
            "删除这条通知？",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingDeletion {
                Button("删除", role: .destructive) {
                    self.pendingDeletion = nil
                    Task { await viewModel.delete(pendingDeletion) }
                }
            }
            Button("取消", role: .cancel) {
                pendingDeletion = nil
            }
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { viewModel.actionErrorMessage != nil },
                set: { if !$0 { viewModel.clearActionError() } }
            )
        ) {
            Button("好") { viewModel.clearActionError() }
        } message: {
            Text(viewModel.actionErrorMessage ?? "请稍后重试")
        }
    }

    @ViewBuilder
    private var content: some View {
        if !sessionStore.isLoggedIn {
            Section {
                LibraryEmptyRow(title: "登录后可查看账号消息", systemImage: "person.crop.circle")
            }
        } else if feed.items.isEmpty {
            switch feed.state {
            case .loading:
                Section {
                    LibraryLoadingRow(title: "正在加载\(category.title)")
                }
            case .failed(let message):
                Section {
                    LibraryErrorRow(title: "加载\(category.title)失败", message: message) {
                        Task { await viewModel.refresh(category) }
                    }
                }
            case .idle, .loaded:
                Section {
                    LibraryEmptyRow(title: category.emptyTitle, systemImage: category.systemImage)
                }
            }
        } else {
            if case .failed(let message) = feed.state {
                Section {
                    LibraryErrorRow(title: "刷新失败", message: message) {
                        Task { await viewModel.refresh(category) }
                    }
                }
            }
            standardContent
            feedFooter
        }
    }

    @ViewBuilder
    private var standardContent: some View {
        let newItems = feed.items.filter(viewModel.isNew)
        let earlierItems = feed.items.filter { !viewModel.isNew($0) }

        if !newItems.isEmpty {
            Section("新消息") {
                messageRows(newItems)
            }
        }
        if !earlierItems.isEmpty {
            if newItems.isEmpty {
                Section {
                    messageRows(earlierItems)
                }
            } else {
                Section("更早") {
                    messageRows(earlierItems)
                }
            }
        }
    }

    @ViewBuilder
    private var feedFooter: some View {
        if feed.loadMoreState.isLoading {
            Section {
                LibraryLoadingRow(title: "正在加载更多")
            }
        } else if case .failed(let message) = feed.loadMoreState {
            Section {
                LibraryErrorRow(title: "加载更多失败", message: message) {
                    Task { await viewModel.loadMore(category) }
                }
            }
        } else if feed.hasMore {
            Section {
                LibraryLoadMoreTriggerRow(title: "加载更多") {
                    Task { await viewModel.loadMore(category) }
                }
            }
        }
    }

    @ViewBuilder
    private func messageRows(_ items: [AccountMessageItem]) -> some View {
        ForEach(items) { item in
            AccountMessageFeedRow(item: item, viewModel: viewModel)
                .contextMenu {
                    if item.category == .like, item.serverID != nil {
                        Button {
                            Task { await viewModel.toggleLikeNotification(item) }
                        } label: {
                            Label(
                                item.isLikeNotificationMuted ? "接收点赞提醒" : "停止点赞提醒",
                                systemImage: item.isLikeNotificationMuted ? "bell" : "bell.slash"
                            )
                        }
                    }
                    if item.canDelete {
                        Button(role: .destructive) {
                            pendingDeletion = item
                        } label: {
                            Label("删除通知", systemImage: "trash")
                        }
                    }
                }
                .task {
                    await viewModel.loadMoreIfNeeded(category, current: item)
                }
        }
    }

    private var feed: AccountMessageFeedState {
        viewModel.feedState(for: category)
    }
}

private struct AccountMessageCategoryRow: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let title: String
    let systemImage: String
    let unreadText: String?

    init(category: AccountMessageCategory, unreadText: String?) {
        self.title = category.title
        self.systemImage = category.systemImage
        self.unreadText = unreadText
    }

    init(title: String, systemImage: String, unreadText: String?) {
        self.title = title
        self.systemImage = systemImage
        self.unreadText = unreadText
    }

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(appTintColor)
                .frame(width: 28, height: 28)

            Text(title)
                .appTypography(.messageName, fallback: .subheadline.weight(.medium))

            Spacer(minLength: 8)

            if let unreadText {
                Text(unreadText)
                    .appTypography(.badge, fallback: .caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(.red, in: Capsule())
                    .accessibilityLabel("\(unreadText) 条未读")
            }
        }
        .padding(.vertical, 3)
    }
}

private struct AccountMessageFeedRow: View {
    let item: AccountMessageItem
    @ObservedObject var viewModel: AccountMessageCenterViewModel
    @Environment(\.appThemeTintColor) private var appTintColor

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AccountMessageAvatar(item: item)
            destination
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var destination: some View {
        if item.canShowLikeDetail {
            NavigationLink {
                AccountMessageLikeDetailView(item: item, viewModel: viewModel)
            } label: {
                messageContent
            }
            .buttonStyle(.plain)
        } else if item.routeURL != nil || item.commentTarget != nil {
            AccountMessageRouteButton(item: item, viewModel: viewModel) {
                messageContent
            }
        } else {
            messageContent
        }
    }

    private var messageContent: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .appTypography(.messageName, fallback: .subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                messageBody

                ForEach(Array(item.contextLines.enumerated()), id: \.offset) { _, context in
                    BiliEmoteText(
                        content: nil,
                        plainText: "| \(context)",
                        inlineEmotes: viewModel.inlineEmotes,
                        font: .caption,
                        textColor: .secondary,
                        emoteSize: 17,
                        showsLinkButtons: false,
                        typographyRole: .metadata
                    )
                        .lineLimit(1)
                }

                if let displayTime = item.displayTime {
                    Text(displayTime)
                        .appTypography(.tertiaryMetadata, fallback: .caption2)
                        .foregroundStyle(.secondary)
                }

                if hasInlineBodyLinks, item.routeURL != nil {
                    Label("查看详情", systemImage: "arrow.up.right.square")
                        .appTypography(.action, fallback: .caption.weight(.medium))
                        .foregroundStyle(appTintColor)
                }
            }

            Spacer(minLength: 2)

            if let coverURLString = item.coverURLString {
                AccountMessageCover(urlString: coverURLString)
            } else if viewModel.isMutating(item) {
                ProgressView()
                    .controlSize(.small)
            } else if item.isLikeNotificationMuted {
                Image(systemName: "bell.slash.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var messageBody: some View {
        BiliEmoteText(
            content: nil,
            plainText: item.body,
            inlineEmotes: viewModel.inlineEmotes,
            font: .subheadline,
            textColor: .primary,
            emoteSize: 21,
            showsLinkButtons: false,
            typographyRole: .messagePreview
        )
        .lineLimit(5)
    }

    private var hasInlineBodyLinks: Bool {
        item.category == .system && AccountMessageRichTextParser.containsLink(in: item.body)
    }
}

private enum AccountMessageRoutePresentation: Identifiable {
    case comment(AccountMessageCommentTarget)
    case unavailable(AccountMessageUnavailableTarget)

    var id: String {
        switch self {
        case .comment(let target):
            return "comment-\(target.id)"
        case .unavailable(let target):
            return "unavailable-\(target.id)"
        }
    }
}

private struct AccountMessageRouteButton<Label: View>: View {
    let item: AccountMessageItem
    @ObservedObject var viewModel: AccountMessageCenterViewModel
    @ViewBuilder let label: () -> Label

    @Environment(\.openAppURLAction) private var openAppURL
    @Environment(\.openURL) private var openURL
    @State private var isResolving = false
    @State private var presentation: AccountMessageRoutePresentation?

    var body: some View {
        Button {
            resolve()
        } label: {
            label()
                .overlay(alignment: .topTrailing) {
                    if isResolving {
                        ProgressView()
                            .controlSize(.small)
                            .padding(4)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isResolving)
        .sheet(item: $presentation) { presentation in
            switch presentation {
            case .comment(let target):
                AccountMessageCommentThreadSheet(target: target, viewModel: viewModel)
            case .unavailable(let target):
                AccountMessageUnavailableView(target: target)
            }
        }
    }

    private func resolve() {
        guard !isResolving else { return }
        isResolving = true
        Task {
            let resolution = await viewModel.resolveRoute(for: item)
            guard !Task.isCancelled else { return }
            isResolving = false
            switch resolution {
            case .open(let url):
                if let openAppURL {
                    openAppURL(url)
                } else {
                    openURL(url)
                }
            case .comment(let target):
                presentation = .comment(target)
            case .unavailable(let target):
                presentation = .unavailable(target)
            }
        }
    }
}

private struct AccountMessageCommentThreadSheet: View {
    let target: AccountMessageCommentTarget
    @ObservedObject var viewModel: AccountMessageCenterViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var state: LoadingState = .idle
    @State private var thread: AccountMessageCommentThread?

    var body: some View {
        NavigationStack {
            content
                .environment(\.openVideoOwnerRouteAction, nil)
                .environment(\.openVideoAction, nil)
                .environment(\.openLiveRoomAction, nil)
                .environment(\.openPgcSeasonRouteAction, nil)
                .videoDestinations()
                .hiddenInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("关闭") { dismiss() }
                    }
                    if let originalURL = target.originalURL {
                        ToolbarItem(placement: .topBarTrailing) {
                            AppLinkButton(url: originalURL) {
                                Image(systemName: "arrow.up.right.square")
                            }
                            .accessibilityLabel("查看\(target.contentTitle)")
                        }
                    }
                }
        }
        .task(id: target.id) {
            await load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let thread {
            loadedContent(thread)
        } else {
            switch state {
            case .loading:
                ProgressView("正在定位评论")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("评论暂时不可见", systemImage: "text.bubble.fill")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") {
                        Task { await load() }
                    }
                    if let originalURL = target.originalURL {
                        AppLinkButton(url: originalURL) {
                            Text("查看\(target.contentTitle)")
                        }
                    }
                }
            case .idle, .loaded:
                ContentUnavailableView("没有找到评论", systemImage: "text.bubble")
            }
        }
    }

    private func loadedContent(_ thread: AccountMessageCommentThread) -> some View {
        let replyItems = VideoDetailCommentReplyDisplayItems.make(
            replies: thread.replies,
            rootComment: thread.root
        )
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if thread.requestedReplyWasUnavailable {
                        Label("目标回复不可见，已显示所在评论串", systemImage: "exclamationmark.bubble")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    CommentReplyRootView(comment: thread.root)
                        .id(thread.root.id)

                    Divider()

                    ForEach(replyItems) { item in
                        CommentReplyDetailRow(item: item, showDialog: nil)
                            .id(item.id)
                            .padding(.horizontal, 8)
                            .background(
                                item.id == thread.focusedReplyID
                                    ? Color.accentColor.opacity(0.10)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                    }
                }
                .padding(16)
            }
            .task(id: thread.focusedReplyID) {
                guard let focusedReplyID = thread.focusedReplyID else { return }
                await Task.yield()
                proxy.scrollTo(focusedReplyID, anchor: .center)
            }
        }
    }

    private func load() async {
        guard !state.isLoading else { return }
        state = .loading
        do {
            let value = try await viewModel.fetchCommentThread(for: target)
            guard !Task.isCancelled else { return }
            thread = value
            state = .loaded
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct AccountMessageUnavailableView: View {
    let target: AccountMessageUnavailableTarget

    @Environment(\.dismiss) private var dismiss
    @State private var browserItem: InAppBrowserItem?

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(target.title, systemImage: "exclamationmark.triangle")
            } description: {
                Text(target.message)
            } actions: {
                if let originalURL = target.originalURL {
                    Button("在网页中尝试打开") {
                        browserItem = InAppBrowserItem(url: originalURL)
                    }
                }
            }
            .hiddenInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .sheet(item: $browserItem) { item in
            InAppBrowserView(url: item.url)
                .ignoresSafeArea()
        }
    }
}

private struct AccountMessageAvatar: View {
    let item: AccountMessageItem
    @Environment(\.openVideoOwnerRouteAction) private var openVideoOwnerRoute

    var body: some View {
        if let owner = item.primaryOwner {
            if let openVideoOwnerRoute {
                Button {
                    openVideoOwnerRoute(owner)
                } label: {
                    avatar
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开\(owner.name)的主页")
            } else {
                NavigationLink(value: owner) {
                    avatar
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开\(owner.name)的主页")
            }
        } else {
            avatar
        }
    }

    private var avatar: some View {
        AvatarRemoteImage(urlString: item.avatarURLString, pixelSize: 112) {
            Image(systemName: item.category.systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }
}

private struct AccountMessageLikeDetailView: View {
    let item: AccountMessageItem
    @ObservedObject var viewModel: AccountMessageCenterViewModel

    @State private var entries: [AccountMessageLikeDetailItem] = []
    @State private var state: LoadingState = .idle
    @State private var loadMoreState: LoadingState = .idle
    @State private var cardTitle: String?
    @State private var page = 1
    @State private var lastMID: Int?
    @State private var hasMore = true

    var body: some View {
        List {
            if let routeURL = item.routeURL {
                Section {
                    AppLinkButton(url: routeURL) {
                        Label(cardTitle ?? item.contextLines.first ?? "查看被点赞的内容", systemImage: "arrow.up.right.square")
                            .lineLimit(2)
                    }
                }
            }

            if entries.isEmpty {
                emptyContent
            } else {
                if case .failed(let message) = state {
                    Section {
                        LibraryErrorRow(title: "刷新失败", message: message) {
                            Task { await load(reset: true) }
                        }
                    }
                }
                Section("点赞用户") {
                    ForEach(entries) { entry in
                        AccountMessageLikeDetailActorRow(entry: entry)
                            .task {
                                guard entry.id == entries.last?.id else { return }
                                await loadMore()
                            }
                    }
                }
                detailFooter
            }
        }
        .hiddenInlineNavigationTitle()
        .nativeTopScrollEdgeEffect()
        .task {
            guard state == .idle else { return }
            await load(reset: true)
        }
        .refreshable {
            await load(reset: true)
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        switch state {
        case .loading:
            Section {
                LibraryLoadingRow(title: "正在加载点赞详情")
            }
        case .failed(let message):
            Section {
                LibraryErrorRow(title: "加载点赞详情失败", message: message) {
                    Task { await load(reset: true) }
                }
            }
        case .idle, .loaded:
            Section {
                LibraryEmptyRow(title: "暂无点赞用户", systemImage: "heart")
            }
        }
    }

    @ViewBuilder
    private var detailFooter: some View {
        if loadMoreState.isLoading {
            Section {
                LibraryLoadingRow(title: "正在加载更多")
            }
        } else if case .failed(let message) = loadMoreState {
            Section {
                LibraryErrorRow(title: "加载更多失败", message: message) {
                    Task { await loadMore() }
                }
            }
        }
    }

    private func loadMore() async {
        guard hasMore else { return }
        await load(reset: false)
    }

    private func load(reset: Bool) async {
        guard !state.isLoading, !loadMoreState.isLoading else { return }
        if reset {
            state = .loading
        } else {
            loadMoreState = .loading
        }

        let requestedPage = reset ? 1 : page
        let requestedLastMID = reset ? nil : lastMID
        do {
            let result = try await viewModel.fetchLikeDetail(
                for: item,
                page: requestedPage,
                lastMID: requestedLastMID
            )
            guard !Task.isCancelled else { return }

            if reset {
                entries = result.items
            } else {
                var seen = Set(entries.map(\.id))
                entries.append(contentsOf: result.items.filter { seen.insert($0.id).inserted })
            }
            cardTitle = result.title ?? cardTitle
            page = requestedPage + 1
            lastMID = result.nextLastMID
            hasMore = result.hasMore
                && !result.items.isEmpty
                && (requestedLastMID == nil || result.nextLastMID != requestedLastMID)
            state = .loaded
            loadMoreState = .idle
        } catch is CancellationError {
            return
        } catch {
            if reset {
                state = .failed(error.localizedDescription)
            } else {
                loadMoreState = .failed(error.localizedDescription)
            }
        }
    }
}

private struct AccountMessageLikeDetailActorRow: View {
    let entry: AccountMessageLikeDetailItem

    var body: some View {
        if let owner = entry.actor.owner {
            VideoOwnerRouteLink(owner: owner) {
                content
            }
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            AvatarRemoteImage(urlString: entry.actor.avatarURLString, pixelSize: 112) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 42, height: 42)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.actor.name)
                    .appTypography(.author, fallback: .subheadline.weight(.medium))
                if let displayTime = entry.displayTime {
                    Text(displayTime)
                        .appTypography(.metadata, fallback: .caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AccountMessageFollowersView: View {
    @ObservedObject var viewModel: AccountMessageCenterViewModel

    @State private var followers: [AccountMessageFollower] = []
    @State private var state: LoadingState = .idle
    @State private var loadMoreState: LoadingState = .idle
    @State private var page = 1
    @State private var total: Int?
    @State private var hasMore = true

    var body: some View {
        List {
            if followers.isEmpty {
                emptyContent
            } else {
                if case .failed(let message) = state {
                    Section {
                        LibraryErrorRow(title: "刷新失败", message: message) {
                            Task { await load(reset: true) }
                        }
                    }
                }

                Section {
                    ForEach(followers) { follower in
                        AccountMessageFollowerRow(
                            follower: follower,
                            inlineEmotes: viewModel.inlineEmotes
                        )
                            .task {
                                guard follower.id == followers.last?.id else { return }
                                await loadMore()
                            }
                    }
                } header: {
                    if let total {
                        Text("共 \(total) 人")
                    }
                }

                if loadMoreState.isLoading {
                    Section {
                        LibraryLoadingRow(title: "正在加载更多粉丝")
                    }
                } else if case .failed(let message) = loadMoreState {
                    Section {
                        LibraryErrorRow(title: "加载更多失败", message: message) {
                            Task { await loadMore() }
                        }
                    }
                }
            }
        }
        .hiddenInlineNavigationTitle()
        .nativeTopScrollEdgeEffect()
        .task {
            guard state == .idle else { return }
            await load(reset: true)
        }
        .refreshable {
            await load(reset: true)
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        switch state {
        case .loading:
            Section {
                LibraryLoadingRow(title: "正在加载新增粉丝")
            }
        case .failed(let message):
            Section {
                LibraryErrorRow(title: "加载新增粉丝失败", message: message) {
                    Task { await load(reset: true) }
                }
            }
        case .idle, .loaded:
            Section {
                LibraryEmptyRow(title: "暂时没有粉丝", systemImage: "person.2")
            }
        }
    }

    private func loadMore() async {
        guard hasMore else { return }
        await load(reset: false)
    }

    private func load(reset: Bool) async {
        guard !state.isLoading, !loadMoreState.isLoading else { return }
        if reset {
            state = .loading
        } else {
            loadMoreState = .loading
        }

        let requestedPage = reset ? 1 : page
        do {
            let result = try await viewModel.fetchFollowers(page: requestedPage)
            guard !Task.isCancelled else { return }

            if reset {
                followers = result.items
            } else {
                var seen = Set(followers.map(\.id))
                followers.append(contentsOf: result.items.filter { seen.insert($0.id).inserted })
            }
            page = requestedPage + 1
            total = result.total
            hasMore = result.hasMore && !result.items.isEmpty
            state = .loaded
            loadMoreState = .idle
        } catch is CancellationError {
            return
        } catch {
            if reset {
                state = .failed(error.localizedDescription)
            } else {
                loadMoreState = .failed(error.localizedDescription)
            }
        }
    }
}

private struct AccountMessageFollowerRow: View {
    let follower: AccountMessageFollower
    let inlineEmotes: [String: BiliInlineEmote]

    var body: some View {
        if let owner = follower.actor.owner {
            VideoOwnerRouteLink(owner: owner) {
                content
            }
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            AvatarRemoteImage(urlString: follower.actor.avatarURLString, pixelSize: 112) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(follower.actor.name)
                    .appTypography(.author, fallback: .subheadline.weight(.medium))

                if let sign = follower.sign {
                    BiliEmoteText(
                        content: nil,
                        plainText: sign,
                        inlineEmotes: inlineEmotes,
                        font: .caption,
                        textColor: .secondary,
                        emoteSize: 17,
                        showsLinkButtons: false,
                        typographyRole: .metadata
                    )
                        .lineLimit(1)
                }

                if let displayTime = follower.displayTime {
                    Text(displayTime)
                        .appTypography(.tertiaryMetadata, fallback: .caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AccountMessageCover: View {
    let urlString: String

    var body: some View {
        CachedRemoteImage(
            url: URL(string: urlString.biliCoverThumbnailURL(width: 192, height: 120)),
            fallbackURL: URL(string: urlString),
            targetPixelSize: 192
        ) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Color.gray.opacity(0.14)
        }
        .frame(width: 64, height: 42)
        .videoCoverSurface(cornerRadius: 6, shadowLevel: .subtle)
    }
}
