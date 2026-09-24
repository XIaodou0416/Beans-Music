import SwiftUI

// Comment section structure and single presentation routing adapted from
// CiliCili (Rone89), GPL-3.0. See THIRD_PARTY_NOTICES.md.

@MainActor
final class BilibiliReplyStore: ObservableObject {
    @Published var rows: [BilibiliReply] = []
    @Published var total = 0
    @Published var loading = false
    @Published var error: String?
    @Published var more = true
    private var page = 0
    private var generation = UUID()
    private var context: String?
    private var loadedContext: String?
    private var request: Task<Void, Never>?
    private var refreshing = false
    private let fetch: (String, Int, Bool, String?) async throws -> BilibiliReplies

    init(fetch: @escaping (String, Int, Bool, String?) async throws -> BilibiliReplies = { aid, page, hot, root in
        try await BilibiliAPI.shared.nativeReplies(aid: aid, page: page, hot: hot, root: root)
    }) {
        self.fetch = fetch
    }
    func load(aid: String, hot: Bool, root: String?, reset: Bool, ifNeeded: Bool = false) async {
        let nextContext = "\(aid)|\(hot)|\(root ?? "")|\(BilibiliAuth.shared.accountID)|\(BilibiliAuth.shared.isLoggedIn)"
        if ifNeeded && context == nextContext && loadedContext == nextContext { return }
        if loading && context == nextContext {
            let needsRefreshAfterPage = reset && !refreshing
            await request?.value
            if needsRefreshAfterPage && context == nextContext {
                await load(aid: aid, hot: hot, root: root, reset: true)
            }
            return
        }
        if !reset && (loading || !more) { return }
        if reset {
            request?.cancel()
            generation = UUID()
            if context != nextContext { rows = []; total = 0; page = 0; more = true; loadedContext = nil }
        }
        context = nextContext
        let token = generation
        loading = true; error = nil
        refreshing = reset
        let next = reset ? 1 : page + 1
        // The store owns the request. Cancelling a view task during navigation
        // must not discard its data or launch a second request on return.
        let operation = Task { @MainActor in
            defer { if token == generation { loading = false; request = nil } }
            do {
                let result = try await fetch(aid, next, hot, root)
                try Task.checkCancellation()
                guard token == generation else { return }
                var seen = Set(reset ? [] : rows.map(\.id))
                let additions = result.items.filter { seen.insert($0.id).inserted }
                rows = reset ? additions : rows + additions
                total = result.total; page = next; more = result.hasMore
                loadedContext = nextContext
            } catch is CancellationError { }
            catch { if token == generation && !Task.isCancelled { self.error = error.localizedDescription } }
        }
        request = operation
        await operation.value
    }
}

struct BilibiliNativeComments: View {
    let aid: String
    var root: BilibiliReply? = nil
    let showsComposerBar: Bool
    private let externalComposer: Binding<Bool>?
    let refreshID: Int
    let isActive: Bool
    private let onOpenAuthor: ((Artist) -> Void)?
    @StateObject private var store = BilibiliReplyStore()
    @ObservedObject private var account = BilibiliAuth.shared
    @Environment(\.bilibiliNavigate) private var navigate
    @State private var hot = true
    @State private var fallbackRoute: BilibiliNativeRoute?
    @State private var sheet: BilibiliCommentSheet?
    @State private var pendingComposer: BilibiliCommentTarget?
    @State private var pendingAuthor: Artist?
    @State private var mutation: String?
    @State private var mutationError: String?
    @State private var likedOverrides: [String: Bool] = [:]

    init(
        aid: String,
        root: BilibiliReply? = nil,
        showsComposerBar: Bool = true,
        composer: Binding<Bool>? = nil,
        refreshID: Int = 0,
        isActive: Bool = true,
        onOpenAuthor: ((Artist) -> Void)? = nil
    ) {
        self.aid = aid
        self.root = root
        self.showsComposerBar = showsComposerBar
        self.externalComposer = composer
        self.refreshID = refreshID
        self.isActive = isActive
        self.onOpenAuthor = onOpenAuthor
    }

