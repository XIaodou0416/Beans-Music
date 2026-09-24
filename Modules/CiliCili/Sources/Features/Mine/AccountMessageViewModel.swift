import Combine
import Foundation

nonisolated struct AccountMessageFeedState: Equatable {
    var state: LoadingState = .idle
    var loadMoreState: LoadingState = .idle
    var items: [AccountMessageItem] = []
    var cursor: AccountMessageCursor?
    var hasMore = false
    var lastViewAt: Date?
    var newItemIDs = Set<String>()
}

@MainActor
final class AccountMessageCenterViewModel: ObservableObject {
    @Published private(set) var unreadSummary = AccountMessageUnreadSummary.empty
    @Published private(set) var privateMessageUnreadCount = 0
    @Published private(set) var inlineEmotes = [String: BiliInlineEmote]()
    @Published private(set) var unreadState: LoadingState = .idle
    @Published private(set) var feeds: [AccountMessageCategory: AccountMessageFeedState]
    @Published private(set) var mutatingItemIDs = Set<String>()
    @Published private(set) var actionErrorMessage: String?
    @Published private(set) var isMarkingAllRead = false

    private let service: AccountMessageService
    private let sessionStore: SessionStore
    let diagnosticsStore: AccountMessageDiagnosticsStore
    private var sessionCancellable: AnyCancellable?
    private var privateUnreadTask: Task<Void, Never>?
    private var inlineEmoteTask: Task<Void, Never>?
    private var hasLoadedInlineEmotes = false
    private var lastUnreadRefreshAt: Date?
    private var privateMessageUnreadGeneration = 0
    private let unreadRefreshInterval: TimeInterval = 45

    init(
        service: AccountMessageService,
        sessionStore: SessionStore,
        diagnosticsStore: AccountMessageDiagnosticsStore? = nil
    ) {
        self.service = service
        self.sessionStore = sessionStore
        self.diagnosticsStore = diagnosticsStore ?? .shared
        self.feeds = Self.emptyFeedStates
        sessionCancellable = sessionStore.$playbackCredentialVersion
            .dropFirst()
            .sink { [weak self] _ in
                self?.resetForSessionChange()
            }
    }

    var totalUnreadBadgeText: String? {
        Self.badgeText(unreadSummary.total + privateMessageUnreadCount)
    }

    var hasUnreadMessages: Bool {
        unreadSummary.total + privateMessageUnreadCount > 0
    }

    var privateMessageUnreadBadgeText: String? {
        Self.badgeText(privateMessageUnreadCount)
    }

    func unreadBadgeText(for category: AccountMessageCategory) -> String? {
        unreadSummary.badgeText(for: category)
    }

    func feedState(for category: AccountMessageCategory) -> AccountMessageFeedState {
        feeds[category] ?? AccountMessageFeedState()
    }

    func refreshUnread(force: Bool = false) async {
        guard sessionStore.isLoggedIn else {
            resetForSessionChange()
            return
        }
        guard !unreadState.isLoading else { return }
        if !force,
           let lastUnreadRefreshAt,
           Date().timeIntervalSince(lastUnreadRefreshAt) < unreadRefreshInterval {
            return
        }

        let credentialVersion = sessionStore.playbackCredentialVersion
        unreadState = .loading
        refreshPrivateMessageUnread(credentialVersion: credentialVersion)
        loadInlineEmotesIfNeeded(credentialVersion: credentialVersion)
        do {
            let summary = try await service.fetchUnreadSummary()
            guard isCurrentSession(credentialVersion) else { return }
            unreadSummary = summary
            unreadState = .loaded
            lastUnreadRefreshAt = Date()
        } catch {
            guard isCurrentSession(credentialVersion) else { return }
            unreadState = .failed(error.localizedDescription)
        }
    }

    func loadIfNeeded(_ category: AccountMessageCategory) async {
        let feed = feedState(for: category)
        guard feed.items.isEmpty, !feed.state.isLoading else { return }
        await refresh(category)
    }

    func refresh(_ category: AccountMessageCategory) async {
        guard sessionStore.isLoggedIn else {
            resetForSessionChange()
            return
        }
        guard !feedState(for: category).state.isLoading else { return }

        let credentialVersion = sessionStore.playbackCredentialVersion
        let unreadCountBeforeLoad = unreadSummary.count(for: category)
        var feed = feedState(for: category)
        feed.state = .loading
        feed.loadMoreState = .idle
        setFeed(feed, for: category)

        do {
            let page = try await service.fetchPage(category: category)
            guard isCurrentSession(credentialVersion) else { return }
            feed.items = Self.uniqued(page.items)
            feed.cursor = page.nextCursor
            feed.hasMore = page.hasMore && page.nextCursor?.canLoadMore == true
            feed.lastViewAt = page.lastViewAt
            feed.newItemIDs = Self.newItemIDs(
                in: feed.items,
                unreadCount: unreadCountBeforeLoad,
                lastViewAt: page.lastViewAt
            )
            feed.state = .loaded
            feed.loadMoreState = .idle
            setFeed(feed, for: category)
            unreadSummary = unreadSummary.markingRead(category)
        } catch {
            guard isCurrentSession(credentialVersion) else { return }
            feed.state = .failed(error.localizedDescription)
            setFeed(feed, for: category)
        }
    }

