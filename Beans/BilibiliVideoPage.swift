import SwiftUI
import AVFoundation

struct BilibiliVideoPage: View {
    let song: Song
    @EnvironmentObject private var music: PlayerManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    @StateObject private var videoPlayer = BilibiliNativePlayer()
    @ObservedObject private var account = BilibiliAuth.shared
    @State private var detail: BilibiliVideoInfo?
    @State private var loadError: String?
    @State private var tab = 0
    @State private var quality = 64
    @State private var selectedPart: Song?
    @State private var expanded = false
    @State private var route: BilibiliNativeRoute?
    @State private var showLogin = false
    @State private var showCoins = false
    @State private var showFavorites = false
    @State private var interaction: BilibiliInteractionState?
    @State private var busy = false
    @State private var message: String?
    @State private var share = false
    @State private var savedProgress = 0.0
    @State private var presentingChild = false

    var body: some View {
        GeometryReader { geometry in
            let wide = sizeClass == .regular && geometry.size.width > geometry.size.height
            Group {
                if wide {
                    HStack(alignment: .top, spacing: 0) {
                        playback.frame(width: geometry.size.width * 0.56)
                        content.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(spacing: 0) { playback; content }
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("视频详情").navigationBarTitleDisplayMode(.inline)
        .task(id: song.identityKey) {
            music.pauseForBilibiliVideo()
            if selectedPart == nil { selectedPart = song }
            if !presentingChild { play() }
            if detail == nil { await load() }
        }
        .onDisappear { rememberPosition(); videoPlayer.stop() }
        .onChange(of: quality) { _ in rememberPosition(); play() }
        .onReceive(NotificationCenter.default.publisher(for: .beansBilibiliLoginDidUpdate)) { _ in Task { await updateInteraction() } }
        .sheet(item: $route, onDismiss: { presentingChild = false; play() }) { next in
            AnyView(BilibiliNativeSheet(route: next)).onAppear { presentingChild = true; rememberPosition(); videoPlayer.pause() }
        }
        .sheet(isPresented: $showLogin) { BilibiliLoginSheet() }
        .sheet(isPresented: $showFavorites) {
            if let detail {
                BilibiliFavoritePicker(aid: detail.aid) { Task { await updateInteraction() } }
            }
        }
        .sheet(isPresented: $share) { if let url = song.officialURL { ShareSheet(items: [url]) } }
        .confirmationDialog("选择投币数量", isPresented: $showCoins, titleVisibility: .visible) {
            Button("投 1 枚硬币") { coin(1) }
            Button("投 2 枚硬币") { coin(2) }
            Button("取消", role: .cancel) {}
        } message: { Text("将消耗当前B站账号的硬币，投币后不能撤回。") }
        .alert("操作提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("知道了") { message = nil }
        } message: { Text(message ?? "") }
    }
    private var playback: some View {
        VStack(spacing: 0) {
            BilibiliVideoSurface(model: videoPlayer, retry: play)
            HStack {
                Menu {
                    Button("流畅") { quality = 16 }
                    Button("高清") { quality = 64 }
                    Button("超清") { quality = 80 }
                } label: { Label(quality == 16 ? "流畅" : quality == 80 ? "超清" : "高清", systemImage: "gearshape") }
                Spacer()
                Button { videoPlayer.stop(); music.play(songs: [selectedPart ?? song]); message = "已切换到音频播放器" } label: {
                    Label("听视频", systemImage: "headphones")
                }
            }.font(.caption).padding(.horizontal, 16).frame(height: 40)
        }
    }
    private var content: some View {
        VStack(spacing: 0) {
            Picker("详情", selection: $tab) { Text("简介").tag(0); Text("评论").tag(1) }
                .pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 10)
            if let detail {
                if tab == 1 { BilibiliNativeComments(aid: detail.aid) }
                else { summary(detail) }
            } else if let loadError { BilibiliInlineError(message: loadError) { Task { await load() } } }
            else { ProgressView("加载视频信息").frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
    }
    private func summary(_ info: BilibiliVideoInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Button { expanded.toggle() } label: {
                    HStack(alignment: .top) {
                        Text(info.song.name).font(BeansFont.appFont(19, .semibold)).lineLimit(expanded ? nil : 2)
                        Spacer(minLength: 4)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption)
                    }.foregroundStyle(Color.beansLabel)
                }.buttonStyle(.plain)
                Text("\(BilibiliFeedVideo.countLabel(info.views)) 次播放 · \(info.published.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(Color.beansComment)
                if expanded && !info.description.isEmpty {
                    Text(info.description).font(.subheadline).foregroundStyle(Color.beansComment).textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    action("点赞", icon: interaction?.liked == true ? "hand.thumbsup.fill" : "hand.thumbsup", selected: interaction?.liked == true) { like() }
                    action("投币", icon: "c.circle", selected: (interaction?.coins ?? 0) > 0) {
                        if account.isLoggedIn { showCoins = true } else { showLogin = true }
                    }
                    action("收藏", icon: interaction?.favorited == true ? "star.fill" : "star", selected: interaction?.favorited == true) {
                        if account.isLoggedIn { showFavorites = true } else { showLogin = true }
                    }
                    action("评论", icon: "text.bubble", selected: false) { tab = 1 }
                    action("分享", icon: "square.and.arrow.up", selected: false) { share = true }
                }
                if busy { ProgressView().frame(maxWidth: .infinity) }
                Button { route = .up(info.owner) } label: {
                    HStack(spacing: 12) {
                        CoverImage(url: info.owner.coverURL, size: 46, cornerRadius: 23)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(info.owner.name).font(.headline).foregroundStyle(Color.beansLabel)
                            Text("查看UP主主页").font(.caption).foregroundStyle(Color.beansComment)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.beansComment)
                    }
                }.buttonStyle(.plain)
                if info.parts.count > 1 {
                    Text("分集（\(info.parts.count)）").font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(info.parts.enumerated()), id: \.element.identityKey) { index, part in
                                Button { savedProgress = 0; selectedPart = part; play() } label: {
                                    Text("P\(index + 1) · \(part.name)").font(.caption).lineLimit(1)
                                        .frame(maxWidth: 180).padding(12)
                                        .background(selectedPart?.identityKey == part.identityKey ? Color.beansAmber.opacity(0.18) : Color.beansGlassFill, in: RoundedRectangle(cornerRadius: 9))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                if let collection = info.collection {
                    Text("所属合集").font(.headline)
                    Button { route = .collection(collection) } label: { BilibiliCollectionRow(collection: collection) }.buttonStyle(.plain)
                }
            }.padding(16)
        }.refreshable { await load() }
    }
    private func action(_ title: String, icon: String, selected: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 7) { Image(systemName: icon).font(.system(size: 22)); Text(title).font(.caption) }
                .foregroundStyle(selected ? Color.beansAmber : Color.beansComment).frame(maxWidth: .infinity, minHeight: 58)
        }.buttonStyle(.plain).disabled(busy)
    }
    private func rememberPosition() {
        if let seconds = videoPlayer.player?.currentTime().seconds, seconds.isFinite { savedProgress = seconds }
    }
    private func play() {
        let part = selectedPart ?? song, value = quality
        music.pauseForBilibiliVideo()
        videoPlayer.open(resumeAt: savedProgress) { try await BilibiliAPI.shared.nativeVideoURLs(part, quality: value) }
    }
    private func load() async {
        loadError = nil
        do { detail = try await BilibiliAPI.shared.nativeVideo(song); await updateInteraction() }
        catch { loadError = error.localizedDescription }
    }
    private func updateInteraction() async {
        guard account.isLoggedIn, let detail else { interaction = nil; return }
        do { interaction = try await BilibiliAPI.shared.nativeInteraction(aid: detail.aid) }
        catch { interaction = nil }
    }
    private func like() {
        guard account.isLoggedIn else { showLogin = true; return }
        guard let detail, !busy else { return }
        guard let interaction else { message = "正在确认点赞状态，请下拉刷新后再操作"; return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                try await BilibiliAPI.shared.nativeLike(aid: detail.aid, liked: !interaction.liked)
                self.interaction?.liked = !interaction.liked
            } catch { message = error.localizedDescription; await updateInteraction() }
        }
    }
    private func coin(_ count: Int) {
        guard let detail, !busy else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do { try await BilibiliAPI.shared.nativeCoin(aid: detail.aid, count: count); message = "投币成功" }
            catch { message = "\(error.localizedDescription)。请刷新确认结果，勿重复投币。" }
            await updateInteraction()
        }
    }
}