    private var loadKey: String {
        "\(aid)|\(hot)|\(root?.id ?? "")|\(account.accountID)|\(account.isLoggedIn)"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    sectionHeader.padding(.vertical, 9)
                    if let root { replyRow(root, isRoot: true); Divider() }
                    if store.loading && store.rows.isEmpty {
                        BilibiliCommentSkeleton()
                    }
                    ForEach(store.rows) { reply in
                        replyRow(reply)
                            .onAppear {
                                if isActive && reply.id == store.rows.last?.id && store.more && store.error == nil {
                                    Task { await reload(reset: false) }
                                }
                            }
                        Divider()
                    }
                    if store.loading && !store.rows.isEmpty { ProgressView().frame(maxWidth: .infinity, minHeight: 60) }
                    if let error = store.error { BilibiliInlineError(message: error) { Task { await reload(reset: store.rows.isEmpty) } } }
                    if !store.loading && store.error == nil && store.rows.isEmpty {
                        Text("暂无评论，来说点什么吧").font(.subheadline).foregroundStyle(Color.beansComment)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                    if !store.loading && store.more && !store.rows.isEmpty && store.error == nil {
                        Button("加载更多") { Task { await reload(reset: false) } }.padding()
                    }
                }.padding(.horizontal, 13).padding(.bottom, 20)
            }.refreshable { await reload(reset: true) }
            if showsComposerBar {
                Button {
                    requestComposer(for: root)
                } label: {
                    HStack {
                        Image(systemName: "square.and.pencil")
                        Text(account.isLoggedIn ? "发一条友善的评论…" : "登录后参与评论")
                        Spacer()
                    }
                    .font(BeansFont.appFont(16, .medium))
                    .foregroundStyle(Color.beansComment)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 52)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .task(id: loadKey) {
            await store.load(aid: aid, hot: hot, root: root?.id, reset: true, ifNeeded: true)
        }
        .onChange(of: loadKey) { _ in likedOverrides = [:] }
        .onChange(of: refreshID) { _ in
            Task { await reload(reset: true) }
        }
        .onChange(of: externalComposer?.wrappedValue ?? false) { requested in
            guard requested else { return }
            // Consume the toolbar request. One route below owns presentation;
            // the external binding cannot recreate a dismissed sheet.
            externalComposer?.wrappedValue = false
            requestComposer(for: root)
        }
        .fullScreenCover(item: $fallbackRoute) { route in
            BilibiliNativeStandaloneStack(initialRoute: route)
        }
        .sheet(item: $sheet, onDismiss: finishSheetDismissal) { route in
            switch route {
            case .login:
                BilibiliLoginSheet()
            case .compose(let target):
                BilibiliCommentComposer(aid: aid, root: target.root, parent: target.parent, replyAuthor: target.author) {
                    Task { await reload(reset: true) }
                }
            case .thread(let reply):
                BeansNavigationStack {
                    AnyView(BilibiliNativeComments(aid: aid, root: reply, onOpenAuthor: { author in
                        pendingAuthor = author
                        sheet = nil
                    }))
                        .navigationTitle("评论回复").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { sheet = nil } } }
                }
            case .image(let url):
                BilibiliCommentImagePreview(url: url)
            }
        }
        .alert("操作未完成", isPresented: Binding(get: { mutationError != nil }, set: { if !$0 { mutationError = nil } })) {
            Button("知道了") { mutationError = nil }
        } message: { Text(mutationError ?? "") }
    }
    private var sectionHeader: some View {
        HStack(spacing: 8) {
            Text(root == nil ? "评论" : "回复").font(.headline)
            Text("\(store.total)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if root == nil {
                sortButton("最热", selected: hot) { hot = true }
                sortButton("最新", selected: !hot) { hot = false }
            }
        }
    }

    private func sortButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .foregroundStyle(selected ? Color.beansAmber : Color.beansComment)
            .background(selected ? Color.beansAmber.opacity(0.14) : .clear, in: Capsule())
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func replyRow(_ reply: BilibiliReply, isRoot: Bool = false) -> some View {
        let liked = likedOverrides[reply.id] ?? reply.liked
        return BilibiliCommentRow(
            reply: reply, liked: liked, likeDisabled: mutation != nil,
            showsPreviews: root == nil && !isRoot,
            openAuthor: { openAuthor(reply.author) },
            like: { like(reply, current: liked) },
            compose: { requestComposer(for: reply) },
            showReplies: { sheet = .thread(reply) },
            showImage: { sheet = .image($0) }
        )
    }
    private func reload(reset: Bool) async {
        if reset { likedOverrides = [:] }
        await store.load(aid: aid, hot: hot, root: root?.id, reset: reset)
    }
    private func requestComposer(for reply: BilibiliReply?) {
        guard sheet == nil else { return }
        let target = BilibiliCommentTarget(root: root?.id ?? reply?.id, parent: reply?.id, author: reply?.author.name)
        if account.isLoggedIn { sheet = .compose(target) }
        else { pendingComposer = target; sheet = .login }
    }
    private func finishSheetDismissal() {
        if let author = pendingAuthor {
            pendingAuthor = nil
            openAuthor(author)
            return
        }
        guard let target = pendingComposer else { return }
        pendingComposer = nil
        if account.isLoggedIn { sheet = .compose(target) }
    }
    private func openAuthor(_ author: Artist) {
        if let onOpenAuthor { onOpenAuthor(author) }
        else if let navigate { navigate(.up(author)) }
        else { fallbackRoute = .up(author) }
    }
    private func like(_ reply: BilibiliReply, current: Bool) {
        guard account.isLoggedIn else { sheet = .login; return }
        guard mutation == nil else { return }
        mutation = reply.id
        Task { @MainActor in
            defer { mutation = nil }
            do {
                try await BilibiliAPI.shared.nativeCommentLike(aid: aid, reply: reply.id, like: !current)
                likedOverrides[reply.id] = !current
            } catch { mutationError = error.localizedDescription }
        }
    }
}

