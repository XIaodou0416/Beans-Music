import SwiftUI

@MainActor
final class BilibiliReplyStore: ObservableObject {
    @Published var rows: [BilibiliReply] = []
    @Published var total = 0
    @Published var loading = false
    @Published var error: String?
    @Published var more = true
    private var page = 0
    private var generation = UUID()
    func load(aid: String, hot: Bool, root: String?, reset: Bool) async {
        if !reset && (loading || !more) { return }
        if reset { generation = UUID(); page = 0; more = true; rows = [] }
        let token = generation
        loading = true; error = nil
        let next = reset ? 1 : page + 1
        defer { if token == generation { loading = false } }
        do {
            let result = try await BilibiliAPI.shared.nativeReplies(aid: aid, page: next, hot: hot, root: root)
            try Task.checkCancellation()
            guard token == generation else { return }
            var seen = Set(reset ? [] : rows.map(\.id))
            let additions = result.items.filter { seen.insert($0.id).inserted }
            rows = reset ? additions : rows + additions
            total = result.total; page = next; more = result.hasMore
        } catch is CancellationError { }
        catch { if token == generation { self.error = error.localizedDescription } }
    }
}

struct BilibiliNativeComments: View {
    let aid: String
    var root: BilibiliReply? = nil
    @StateObject private var store = BilibiliReplyStore()
    @ObservedObject private var account = BilibiliAuth.shared
    @State private var hot = true
    @State private var composer = false
    @State private var showLogin = false
    @State private var route: BilibiliNativeRoute?
    @State private var thread: BilibiliReply?
    @State private var mutation: String?
    @State private var mutationError: String?
    @State private var likedOverrides: [String: Bool] = [:]
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if root == nil {
                    Picker("排序", selection: $hot) { Text("热门").tag(true); Text("最新").tag(false) }
                        .pickerStyle(.segmented).frame(maxWidth: 190)
                } else { Text("回复 \(root?.author.name ?? "")").font(.headline) }
                Spacer(minLength: 4)
                Text("\(store.total) 条").font(.caption).foregroundStyle(Color.beansComment)
            }.padding(.horizontal, 16).padding(.vertical, 10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let root { replyRow(root, isRoot: true); Divider() }
                    ForEach(store.rows) { reply in
                        replyRow(reply)
                            .onAppear {
                                if reply.id == store.rows.last?.id && store.more && store.error == nil {
                                    Task { await reload(reset: false) }
                                }
                            }
                    }
                    if store.loading { ProgressView().frame(maxWidth: .infinity, minHeight: 60) }
                    if let error = store.error { BilibiliInlineError(message: error) { Task { await reload(reset: store.rows.isEmpty) } } }
                    if !store.loading && store.error == nil && store.rows.isEmpty {
                        Text("暂无评论，来说点什么吧").font(.subheadline).foregroundStyle(Color.beansComment)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }.padding(16)
            }.refreshable { await reload(reset: true) }
            Button {
                if account.isLoggedIn { composer = true } else { showLogin = true }
            } label: {
                HStack {
                    Image(systemName: "square.and.pencil")
                    Text(account.isLoggedIn ? "发一条友善的评论…" : "登录后参与评论")
                    Spacer()
                }.font(.subheadline).padding(14).background(Color.beansGlassFill, in: Capsule())
            }.buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 10)
        }
        .task(id: "\(aid)|\(hot)|\(root?.id ?? "")") { await reload(reset: true) }
        .onReceive(NotificationCenter.default.publisher(for: .beansBilibiliLoginDidUpdate)) { _ in
            likedOverrides = [:]
            Task { await reload(reset: true) }
        }
        .sheet(isPresented: $showLogin) { BilibiliLoginSheet() }
        .sheet(isPresented: $composer) {
            BilibiliCommentComposer(aid: aid, root: root?.id) { Task { await reload(reset: true) } }
        }
        .sheet(item: $route) { BilibiliNativeSheet(route: $0) }
        .sheet(item: $thread) { reply in
            BeansNavigationStack {
                AnyView(BilibiliNativeComments(aid: aid, root: reply))
                    .navigationTitle("评论回复").navigationBarTitleDisplayMode(.inline)
            }
        }
        .alert("操作未完成", isPresented: Binding(get: { mutationError != nil }, set: { if !$0 { mutationError = nil } })) {
            Button("知道了") { mutationError = nil }
        } message: { Text(mutationError ?? "") }
    }
    private func replyRow(_ reply: BilibiliReply, isRoot: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { route = .up(reply.author) } label: { CoverImage(url: reply.author.coverURL, size: 36, cornerRadius: 18) }
                .buttonStyle(.plain).accessibilityLabel("打开\(reply.author.name)主页")
            VStack(alignment: .leading, spacing: 7) {
                Button { route = .up(reply.author) } label: {
                    Text(reply.author.name).font(BeansFont.appFont(13, .medium)).foregroundStyle(Color.beansComment)
                }.buttonStyle(.plain)
                Text(reply.message).font(BeansFont.appFont(15)).foregroundStyle(Color.beansLabel)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                HStack(spacing: 16) {
                    Text(beansCommentDate(reply.date)).font(.caption2).foregroundStyle(Color.beansComment)
                    Spacer(minLength: 0)
                    let liked = likedOverrides[reply.id] ?? reply.liked
                    Button { like(reply, current: liked) } label: {
                        Label("\(max(0, reply.likeCount + (liked == reply.liked ? 0 : liked ? 1 : -1)))", systemImage: liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.caption).foregroundStyle(liked ? Color.beansAmber : Color.beansComment)
                    }.disabled(mutation != nil).buttonStyle(.plain).frame(minHeight: 32)
                }
                if !isRoot && root == nil && reply.replyCount > 0 {
                    Button("查看 \(reply.replyCount) 条回复") { thread = reply }.font(.caption)
                }
                if !isRoot && root == nil && reply.replyCount == 0 {
                    Button("回复") { thread = reply }.font(.caption)
                }
            }
        }
    }
    private func reload(reset: Bool) async { await store.load(aid: aid, hot: hot, root: root?.id, reset: reset) }
    private func like(_ reply: BilibiliReply, current: Bool) {
        guard account.isLoggedIn else { showLogin = true; return }
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
    let onSent: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var sending = false
    @State private var error: String?
    @FocusState private var focused: Bool
    var body: some View {
        BeansNavigationStack {
            VStack(alignment: .leading, spacing: 12) {
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
                                try await BilibiliAPI.shared.nativeComment(aid: aid, message: text, root: root)
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