struct BilibiliFavoritePicker: View {
    let aid: String
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var folders: [BilibiliFavoriteFolder] = []
    @State private var selected = Set<String>()
    @State private var original = Set<String>()
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        BeansNavigationStack {
            List {
                if loading { ProgressView("加载收藏夹") }
                if let error { Text(error).foregroundStyle(.red).font(.footnote); Button("重新加载") { Task { await load() } } }
                ForEach(folders) { folder in
                    Button {
                        if selected.contains(folder.id) { selected.remove(folder.id) } else { selected.insert(folder.id) }
                    } label: {
                        HStack { Text(folder.title).foregroundStyle(Color.beansLabel); Spacer(); Image(systemName: selected.contains(folder.id) ? "checkmark.circle.fill" : "circle") }
                    }.disabled(saving)
                }
                if !loading && folders.isEmpty && error == nil { Text("账号还没有收藏夹") }
            }
            .navigationTitle("选择收藏夹").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中" : "保存") {
                        saving = true; error = nil
                        Task { @MainActor in
                            defer { saving = false }
                            do {
                                try await BilibiliAPI.shared.nativeFavorite(aid: aid, add: selected.subtracting(original), remove: original.subtracting(selected))
                                onSaved(); dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }.disabled(loading || saving || folders.isEmpty)
                }
            }
        }.task { await load() }.interactiveDismissDisabled(saving)
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            folders = try await BilibiliAPI.shared.nativeFolders(aid: aid)
            original = Set(folders.filter(\.containsVideo).map(\.id)); selected = original
        } catch { self.error = error.localizedDescription }
    }
}