struct BilibiliCommentComposer: View {
    let aid: String
    let root: String?
    var parent: String? = nil
    var replyAuthor: String? = nil
    let onSent: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var sending = false
    @State private var error: String?
    @FocusState private var focused: Bool
    var body: some View {
        BeansNavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if let replyAuthor { Text("回复 \(replyAuthor)").font(.subheadline).foregroundStyle(.secondary) }
                TextEditor(text: $text).focused($focused).frame(minHeight: 160)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty { Text("写下你的评论…").foregroundStyle(.secondary).padding(8).allowsHitTesting(false) }
                    }
                Text("\(text.count)/1000").font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                if sending { ProgressView("正在发送") }
                Spacer()
            }.padding()
            .navigationTitle(root == nil ? "发表评论" : "回复评论").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(sending) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发送") {
                        sending = true; error = nil
                        Task { @MainActor in
                            defer { sending = false }
                            do {
                                try await BilibiliAPI.shared.nativeComment(aid: aid, message: text, root: root, parent: parent)
                                onSent(); dismiss()
                            } catch { self.error = "\(error.localizedDescription)。请刷新评论确认结果，勿连续重复发送。" }
                        }
                    }.disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 1000)
                }
            }
        }
        .onAppear { focused = true }
        .interactiveDismissDisabled(sending)
    }
}

struct BilibiliAudioCommentsPage: View {
    let song: Song
    @Environment(\.dismiss) private var dismiss
    @State private var aid: String?
    @State private var error: String?
    var body: some View {
        BeansNavigationStack {
            Group {
                if let aid { BilibiliNativeComments(aid: aid) }
                else if let error { BilibiliInlineError(message: error) { Task { await load() } } }
                else { ProgressView("正在加载视频评论") }
            }
            .navigationTitle("视频评论").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.task(id: song.identityKey) { await load() }
    }
    private func load() async {
        error = nil
        do { aid = try await BilibiliAPI.shared.nativeVideo(song).aid }
        catch { self.error = error.localizedDescription }
    }
}