    func loadMoreIfNeeded(_ category: AccountMessageCategory, current item: AccountMessageItem) async {
        guard feedState(for: category).items.last?.id == item.id else { return }
        await loadMore(category)
    }

    func loadMore(_ category: AccountMessageCategory) async {
        guard sessionStore.isLoggedIn else {
            resetForSessionChange()
            return
        }

        let currentFeed = feedState(for: category)
        guard currentFeed.hasMore,
              let cursor = currentFeed.cursor,
              cursor.canLoadMore,
              !currentFeed.state.isLoading,
              !currentFeed.loadMoreState.isLoading
        else {
            return
        }

        let credentialVersion = sessionStore.playbackCredentialVersion
        var feed = currentFeed
        feed.loadMoreState = .loading
        setFeed(feed, for: category)

        do {
            let page = try await service.fetchPage(category: category, cursor: cursor)
            guard isCurrentSession(credentialVersion) else { return }
            let previousCount = feed.items.count
            feed.items = Self.appendingUnique(page.items, to: feed.items)
            let cursorAdvanced = page.nextCursor != cursor
            feed.cursor = page.nextCursor
            feed.hasMore = page.hasMore && cursorAdvanced && feed.items.count > previousCount
            feed.loadMoreState = .idle
            setFeed(feed, for: category)
        } catch {
            guard isCurrentSession(credentialVersion) else { return }
            feed.loadMoreState = .failed(error.localizedDescription)
            setFeed(feed, for: category)
        }
    }

    func resetForSessionChange() {
        privateUnreadTask?.cancel()
        privateUnreadTask = nil
        inlineEmoteTask?.cancel()
        inlineEmoteTask = nil
        unreadSummary = .empty
        replacePrivateMessageUnreadCount(0)
        inlineEmotes = [:]
        hasLoadedInlineEmotes = false
        unreadState = .idle
        feeds = Self.emptyFeedStates
        mutatingItemIDs = []
        actionErrorMessage = nil
        isMarkingAllRead = false
        lastUnreadRefreshAt = nil
        diagnosticsStore.reset()
    }

