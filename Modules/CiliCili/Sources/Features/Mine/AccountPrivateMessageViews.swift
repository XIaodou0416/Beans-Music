import ImageIO
import PhotosUI
import SwiftUI
import UIKit

struct AccountPrivateMessageSessionsView: View {
    @ObservedObject var viewModel: AccountMessageCenterViewModel

    @State private var sessions: [AccountPrivateMessageSession] = []
    @State private var state: LoadingState = .idle
    @State private var mutatingTalkerIDs = Set<Int>()
    @State private var pendingRemoval: AccountPrivateMessageSession?
    @State private var actionErrorMessage: String?
    @State private var searchText = ""
    @State private var isMarkingAllRead = false

    var body: some View {
        List {
            if case .failed(let message) = state, !sessions.isEmpty {
                Section {
                    HStack(spacing: 12) {
                        Label("刷新失败", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 8)

                        Button("重试") {
                            Task { await load() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } footer: {
                    Text(message)
                }
            }

            ForEach(filteredSessions) { session in
                NavigationLink {
                    AccountPrivateMessageConversationView(
                        session: session,
                        viewModel: viewModel,
                        onMarkedRead: { markRead(session.talkerID) },
                        onConversationChanged: {
                            Task { await load() }
                        }
                    )
                } label: {
                    AccountPrivateMessageSessionRow(
                        session: session,
                        inlineEmotes: viewModel.inlineEmotes,
                        isMutating: mutatingTalkerIDs.contains(session.talkerID)
                    )
                }
                .contextMenu {
                    Button {
                        Task { await togglePinned(session) }
                    } label: {
                        Label(
                            session.isPinned ? "取消置顶" : "置顶聊天",
                            systemImage: session.isPinned ? "pin.slash" : "pin"
                        )
                    }

                    Button {
                        Task { await toggleMuted(session) }
                    } label: {
                        Label(
                            session.isMuted ? "关闭免打扰" : "开启免打扰",
                            systemImage: session.isMuted ? "bell" : "bell.slash"
                        )
                    }

                    Button(role: .destructive) {
                        pendingRemoval = session
                    } label: {
                        Label("删除会话", systemImage: "trash")
                    }
                }
                .listRowInsets(
                    EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
                )
            }
        }
        .listStyle(.plain)
        .overlay {
            sessionListOverlay
        }
        .hiddenInlineNavigationTitle()
        .nativeTopScrollEdgeEffect()
        .searchable(text: $searchText, prompt: "搜索用户或最近消息")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isMarkingAllRead {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Menu {
                        Button {
                            Task { await markAllRead() }
                        } label: {
                            Label("全部已读", systemImage: "checkmark.circle")
                        }
                        .disabled(!hasUnreadSessions || state.isLoading)

                        Button {
                            Task { await load() }
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                        .disabled(state.isLoading)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("私信操作")
                }
            }
        }
        .task {
            guard state == .idle else { return }
            await load()
        }
        .refreshable {
            await load()
        }
        .confirmationDialog(
            "删除与该用户的会话？",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingRemoval {
                Button("删除会话", role: .destructive) {
                    self.pendingRemoval = nil
                    Task { await remove(pendingRemoval) }
                }
            }
            Button("取消", role: .cancel) {
                pendingRemoval = nil
            }
        } message: {
            Text("只会删除会话记录，不会拉黑对方。之后收到或发送新私信时，会话会重新出现。")
        }
        .alert(
            "会话操作失败",
            isPresented: Binding(
                get: { actionErrorMessage != nil },
                set: { if !$0 { actionErrorMessage = nil } }
            )
        ) {
            Button("好") { actionErrorMessage = nil }
        } message: {
            Text(actionErrorMessage ?? "请稍后重试")
        }
    }

    @ViewBuilder
    private var sessionListOverlay: some View {
        if sessions.isEmpty {
            switch state {
            case .loading:
                ProgressView("正在加载私信")
            case .failed(let message):
                ContentUnavailableView {
                    Label("加载私信失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") {
                        Task { await load() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .idle, .loaded:
                ContentUnavailableView("暂时没有私信", systemImage: "bubble.left.and.bubble.right")
            }
        } else if filteredSessions.isEmpty {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private func load() async {
        guard !state.isLoading, !isMarkingAllRead else { return }
        state = .loading
        do {
            let result = try await viewModel.fetchPrivateMessageSessions()
            guard !Task.isCancelled else { return }
            sessions = result
            state = .loaded
        } catch is CancellationError {
            state = sessions.isEmpty ? .idle : .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func markRead(_ talkerID: Int) {
        guard let index = sessions.firstIndex(where: { $0.talkerID == talkerID }) else { return }
        sessions[index].unreadCount = 0
    }

    private func markAllRead() async {
        guard !isMarkingAllRead else { return }
        let unreadSessions = sessions.filter { $0.unreadCount > 0 }
        guard !unreadSessions.isEmpty else { return }

        isMarkingAllRead = true
        actionErrorMessage = nil
        let startedAt = Date()
        var succeededCount = 0
        var failureCount = 0
        var missingSequenceCount = 0
        var wasCancelled = false
        defer {
            isMarkingAllRead = false
            viewModel.diagnosticsStore.record(
                operation: "private_mark_all_read",
                startedAt: startedAt,
                outcome: wasCancelled
                    ? "cancelled"
                    : failureCount == 0 && missingSequenceCount == 0 ? "success" : "failure",
                details: [
                    "requested": String(unreadSessions.count),
                    "success": String(succeededCount),
                    "failure": String(failureCount + missingSequenceCount)
                ]
            )
        }

        for session in unreadSessions {
            guard let sequence = session.lastMessageSequence, sequence > 0 else {
                missingSequenceCount += 1
                continue
            }
            do {
                try await viewModel.markPrivateMessageSessionRead(
                    talkerID: session.talkerID,
                    ackSequence: sequence,
                    unreadCount: session.unreadCount
                )
                markRead(session.talkerID)
                succeededCount += 1
            } catch is CancellationError {
                wasCancelled = true
                return
            } catch {
                failureCount += 1
            }
        }

        let totalFailureCount = failureCount + missingSequenceCount
        if totalFailureCount > 0 {
            actionErrorMessage = succeededCount > 0
                ? "已标记 \(succeededCount) 个会话，另有 \(totalFailureCount) 个失败，请刷新后重试"
                : "私信全部已读失败，请刷新后重试"
        }
    }

    private func togglePinned(_ session: AccountPrivateMessageSession) async {
        await mutate(session) {
            let pinned = !session.isPinned
            try await viewModel.setPrivateMessageSessionPinned(
                talkerID: session.talkerID,
                pinned: pinned
            )
            guard let index = sessions.firstIndex(where: { $0.talkerID == session.talkerID }) else {
                return
            }
            sessions[index].isPinned = pinned
            sortSessions()
        }
    }

    private func toggleMuted(_ session: AccountPrivateMessageSession) async {
        await mutate(session) {
            let muted = !session.isMuted
            try await viewModel.setPrivateMessageSessionMuted(
                talkerID: session.talkerID,
                muted: muted
            )
            guard let index = sessions.firstIndex(where: { $0.talkerID == session.talkerID }) else {
                return
            }
            sessions[index].isMuted = muted
        }
    }

    private func remove(_ session: AccountPrivateMessageSession) async {
        await mutate(session) {
            try await viewModel.removePrivateMessageSession(talkerID: session.talkerID)
            sessions.removeAll { $0.talkerID == session.talkerID }
        }
    }

    private func mutate(
        _ session: AccountPrivateMessageSession,
        action: () async throws -> Void
    ) async {
        guard mutatingTalkerIDs.insert(session.talkerID).inserted else { return }
        defer { mutatingTalkerIDs.remove(session.talkerID) }
        actionErrorMessage = nil
        do {
            try await action()
        } catch is CancellationError {
            return
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func sortSessions() {
        sessions.sort {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned
            }
            return ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast)
        }
    }

    private var hasUnreadSessions: Bool {
        sessions.contains { $0.unreadCount > 0 }
    }

    private var filteredSessions: [AccountPrivateMessageSession] {
        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        guard !query.isEmpty else { return sessions }

        return sessions.filter { session in
            "\(session.actor.name) \(session.preview)"
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
                .contains(query)
        }
    }
}

private struct AccountPrivateMessageSessionRow: View {
    let session: AccountPrivateMessageSession
    let inlineEmotes: [String: BiliInlineEmote]
    let isMutating: Bool

    var body: some View {
        HStack(spacing: 12) {
            AvatarRemoteImage(urlString: session.actor.avatarURLString, pixelSize: 128) {
                Image(systemName: "person.crop.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 52, height: 52)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(session.actor.name)
                        .appTypography(
                            .messageName,
                            fallback: .body.weight(session.unreadCount > 0 ? .semibold : .regular)
                        )
                        .lineLimit(1)

                    if session.isMuted {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if session.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                BiliEmoteText(
                    content: nil,
                    plainText: session.preview,
                    inlineEmotes: inlineEmotes,
                    font: .subheadline,
                    textColor: session.unreadCount > 0 ? .primary : .secondary,
                    emoteSize: 19,
                    showsLinkButtons: false,
                    typographyRole: .messagePreview
                )
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 7) {
                if let displayTime = session.displayTime {
                    Text(displayTime)
                        .appTypography(.tertiaryMetadata, fallback: .caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if isMutating {
                    ProgressView()
                        .controlSize(.small)
                        .frame(minWidth: 20, minHeight: 20)
                } else if session.unreadCount > 0 {
                    Text(session.unreadCount > 99 ? "99+" : String(session.unreadCount))
                        .appTypography(.badge, fallback: .caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(.red, in: Capsule())
                        .accessibilityLabel("\(session.unreadCount) 条未读私信")
                }
            }
        }
        .padding(.vertical, 3)
    }
}

private struct AccountPrivateMessageConversationView: View {
    let session: AccountPrivateMessageSession
    @ObservedObject var viewModel: AccountMessageCenterViewModel
    let onMarkedRead: () -> Void
    let onConversationChanged: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var messages: [AccountPrivateMessage] = []
    @State private var state: LoadingState = .idle
    @State private var loadMoreState: LoadingState = .idle
    @State private var hasMore = false
    @State private var endSequence: Int?
    @State private var didMarkRead = false
    @State private var isMarkingRead = false
    @State private var lastAcknowledgedSequence: Int?
    @State private var draft = ""
    @State private var isSending = false
    @State private var isSynchronizingLatest = false
    @State private var isSendingImage = false
    @State private var sendErrorMessage: String?
    @State private var showsEmotePicker = false
    @State private var showsPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var failedImageData: Data?
    @State private var lastFailureWasImage = false
    @State private var draftSaveTask: Task<Void, Never>?
    @State private var pendingWithdrawal: AccountPrivateMessage?
    @State private var reportingMessage: AccountPrivateMessage?
    @State private var mutatingMessageIDs = Set<Int>()
    @State private var messageActionErrorMessage: String?
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    historyControl

                    ForEach(messages) { message in
                        AccountPrivateMessageBubble(
                            message: message,
                            inlineEmotes: viewModel.inlineEmotes,
                            isMutating: mutatingMessageIDs.contains(message.id)
                        )
                            .id(message.id)
                            .contextMenu {
                                messageContextMenu(for: message)
                            }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.top)
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                TapGesture().onEnded {
                    isComposerFocused = false
                }
            )
            .refreshable {
                await load(reset: true)
                scrollToLatest(using: proxy)
            }
            .task(id: session.talkerID) {
                guard state == .idle else { return }
                draft = viewModel.privateMessageDraft(talkerID: session.talkerID)
                if session.unreadCount == 0 {
                    lastAcknowledgedSequence = session.lastMessageSequence
                }
                async let readAcknowledgement: Void = markReadIfNeeded(
                    latestSequence: session.lastMessageSequence
                )
                await load(reset: true)
                scrollToLatest(using: proxy)
                _ = await readAcknowledgement
                await synchronizeLoop(using: proxy)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composer(using: proxy)
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task { await sendSelectedPhoto(item, using: proxy) }
            }
            .photosPicker(
                isPresented: $showsPhotoPicker,
                selection: $selectedPhoto,
                matching: .images
            )
        }
        .overlay {
            if messages.isEmpty {
                emptyContent
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
        .nativeTopScrollEdgeEffect()
        .toolbar {
            ToolbarItem(placement: .principal) {
                AccountPrivateMessageConversationHeader(actor: session.actor)
            }
        }
        .sheet(isPresented: $showsEmotePicker) {
            AccountPrivateMessageEmotePicker(
                emotes: Array(viewModel.inlineEmotes.values),
                onSelect: { token in
                    draft.append(token)
                    isComposerFocused = true
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $reportingMessage) { message in
            AccountPrivateMessageReportSheet(
                message: message,
                viewModel: viewModel
            )
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "撤回这条私信？",
            isPresented: Binding(
                get: { pendingWithdrawal != nil },
                set: { if !$0 { pendingWithdrawal = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingWithdrawal {
                Button("撤回", role: .destructive) {
                    self.pendingWithdrawal = nil
                    Task { await withdraw(pendingWithdrawal) }
                }
            }
            Button("取消", role: .cancel) {
                pendingWithdrawal = nil
            }
        } message: {
            Text("撤回后，对方将无法继续查看这条消息。是否能撤回仍由 B站服务器判断。")
        }
        .alert(
            "消息操作失败",
            isPresented: Binding(
                get: { messageActionErrorMessage != nil },
                set: { if !$0 { messageActionErrorMessage = nil } }
            )
        ) {
            Button("好") { messageActionErrorMessage = nil }
        } message: {
            Text(messageActionErrorMessage ?? "请稍后重试")
        }
        .onChange(of: draft) { _, _ in
            scheduleDraftSave()
        }
        .onDisappear {
            draftSaveTask?.cancel()
            viewModel.savePrivateMessageDraft(draft, talkerID: session.talkerID)
            onConversationChanged()
        }
    }

    @ViewBuilder
    private var historyControl: some View {
        if loadMoreState.isLoading {
            ProgressView("正在加载更早消息")
                .font(.caption)
                .padding(.vertical, 8)
        } else if case .failed(let message) = loadMoreState {
            Button {
                Task { await load(reset: false) }
            } label: {
                Label("加载更早消息失败", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .accessibilityHint(message)
            .padding(.vertical, 8)
        } else if hasMore {
            Button("加载更早消息") {
                Task { await load(reset: false) }
            }
            .font(.caption.weight(.medium))
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        switch state {
        case .loading:
            ProgressView("正在加载私信内容")
        case .failed(let message):
            ContentUnavailableView {
                Label("加载私信失败", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("重试") {
                    Task { await load(reset: true) }
                }
            }
        case .idle, .loaded:
            ContentUnavailableView("暂无私信内容", systemImage: "bubble.left.and.bubble.right")
        }
    }

    private func load(reset: Bool) async {
        guard !state.isLoading, !loadMoreState.isLoading else { return }
        if reset {
            state = .loading
        } else {
            loadMoreState = .loading
        }

        do {
            let previousEndSequence = endSequence
            let page = try await viewModel.fetchPrivateMessages(
                talkerID: session.talkerID,
                endSequence: reset ? nil : endSequence
            )
            guard !Task.isCancelled else { return }

            if reset {
                let locallyWithdrawnKeys = Set(
                    messages
                        .filter(\.isWithdrawn)
                        .compactMap(\.messageKey)
                )
                messages = page.items.map { item in
                    var item = item
                    if let messageKey = item.messageKey,
                       locallyWithdrawnKeys.contains(messageKey) {
                        item.isWithdrawn = true
                    }
                    return item
                }
                hasMore = page.hasMore && !page.items.isEmpty
            } else {
                var seen = Set(messages.map(\.id))
                let newItems = page.items.filter { seen.insert($0.id).inserted }
                messages.insert(contentsOf: newItems, at: 0)
                hasMore = page.hasMore
                    && !newItems.isEmpty
                    && page.nextEndSequence != previousEndSequence
            }
            endSequence = page.nextEndSequence
            state = .loaded
            loadMoreState = .idle
            if reset {
                Task {
                    await markReadIfNeeded(
                        latestSequence: page.items.last(where: { !$0.isOutgoing })?.sequence
                    )
                }
            }
        } catch is CancellationError {
            state = messages.isEmpty ? .idle : .loaded
            loadMoreState = .idle
        } catch {
            if reset {
                state = .failed(error.localizedDescription)
            } else {
                loadMoreState = .failed(error.localizedDescription)
            }
        }
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard let id = messages.last?.id else { return }
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo(id, anchor: .bottom)
        }
    }

    private func synchronizeLoop(using proxy: ScrollViewProxy) async {
        var consecutiveFailures = 0
        while !Task.isCancelled {
            let delays = [15, 30, 60]
            let delay = delays[min(consecutiveFailures, delays.count - 1)]
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard scenePhase == .active else { continue }
            guard let didUpdate = await synchronizeLatestMessages() else {
                consecutiveFailures += 1
                continue
            }
            consecutiveFailures = 0
            if didUpdate {
                scrollToLatest(using: proxy)
            }
        }
    }

    private func synchronizeLatestMessages() async -> Bool? {
        guard !isSynchronizingLatest, !state.isLoading, !isSending, !isSendingImage else { return false }
        isSynchronizingLatest = true
        defer { isSynchronizingLatest = false }

        do {
            let page = try await viewModel.fetchPrivateMessages(talkerID: session.talkerID)
            guard !Task.isCancelled else { return false }
            let previousLatestSequence = messages.last?.sequence ?? 0
            var merged = [Int: AccountPrivateMessage]()
            for message in messages {
                merged[message.sequence] = message
            }
            for var message in page.items {
                if merged[message.sequence]?.isWithdrawn == true {
                    message.isWithdrawn = true
                }
                merged[message.sequence] = message
            }
            messages = merged.values.sorted { $0.sequence < $1.sequence }

            if let latestIncomingSequence = page.items.last(where: { !$0.isOutgoing })?.sequence,
               latestIncomingSequence > previousLatestSequence {
                await markReadIfNeeded(latestSequence: latestIncomingSequence)
            }
            return (messages.last?.sequence ?? 0) > previousLatestSequence
        } catch {
            return nil
        }
    }

    private func scheduleDraftSave() {
        draftSaveTask?.cancel()
        let value = draft
        draftSaveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            viewModel.savePrivateMessageDraft(value, talkerID: session.talkerID)
        }
    }

    @ViewBuilder
    private func messageContextMenu(for message: AccountPrivateMessage) -> some View {
        if let copyableText = copyableText(for: message) {
            Button {
                UIPasteboard.general.string = copyableText
            } label: {
                Label("复制文字", systemImage: "doc.on.doc")
            }
        }

        if let imageURLString = message.imageURLString, !message.isWithdrawn {
            Button {
                UIPasteboard.general.string = imageURLString
            } label: {
                Label("复制图片链接", systemImage: "link")
            }
        }

        if message.canWithdraw {
            Button(role: .destructive) {
                pendingWithdrawal = message
            } label: {
                Label("撤回", systemImage: "arrow.uturn.backward")
            }
            .disabled(mutatingMessageIDs.contains(message.id))
        } else if message.canReport {
            Button(role: .destructive) {
                reportingMessage = message
            } label: {
                Label("举报", systemImage: "exclamationmark.bubble")
            }
            .disabled(mutatingMessageIDs.contains(message.id))
        }
    }

    private func copyableText(for message: AccountPrivateMessage) -> String? {
        guard !message.isWithdrawn else { return nil }
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != "[图片]" else { return nil }
        return text
    }

    private func withdraw(_ message: AccountPrivateMessage) async {
        guard let messageKey = message.messageKey,
              mutatingMessageIDs.insert(message.id).inserted
        else {
            return
        }
        defer { mutatingMessageIDs.remove(message.id) }
        messageActionErrorMessage = nil

        do {
            try await viewModel.withdrawPrivateMessage(
                talkerID: session.talkerID,
                messageKey: messageKey
            )
            guard !Task.isCancelled else { return }
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index].isWithdrawn = true
            }
            onConversationChanged()
        } catch is CancellationError {
            return
        } catch {
            messageActionErrorMessage = error.localizedDescription
        }
    }

    private func composer(using proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 8) {
            if let sendErrorMessage {
                HStack(spacing: 8) {
                    Label(sendErrorMessage, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)

                    Spacer(minLength: 4)

                    if hasRetryPayload {
                        Button("重试") {
                            Task { await retryFailedSend(using: proxy) }
                        }
                        .font(.caption.weight(.semibold))
                        .disabled(isSending || isSendingImage)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    Color.red.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Menu {
                        Button {
                            showsPhotoPicker = true
                        } label: {
                            Label("照片", systemImage: "photo")
                        }

                        Button {
                            showsEmotePicker = true
                        } label: {
                            Label("B站表情", systemImage: "face.smiling")
                        }
                        .disabled(viewModel.inlineEmotes.isEmpty)
                    } label: {
                        Group {
                            if isSendingImage {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "plus")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                        }
                        .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .disabled(isSending || isSendingImage)
                    .accessibilityLabel("添加附件")

                    TextField("发私信", text: $draft, axis: .vertical)
                        .lineLimit(1 ... 4)
                        .focused($isComposerFocused)
                        .textFieldStyle(.plain)
                        .submitLabel(.send)
                        .onSubmit {
                            Task { await send(using: proxy) }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .frame(minHeight: 40, alignment: .center)
                        .disabled(isSending || isSendingImage)
                        .overlay(alignment: .trailing) {
                            if isSending {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 12)
                            }
                        }
                    .biliRegularGlassEffect(
                        interactive: true,
                        in: Capsule(style: .continuous)
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasRetryPayload: Bool {
        lastFailureWasImage ? failedImageData != nil : !trimmedDraft.isEmpty
    }

    private func send(using proxy: ScrollViewProxy) async {
        let text = trimmedDraft
        guard !text.isEmpty, !isSending, !isSendingImage else { return }
        isSending = true
        defer { isSending = false }
        sendErrorMessage = nil
        failedImageData = nil
        lastFailureWasImage = false
        do {
            try await viewModel.sendPrivateTextMessage(talkerID: session.talkerID, text: text)
            guard !Task.isCancelled else { return }
            draft = ""
            viewModel.savePrivateMessageDraft("", talkerID: session.talkerID)
            await load(reset: true)
            scrollToLatest(using: proxy)
            onConversationChanged()
        } catch is CancellationError {
            return
        } catch {
            sendErrorMessage = error.localizedDescription
        }
    }

    private func sendSelectedPhoto(_ item: PhotosPickerItem, using proxy: ScrollViewProxy) async {
        guard !isSending, !isSendingImage else { return }
        isSendingImage = true
        defer {
            isSendingImage = false
            selectedPhoto = nil
        }
        sendErrorMessage = nil
        failedImageData = nil

        var preparedData: Data?
        do {
            guard let sourceData = try await item.loadTransferable(type: Data.self) else {
                throw AccountPrivateMessageImageError.unreadable
            }
            let data = try await Task.detached(priority: .userInitiated) {
                try AccountPrivateMessageImagePreparation.jpegData(from: sourceData)
            }.value
            preparedData = data
            try await completeImageSend(data, using: proxy)
        } catch is CancellationError {
            return
        } catch {
            lastFailureWasImage = true
            failedImageData = isPermanentImageSendFailure(error) ? nil : preparedData
            sendErrorMessage = privateImageSendErrorMessage(error)
        }
    }

    private func retryFailedSend(using proxy: ScrollViewProxy) async {
        if let failedImageData {
            guard !isSending, !isSendingImage else { return }
            isSendingImage = true
            defer { isSendingImage = false }
            sendErrorMessage = nil
            do {
                try await completeImageSend(failedImageData, using: proxy)
            } catch is CancellationError {
                return
            } catch {
                lastFailureWasImage = true
                if isPermanentImageSendFailure(error) {
                    self.failedImageData = nil
                }
                sendErrorMessage = privateImageSendErrorMessage(error)
            }
        } else {
            await send(using: proxy)
        }
    }

    private func completeImageSend(_ imageData: Data, using proxy: ScrollViewProxy) async throws {
        try await viewModel.sendPrivateImageMessage(
            talkerID: session.talkerID,
            imageData: imageData
        )
        guard !Task.isCancelled else { throw CancellationError() }
        failedImageData = nil
        lastFailureWasImage = false
        await load(reset: true)
        scrollToLatest(using: proxy)
        onConversationChanged()
    }

    private func isPermanentImageSendFailure(_ error: Error) -> Bool {
        guard let error = error as? BiliAPIError,
              case .api(let code, _) = error
        else {
            return false
        }
        return code == 25_006
    }

    private func privateImageSendErrorMessage(_ error: Error) -> String {
        if isPermanentImageSendFailure(error) {
            return "当前会话暂时不能发图，请先等对方回复或关注你后再试"
        }
        return error.localizedDescription
    }

    private func markReadIfNeeded(latestSequence: Int?) async {
        guard !isMarkingRead,
              let latestSequence,
              latestSequence > (lastAcknowledgedSequence ?? 0)
        else {
            return
        }
        isMarkingRead = true
        defer { isMarkingRead = false }
        do {
            try await viewModel.markPrivateMessageSessionRead(
                talkerID: session.talkerID,
                ackSequence: latestSequence,
                unreadCount: didMarkRead ? 0 : session.unreadCount
            )
            lastAcknowledgedSequence = latestSequence
            if !didMarkRead {
                didMarkRead = true
                if session.unreadCount > 0 {
                    onMarkedRead()
                }
            }
        } catch {
            // Keep the unread state so a later refresh can retry the acknowledgement.
        }
    }
}

private struct AccountPrivateMessageConversationHeader: View {
    let actor: AccountMessageActor

    var body: some View {
        HStack(spacing: 7) {
            AvatarRemoteImage(urlString: actor.avatarURLString, pixelSize: 72) {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 26, height: 26)
            .clipShape(Circle())

            Text(actor.name)
                .appTypography(.navigationTitle, fallback: .subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: 220)
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .biliRegularGlassEffect(in: Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("与\(actor.name)的私信")
    }
}

private nonisolated enum AccountPrivateMessageImageError: LocalizedError {
    case unreadable
    case encodingFailed
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "无法读取这张图片"
        case .encodingFailed:
            return "图片处理失败"
        case .tooLarge:
            return "图片处理后仍超过 20 MB"
        }
    }
}

private nonisolated enum AccountPrivateMessageImagePreparation {
    static func jpegData(from data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw AccountPrivateMessageImageError.unreadable
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 2_048
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw AccountPrivateMessageImageError.encodingFailed
        }

        let image = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        var lastData: Data?
        for quality in [0.88, 0.76, 0.64, 0.52] {
            guard let encoded = image.jpegData(compressionQuality: quality) else { continue }
            lastData = encoded
            if encoded.count <= 12 * 1_024 * 1_024 {
                return encoded
            }
        }
        guard let lastData else {
            throw AccountPrivateMessageImageError.encodingFailed
        }
        guard lastData.count <= 20 * 1_024 * 1_024 else {
            throw AccountPrivateMessageImageError.tooLarge
        }
        return lastData
    }
}

private nonisolated enum AccountPrivateMessageReportReason: Int, CaseIterable, Identifiable {
    case sexualContent = 1
    case politicalContent = 2
    case illegalContent = 3
    case advertising = 4
    case personalAttack = 5
    case fraud = 6
    case other = 0

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .sexualContent:
            return "色情低俗"
        case .politicalContent:
            return "政治敏感"
        case .illegalContent:
            return "违法有害"
        case .advertising:
            return "广告骚扰"
        case .personalAttack:
            return "人身攻击"
        case .fraud:
            return "诈骗"
        case .other:
            return "其他问题"
        }
    }
}

private struct AccountPrivateMessageReportSheet: View {
    let message: AccountPrivateMessage
    @ObservedObject var viewModel: AccountMessageCenterViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: AccountPrivateMessageReportReason?
    @State private var customReason = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("选择举报原因") {
                    Picker("举报原因", selection: $selectedReason) {
                        Text("请选择").tag(AccountPrivateMessageReportReason?.none)
                        ForEach(AccountPrivateMessageReportReason.allCases) { reason in
                            Text(reason.title).tag(Optional(reason))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if selectedReason == .other {
                    Section("补充说明") {
                        TextField("请说明具体问题", text: $customReason, axis: .vertical)
                            .lineLimit(2 ... 5)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .hiddenInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("提交")
                        }
                    }
                    .disabled(!canSubmit || isSubmitting)
                }
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    private var canSubmit: Bool {
        guard let selectedReason else { return false }
        return selectedReason != .other
            || !customReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() async {
        guard let selectedReason,
              let messageKey = message.messageKey,
              canSubmit,
              !isSubmitting
        else {
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil
        let description = selectedReason == .other
            ? customReason.trimmingCharacters(in: .whitespacesAndNewlines)
            : selectedReason.title

        do {
            try await viewModel.reportPrivateMessage(
                accusedUserID: message.senderID,
                messageKey: messageKey,
                reasonType: selectedReason.rawValue,
                reasonDescription: description
            )
            guard !Task.isCancelled else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AccountPrivateMessageEmotePicker: View {
    let emotes: [BiliInlineEmote]
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 44), spacing: 10),
        count: 5
    )

    var body: some View {
        NavigationStack {
            Group {
                if sortedEmotes.isEmpty {
                    ContentUnavailableView("暂无可用表情", systemImage: "face.smiling")
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(sortedEmotes, id: \.token) { emote in
                                Button {
                                    onSelect(emote.token)
                                    dismiss()
                                } label: {
                                    VStack(spacing: 5) {
                                        CachedRemoteImage(
                                            url: emote.displayURL.flatMap(URL.init(string:)),
                                            targetPixelSize: 88
                                        ) { image in
                                            image.resizable().scaledToFit()
                                        } placeholder: {
                                            Image(systemName: "face.smiling")
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 38, height: 38)

                                        Text(emote.token)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.75)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 62)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(emote.token)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .hiddenInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var sortedEmotes: [BiliInlineEmote] {
        let commonTokens = [
            "[doge]", "[笑哭]", "[支持]", "[点赞]", "[抱拳]", "[呲牙]", "[吃瓜]",
            "[妙啊]", "[打call]", "[星星眼]", "[滑稽]", "[藏狐]", "[辣眼睛]", "[OK]", "[捂脸]"
        ]
        let priority = Dictionary(uniqueKeysWithValues: commonTokens.enumerated().map { ($1, $0) })
        return Array(emotes.sorted {
            let left = priority[$0.token] ?? Int.max
            let right = priority[$1.token] ?? Int.max
            if left != right { return left < right }
            return $0.token.localizedStandardCompare($1.token) == .orderedAscending
        }.prefix(60))
    }
}

private struct AccountPrivateMessageBubble: View {
    let message: AccountPrivateMessage
    let inlineEmotes: [String: BiliInlineEmote]
    let isMutating: Bool
    @Environment(\.appThemeTintColor) private var appTintColor
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack {
            if message.isOutgoing {
                Spacer(minLength: 54)
            }

            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 4) {
                destination

                HStack(spacing: 5) {
                    if isMutating {
                        ProgressView()
                            .controlSize(.mini)
                    }

                    if let displayTime = message.displayTime {
                        Text(displayTime)
                            .appTypography(.tertiaryMetadata, fallback: .caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !message.isOutgoing {
                Spacer(minLength: 54)
            }
        }
    }

    @ViewBuilder
    private var destination: some View {
        if let routeURL = message.isWithdrawn ? nil : message.routeURL {
            AppLinkButton(url: routeURL) {
                bubble
            }
        } else {
            bubble
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 7) {
            if message.isWithdrawn {
                Label(
                    message.isOutgoing ? "你撤回了一条消息" : "对方撤回了一条消息",
                    systemImage: "arrow.uturn.backward"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if let imageURLString = message.imageURLString {
                if message.messageType == 2 || message.messageType == 6 {
                    previewableMessageImage(imageURLString)
                } else {
                    cardImage(imageURLString)
                }
            }

            if shouldShowText, !message.isWithdrawn {
                BiliEmoteText(
                    content: nil,
                    plainText: message.text,
                    inlineEmotes: inlineEmotes,
                    font: .subheadline,
                    textColor: messageTextColor,
                    emoteSize: 21,
                    showsLinkButtons: false,
                    typographyRole: .messageBody
                )
                .frame(width: messageTextWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            bubbleColor,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: message.isOutgoing ? 18 : 6,
                bottomTrailingRadius: message.isOutgoing ? 6 : 18,
                topTrailingRadius: 18,
                style: .continuous
            )
        )
        .contentShape(Rectangle())
    }

    private var messageTextColor: Color {
        message.isOutgoing && !message.isWithdrawn ? .white : .primary
    }

    private var bubbleColor: Color {
        if message.isWithdrawn {
            return Color(uiColor: .tertiarySystemFill)
        }
        return message.isOutgoing
            ? appTintColor
            : Color(uiColor: .secondarySystemFill)
    }

    private func previewableMessageImage(_ imageURLString: String) -> some View {
        let originalURL = URL(string: imageURLString)
        return ZoomyRemoteImage(
            url: URL(string: imageURLString.biliCoverThumbnailURL(width: 480, height: 360)),
            fallbackURL: originalURL,
            viewerURL: originalURL,
            targetPixelSize: 480,
            viewerTargetPixelSize: 2_400,
            cornerRadius: 10,
            contentMode: .fill,
            phasePlaceholder: { phase in
                BiliMediaPlaceholder(style: .image, phase: phase, iconSize: 18)
            }
        )
        .frame(width: 200, height: 140)
    }

    private func cardImage(_ imageURLString: String) -> some View {
        CachedRemoteImage(
            url: URL(string: imageURLString.biliCoverThumbnailURL(width: 480, height: 360)),
            fallbackURL: URL(string: imageURLString),
            targetPixelSize: 480
        ) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Color.gray.opacity(0.14)
        }
        .frame(width: 200, height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var shouldShowText: Bool {
        message.imageURLString == nil || message.text != "[图片]"
    }

    private var messageTextWidth: CGFloat {
        let maximumWidth: CGFloat = horizontalSizeClass == .regular ? 420 : 300
        var measuredText = message.text
        for token in inlineEmotes.keys where measuredText.contains(token) {
            measuredText = measuredText.replacingOccurrences(of: token, with: "口")
        }
        let font = AppTypography.Role.messageBody.uiFont(
            contentSizeCategory: dynamicTypeSize.uiContentSizeCategory
        )
        let bounds = (measuredText as NSString).boundingRect(
            with: CGSize(width: maximumWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return min(max(ceil(bounds.width), 12), maximumWidth)
    }
}