    func delete(_ item: AccountMessageItem) async {
        guard !mutatingItemIDs.contains(item.id) else { return }
        mutatingItemIDs.insert(item.id)
        defer { mutatingItemIDs.remove(item.id) }

        do {
            try await service.delete(item)
            var feed = feedState(for: item.category)
            feed.items.removeAll { $0.id == item.id }
            setFeed(feed, for: item.category)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    func toggleLikeNotification(_ item: AccountMessageItem) async {
        guard item.category == .like, !mutatingItemIDs.contains(item.id) else { return }
        mutatingItemIDs.insert(item.id)
        defer { mutatingItemIDs.remove(item.id) }

        let muted = !item.isLikeNotificationMuted
        do {
            try await service.setLikeNotificationMuted(muted, for: item)
            var feed = feedState(for: .like)
            guard let index = feed.items.firstIndex(where: { $0.id == item.id }) else { return }
            feed.items[index].noticeState = muted ? 1 : 0
            setFeed(feed, for: .like)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    func fetchLikeDetail(
        for item: AccountMessageItem,
        page: Int,
        lastMID: Int?
    ) async throws -> AccountMessageLikeDetailPage {
        guard item.category == .like, let serverID = item.serverID else {
            throw BiliAPIError.api(code: -1, message: "这条点赞通知没有详情")
        }
        return try await service.fetchLikeDetail(cardID: serverID, page: page, lastMID: lastMID)
    }

    func fetchFollowers(page: Int, pageSize: Int = 20) async throws -> AccountMessageFollowerPage {
        try await service.fetchFollowers(page: page, pageSize: pageSize)
    }

    func fetchPrivateMessageSessions() async throws -> [AccountPrivateMessageSession] {
        let sessions = try await service.fetchPrivateMessageSessions()
        replacePrivateMessageUnreadCount(sessions.reduce(into: 0) { partialResult, session in
            partialResult += max(0, session.unreadCount)
        })
        return sessions
    }

    func fetchPrivateMessages(
        talkerID: Int,
        endSequence: Int? = nil,
        pageSize: Int = 20
    ) async throws -> AccountPrivateMessagePage {
        try await service.fetchPrivateMessages(
            talkerID: talkerID,
            endSequence: endSequence,
            pageSize: pageSize
        )
    }

    func sendPrivateTextMessage(talkerID: Int, text: String) async throws {
        try await service.sendPrivateTextMessage(talkerID: talkerID, text: text)
    }

    func sendPrivateImageMessage(talkerID: Int, imageData: Data) async throws {
        try await service.sendPrivateImageMessage(talkerID: talkerID, imageData: imageData)
    }

    func withdrawPrivateMessage(talkerID: Int, messageKey: Int) async throws {
        try await service.withdrawPrivateMessage(talkerID: talkerID, messageKey: messageKey)
    }

    func reportPrivateMessage(
        accusedUserID: Int,
        messageKey: Int,
        reasonType: Int,
        reasonDescription: String
    ) async throws {
        try await service.reportPrivateMessage(
            accusedUserID: accusedUserID,
            messageKey: messageKey,
            reasonType: reasonType,
            reasonDescription: reasonDescription
        )
    }

    func setPrivateMessageSessionPinned(talkerID: Int, pinned: Bool) async throws {
        try await service.setPrivateMessageSessionPinned(talkerID: talkerID, pinned: pinned)
    }

    func setPrivateMessageSessionMuted(talkerID: Int, muted: Bool) async throws {
        try await service.setPrivateMessageSessionMuted(talkerID: talkerID, muted: muted)
    }

    func removePrivateMessageSession(talkerID: Int) async throws {
        try await service.removePrivateMessageSession(talkerID: talkerID)
    }

    func resolveRoute(for item: AccountMessageItem) async -> AccountMessageRouteResolution {
        await service.resolveRoute(for: item)
    }

    func fetchCommentThread(for target: AccountMessageCommentTarget) async throws -> AccountMessageCommentThread {
        try await service.fetchCommentThread(for: target)
    }

    func loadAllIfNeeded() async {
        async let reply: Void = loadIfNeeded(.reply)
        async let mention: Void = loadIfNeeded(.mention)
        async let like: Void = loadIfNeeded(.like)
        async let system: Void = loadIfNeeded(.system)
        _ = await (reply, mention, like, system)
    }

    func refreshAll() async {
        async let reply: Void = refresh(.reply)
        async let mention: Void = refresh(.mention)
        async let like: Void = refresh(.like)
        async let system: Void = refresh(.system)
        _ = await (reply, mention, like, system)
    }

    func loadMoreForInbox(filter: AccountMessageInboxFilter) async {
        if let category = filter.category {
            await loadMore(category)
            return
        }

        async let reply: Void = loadMore(.reply)
        async let mention: Void = loadMore(.mention)
        async let like: Void = loadMore(.like)
        async let system: Void = loadMore(.system)
        _ = await (reply, mention, like, system)
    }

    func hasMoreForInbox(filter: AccountMessageInboxFilter) -> Bool {
        inboxCategories(for: filter).contains { feedState(for: $0).hasMore }
    }

    func isLoadingMoreForInbox(filter: AccountMessageInboxFilter) -> Bool {
        inboxCategories(for: filter).contains { feedState(for: $0).loadMoreState.isLoading }
    }

    func loadMoreErrorsForInbox(filter: AccountMessageInboxFilter) -> [String] {
        inboxCategories(for: filter).compactMap { category in
            guard case .failed(let message) = feedState(for: category).loadMoreState else { return nil }
            return "\(category.title)：\(message)"
        }
    }

    func markAllNotificationsRead() async {
        guard sessionStore.isLoggedIn, !isMarkingAllRead else { return }
        isMarkingAllRead = true
        defer { isMarkingAllRead = false }

        do {
            try await service.markAllNotificationsRead()
            unreadSummary = .empty
            for category in AccountMessageCategory.allCases {
                var feed = feedState(for: category)
                feed.newItemIDs = []
                setFeed(feed, for: category)
            }
            lastUnreadRefreshAt = Date()
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    func filteredItems(
        filter: AccountMessageInboxFilter,
        searchText: String
    ) -> [AccountMessageItem] {
        let normalizedQuery = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        return AccountMessageCategory.allCases
            .flatMap { feedState(for: $0).items }
            .filter { item in
                if filter == .unread, !isNew(item) {
                    return false
                }
                if let category = filter.category, item.category != category {
                    return false
                }
                return normalizedQuery.isEmpty || item.searchableText.contains(normalizedQuery)
            }
            .sorted {
                ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast)
            }
    }

    func isNew(_ item: AccountMessageItem) -> Bool {
        feedState(for: item.category).newItemIDs.contains(item.id)
    }

    var isLoadingAllFeeds: Bool {
        AccountMessageCategory.allCases.contains {
            feedState(for: $0).state.isLoading
        }
    }

    var loadedFeedErrorMessages: [String] {
        AccountMessageCategory.allCases.compactMap { category in
            guard case .failed(let message) = feedState(for: category).state else { return nil }
            return "\(category.title)：\(message)"
        }
    }

    func markPrivateMessageSessionRead(
        talkerID: Int,
        ackSequence: Int,
        unreadCount: Int
    ) async throws {
        let credentialVersion = sessionStore.playbackCredentialVersion
        try await service.markPrivateMessageSessionRead(
            talkerID: talkerID,
            ackSequence: ackSequence
        )
        guard isCurrentSession(credentialVersion) else { return }
        replacePrivateMessageUnreadCount(
            max(0, privateMessageUnreadCount - max(0, unreadCount))
        )
    }

    func privateMessageDraft(talkerID: Int) -> String {
        guard talkerID > 0 else { return "" }
        return UserDefaults.standard.string(forKey: privateMessageDraftKey(talkerID: talkerID)) ?? ""
    }

    func savePrivateMessageDraft(_ draft: String, talkerID: Int) {
        guard talkerID > 0 else { return }
        let key = privateMessageDraftKey(talkerID: talkerID)
        if draft.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(draft, forKey: key)
        }
    }

    func isMutating(_ item: AccountMessageItem) -> Bool {
        mutatingItemIDs.contains(item.id)
    }

    func clearActionError() {
        actionErrorMessage = nil
    }

    nonisolated static func appendingUnique(
        _ newItems: [AccountMessageItem],
        to existingItems: [AccountMessageItem]
    ) -> [AccountMessageItem] {
        var seen = Set(existingItems.map(\.id))
        var result = existingItems
        for item in newItems where seen.insert(item.id).inserted {
            result.append(item)
        }
        return result
    }

    private static let emptyFeedStates = Dictionary(
        uniqueKeysWithValues: AccountMessageCategory.allCases.map { ($0, AccountMessageFeedState()) }
    )

    private static func uniqued(_ items: [AccountMessageItem]) -> [AccountMessageItem] {
        appendingUnique(items, to: [])
    }

    private static func newItemIDs(
        in items: [AccountMessageItem],
        unreadCount: Int,
        lastViewAt: Date?
    ) -> Set<String> {
        if unreadCount > 0 {
            return Set(items.prefix(unreadCount).map(\.id))
        }
        if let lastViewAt {
            return Set(items.filter { ($0.timestamp ?? .distantPast) > lastViewAt }.map(\.id))
        }
        return Set(items.filter(\.isLatest).map(\.id))
    }

    private func setFeed(_ feed: AccountMessageFeedState, for category: AccountMessageCategory) {
        feeds[category] = feed
    }

    private func refreshPrivateMessageUnread(credentialVersion: Int) {
        privateUnreadTask?.cancel()
        let unreadGeneration = privateMessageUnreadGeneration
        privateUnreadTask = Task { [weak self] in
            guard let self,
                  let count = try? await service.fetchPrivateMessageUnreadCount(),
                  !Task.isCancelled,
                  isCurrentSession(credentialVersion),
                  privateMessageUnreadGeneration == unreadGeneration
            else {
                return
            }
            privateMessageUnreadCount = count
        }
    }

    private func replacePrivateMessageUnreadCount(_ count: Int) {
        privateMessageUnreadGeneration &+= 1
        privateMessageUnreadCount = max(0, count)
    }

    private func loadInlineEmotesIfNeeded(credentialVersion: Int) {
        guard !hasLoadedInlineEmotes, inlineEmoteTask == nil else { return }
        inlineEmoteTask = Task { [weak self] in
            guard let self else { return }
            defer { inlineEmoteTask = nil }
            guard let emotes = try? await service.fetchAccountMessageInlineEmotes(),
                  !Task.isCancelled,
                  isCurrentSession(credentialVersion)
            else {
                return
            }
            inlineEmotes = emotes
            hasLoadedInlineEmotes = true
        }
    }

    private static func badgeText(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > 99 ? "99+" : String(count)
    }

    private func isCurrentSession(_ credentialVersion: Int) -> Bool {
        sessionStore.isLoggedIn && sessionStore.playbackCredentialVersion == credentialVersion
    }

    private func inboxCategories(for filter: AccountMessageInboxFilter) -> [AccountMessageCategory] {
        filter.category.map { [$0] } ?? AccountMessageCategory.allCases
    }

    private func privateMessageDraftKey(talkerID: Int) -> String {
        let accountID = sessionStore.user?.mid
            ?? sessionStore.cookieHeader()
                .split(separator: ";")
                .compactMap { item -> Int? in
                    let pair = item.split(separator: "=", maxSplits: 1).map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    guard pair.count == 2, pair[0] == "DedeUserID" else { return nil }
                    return Int(pair[1])
                }
                .first
            ?? 0
        return "cc.bili.accountMessage.privateDraft.\(accountID).\(talkerID)"
    }
}
