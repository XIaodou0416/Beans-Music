import SwiftUI

enum LibraryProvider: String, CaseIterable, Identifiable {
    case netease = "网易云音乐"
    case qq = "QQ音乐"
    case kugou = "酷狗音乐"

    var id: String { rawValue }

    var tint: LinearGradient {
        switch self {
        case .netease:
            return LinearGradient(colors: [Color(red: 0.93, green: 0.22, blue: 0.16), Color(red: 0.80, green: 0.15, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .qq:
            return LinearGradient(colors: [Color(red: 0.15, green: 0.78, blue: 0.55), Color(red: 0.05, green: 0.58, blue: 0.42)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .kugou:
            return LinearGradient(colors: [Color(red: 0.12, green: 0.58, blue: 0.95), Color(red: 0.02, green: 0.32, blue: 0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var icon: String {
        switch self {
        case .netease: return "cloud.fill"
        case .qq: return "play.rectangle.fill"
        case .kugou: return "music.note"
        }
    }

    var brandImageName: String? {
        switch self {
        case .netease: return "BrandNetease"
        case .qq: return "BrandQQ"
        case .kugou: return "BrandKugou"
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var favorites: FavoritesStore
    @ObservedObject private var qqAuth = QQMusicAuth.shared
    @ObservedObject private var kugouAuth = KugouMusicAuth.shared
    @ObservedObject private var platformPrefs = PlatformPreferenceStore.shared

    @State private var showHistory = false
    @State private var showSectionSort = false
    /// 音乐库板块顺序（本地音乐库 / 我的歌单 / 最近播放，可自定义）
    @State private var libraryOrder = SectionOrderStore.load(SectionOrderStore.libraryKey, defaults: SectionOrderStore.libraryDefaults)
    @State private var selectedPlaylist: Playlist?
    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var pendingDelete: Playlist?
    @State private var showDeleteConfirm = false
    @State private var source: LibraryProvider = .netease
    @AppStorage("beans.homeHeaderHideSort") private var hideSortButton = false
    @AppStorage(PlatformPreferenceStore.hidePickerKey) private var hidePlatformPicker = false
    @State private var qqPlaylists: [Playlist] = []
    @State private var qqLoading = false
    @State private var qqSavedAt = Date.distantPast
    @State private var kugouPlaylists: [Playlist] = []
    @State private var kugouLoading = false
    @State private var kugouSavedAt = Date.distantPast
    @AppStorage("beans.uiStyle") private var uiStyleRaw = BeansUIStyle.liquid.rawValue
    private var libraryProviders: [LibraryProvider] { platformPrefs.enabledLibraryProviders }

    private var isNativeClean: Bool {
        BeansUIStyle(rawValue: uiStyleRaw) == .nativeClean
    }

    var body: some View {
        let _ = theme.accent
        ZStack {
            // 页面背景：同步开启时显示壁纸/背景色，否则默认氛围渐变
            GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
            // 实例级 UITabBar 清透风格（固定全透明，无需调节）
            TabBarAppearanceConfigurator()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: isNativeClean ? 30 : 24) {
                    if isNativeClean {
                        appleHeader
                    } else {
                        header
                    }
                    if !hidePlatformPicker {
                        providerPicker
                    }
                    // 板块按用户自定义顺序渲染（可拖拽排序）
                    ForEach(libraryOrder, id: \.self) { key in
                        switch key {
                        case "本地音乐库":
                            LocalMusicSection()
                        case "我的歌单":
                            switch source {
                            case .netease: playlistsSection
                            case .qq: qqSection
                            case .kugou: kugouSection
                            }
                        case "最近播放":
                            historySection
                        default:
                            EmptyView()
                        }
                    }
                }
                .padding(.horizontal, isNativeClean ? 24 : 16)
                .padding(.top, isNativeClean ? 20 : 8)
                .padding(.bottom, 190)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
            .beansScrollIndicatorsHidden()
            .refreshable {
                await refreshCurrentSource(force: true)
            }
        }
        .task {
            source = platformPrefs.ensureVisible(source)
        }
        .task(id: source) {
            await refreshCurrentSource(force: false)
        }
        .onAppear {
            source = platformPrefs.ensureVisible(source)
        }
        .onReceive(platformPrefs.changes) { _ in
            let next = platformPrefs.ensureVisible(source)
            if next != source { source = next }
        }
        .onReceive(NotificationCenter.default.publisher(for: .beansNeteaseLoginDidUpdate)) { _ in
            guard platformPrefs.isEnabled(SearchProvider.netease) else { return }
            source = .netease
            Task { await auth.loadLibrary() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .beansQQLoginDidUpdate)) { _ in
            guard platformPrefs.isEnabled(SearchProvider.qq) else { return }
            source = .qq
            Task { await loadQQPlaylists(force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .beansKugouLoginDidUpdate)) { _ in
            guard platformPrefs.isEnabled(SearchProvider.kugou) else { return }
            source = .kugou
            Task { await loadKugouPlaylists(force: true) }
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .environmentObject(player)
                .environmentObject(auth)
                .environmentObject(theme)
        }
        .sheet(isPresented: $showSectionSort) {
            SectionOrderSheet(
                title: "音乐库板块排序",
                sections: SectionOrderStore.libraryDefaults,
                order: $libraryOrder,
                platformOrder: Binding(
                    get: { platformPrefs.orderedRaw },
                    set: { platformPrefs.orderedRaw = $0 }
                )
            )
                .onDisappear { SectionOrderStore.save(SectionOrderStore.libraryKey, libraryOrder) }
        }
        .sheet(item: $selectedPlaylist) { playlist in
            PlaylistView(playlist: playlist)
                .environmentObject(player)
                .environmentObject(auth)
                .environmentObject(theme)
        }
        .alert("新建歌单", isPresented: $showCreatePlaylist) {
            TextField("歌单名称", text: $newPlaylistName)
            Button("创建") { createPlaylist() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("输入歌单名称，创建后同步到\(source.rawValue)")
        }
        .confirmationDialog("确定删除歌单「\(pendingDelete?.name ?? "")」吗？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) { confirmDeletePlaylist() }
            Button("取消", role: .cancel) {}
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("音乐库")
                        .font(BeansFont.appFont(isNativeClean ? 34 : 30, .bold))
                        .foregroundStyle(Color.beansLabel)
                    Text(librarySubtitle)
                        .font(BeansFont.appFont(13))
                        .foregroundStyle(Color.beansComment)
                }
                Spacer()
                HStack(spacing: 10) {
                if !hideSortButton {
                    GlassIconButton(systemName: "arrow.up.arrow.down") {
                        BeansHaptics.tap()
                        showSectionSort = true
                    }
                }
                }
            }
        }
        .padding(.top, 8)
    }

    private var appleHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center) {
                Text("音乐库")
                    .font(BeansFont.appFont(38, .bold))
                    .foregroundStyle(Color.beansLabel)
                Spacer(minLength: 12)
                if !hideSortButton {
                    GlassIconButton(systemName: "arrow.up.arrow.down") {
                        BeansHaptics.tap()
                        showSectionSort = true
                    }
                }
            }
            Text(librarySubtitle)
                .font(BeansFont.appFont(12, .medium))
                .foregroundStyle(Color.beansComment)
                .lineLimit(1)
            Rectangle()
                .fill(Color.beansLabel.opacity(0.10))
                .frame(height: 1)
        }
        .padding(.top, 4)
    }

    private var librarySubtitle: String {
        switch source {
        case .netease: return "网易云音乐歌单"
        case .qq: return "QQ 音乐收藏与歌单"
        case .kugou: return "酷狗云端歌单"
        }
    }


    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "我的歌单", trailing: auth.isLoggedIn ? "新建" : nil) {
                if auth.isLoggedIn {
                    BeansHaptics.tap()
                    newPlaylistName = ""
                    showCreatePlaylist = true
                }
            }
            if !auth.isLoggedIn {
                EmptyStateView(icon: "music.note.list", text: "登录网易云音乐后即可查看你的歌单")
            } else if auth.playlists.isEmpty {
                createPlaylistCard
            } else {
                VStack(spacing: 0) {
                    ForEach(auth.playlists) { playlist in
                        Button {
                            selectedPlaylist = playlist
                        } label: {
                            HStack(spacing: 12) {
                                CoverImage(url: playlist.coverURL, size: 56, cornerRadius: 12)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(playlist.name)
                                        .font(BeansFont.appFont(15, .medium))
                                        .foregroundStyle(Color.beansLabel)
                                        .lineLimit(1)
                                    Text("\(playlist.trackCount) 首")
                                        .font(BeansFont.appFont(12))
                                        .foregroundStyle(Color.beansComment)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.beansComment.opacity(0.6))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                BeansHaptics.tap()
                                requestDelete(playlist)
                            } label: {
                                Label("删除歌单", systemImage: "trash")
                            }
                        }
                        Divider().overlay(Color.beansComment.opacity(0.12))
                    }
                    // 新建歌单行
                    Button {
                        BeansHaptics.tap()
                        newPlaylistName = ""
                        showCreatePlaylist = true
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
                                    .foregroundStyle(Color.beansComment.opacity(0.45))
                                    .frame(width: 56, height: 56)
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(Color.beansComment)
                            }
                            Text("新建歌单")
                                .font(BeansFont.appFont(15, .medium))
                                .foregroundStyle(Color.beansComment)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6)
                .background {
                                        BeansGlass(shape: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .beansCardShadow(radius: 9, y: 3)
            }
        }
    }

    private var createPlaylistCard: some View {
        Button {
            BeansHaptics.tap()
            newPlaylistName = ""
            showCreatePlaylist = true
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .foregroundStyle(Color.beansComment.opacity(0.45))
                        .frame(width: 160, height: 160)
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.beansComment)
                }
                Text("新建歌单")
                    .font(BeansFont.appFont(12, .medium))
                    .foregroundStyle(Color.beansComment)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background {
                                BeansGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .buttonStyle(.plain)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "最近播放", trailing: "查看全部") {
                showHistory = true
            }
            if player.history.isEmpty {
                EmptyStateView(icon: "clock.arrow.circlepath", text: "暂无播放记录")
            } else {
                VStack(spacing: 0) {
                    ForEach(player.history.prefix(5), id: \.identityKey) { song in
                        SongCell(song: song, suppressNativeCleanRowGlass: isNativeClean) {
                            playFromHistory(song)
                        }
                        Divider().overlay(Color.beansComment.opacity(0.15))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background {
                                        BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .beansCardShadow(radius: 8, y: 3)
            }
        }
    }

    /// 平台选择（网易云 / QQ音乐，样式与主页一致）
    private var providerPicker: some View {
        HStack(spacing: 4) {
            ForEach(libraryProviders) { p in
                Button {
                    BeansHaptics.tap()
                    if source != p { source = p }
                } label: {
                    HStack(spacing: 6) {
                        if let brandImageName = p.brandImageName {
                            Image(brandImageName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: p.icon)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(LocalizedStringKey(p.rawValue))
                            .font(BeansFont.appFont(13, .semibold))
                    }
                    .foregroundStyle(source == p ? Color.white : Color.beansComment)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if source == p {
                            Capsule().fill(p.tint)
                        } else {
                            Capsule().fill(.clear)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
                .background { BeansSurface(shape: Capsule()) }
                .clipShape(Capsule())
        .beansCardShadow(radius: isNativeClean ? 1 : 6, y: isNativeClean ? 0.5 : 2)
    }

    private func refreshCurrentSource(force: Bool) async {
        switch source {
        case .netease:
            await auth.loadLibrary()
        case .qq:
            await loadQQPlaylists(force: force)
        case .kugou:
            await loadKugouPlaylists(force: force)
        }
    }

    /// QQ 模式整体内容：用户歌单（创建 + 收藏同步）
    private var qqSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            qqPlaylistsSection
        }
    }

    /// 酷狗模式整体内容：只保留同步歌单
    private var kugouSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            kugouPlaylistsSection
        }
    }

    /// 我的 QQ 歌单（登录后从 QQ 音乐拉取）
    private var qqPlaylistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "我的 QQ 歌单", trailing: qqAuth.isLoggedIn ? (qqPlaylists.isEmpty ? "新建" : "新建 · \(qqPlaylists.count) 个") : nil) {
                if qqAuth.isLoggedIn {
                    BeansHaptics.tap()
                    newPlaylistName = ""
                    showCreatePlaylist = true
                }
            }
            if !qqAuth.isLoggedIn {
                EmptyStateView(icon: "music.note.list", text: "登录 QQ 音乐后即可查看你的歌单")
            } else if qqLoading {
                LoadingStateView()
            } else if qqPlaylists.isEmpty {
                EmptyStateView(icon: "music.note.list", text: "暂无 QQ 歌单")
            } else {
                VStack(spacing: 0) {
                    ForEach(qqPlaylists) { playlist in
                        Button {
                            selectedPlaylist = playlist
                        } label: {
                            HStack(spacing: 12) {
                                CoverImage(url: playlist.coverURL, size: 56, cornerRadius: 12)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(playlist.name)
                                        .font(BeansFont.appFont(15, .medium))
                                        .foregroundStyle(Color.beansLabel)
                                        .lineLimit(1)
                                    Text("\(playlist.trackCount) 首")
                                        .font(BeansFont.appFont(12))
                                        .foregroundStyle(Color.beansComment)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.beansComment.opacity(0.6))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                BeansHaptics.tap()
                                requestDelete(playlist)
                            } label: {
                                Label("删除歌单", systemImage: "trash")
                            }
                        }
                        Divider().overlay(Color.beansComment.opacity(0.12))
                    }
                }
                .padding(.vertical, 6)
                .background {
                                        BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .beansCardShadow(radius: 8, y: 3)
            }
        }
    }

    private var kugouPlaylistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "我的酷狗歌单", trailing: kugouAuth.isLoggedIn ? "\(kugouPlaylists.count) 个" : nil)
            if !kugouAuth.isLoggedIn {
                EmptyStateView(icon: "music.note.list", text: "登录酷狗音乐后即可同步云端歌单")
            } else if kugouLoading {
                LoadingStateView()
            } else if kugouPlaylists.isEmpty {
                EmptyStateView(icon: "music.note.list", text: "暂未同步到酷狗歌单，下拉刷新试试")
            } else {
                VStack(spacing: 0) {
                    ForEach(kugouPlaylists) { playlist in
                        Button {
                            selectedPlaylist = playlist
                        } label: {
                            HStack(spacing: 12) {
                                CoverImage(url: playlist.coverURL, size: 56, cornerRadius: 12)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(playlist.name)
                                        .font(BeansFont.appFont(15, .medium))
                                        .foregroundStyle(Color.beansLabel)
                                        .lineLimit(1)
                                    Text("\(playlist.trackCount) 首")
                                        .font(BeansFont.appFont(12))
                                        .foregroundStyle(Color.beansComment)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.beansComment.opacity(0.6))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(Color.beansComment.opacity(0.12))
                    }
                }
                .padding(.vertical, 6)
                .background {
                    BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .beansCardShadow(radius: 8, y: 3)
            }
        }
    }

    // MARK: - 歌单新建 / 删除

    private func loadQQPlaylists(force: Bool = false) async {
        guard qqAuth.isLoggedIn else {
            qqPlaylists = []
            qqLoading = false
            return
        }
        // 会话内短缓存：5 分钟内不重复拉取，避免每次打开界面都重新加载（下拉可强制刷新）
        if !force, !qqPlaylists.isEmpty, Date().timeIntervalSince(qqSavedAt) < 300 { return }
        qqLoading = true
        let list = (try? await QQMusicAPI.shared.userPlaylists(uin: qqAuth.uin)) ?? []
        qqPlaylists = list
        await favorites.syncQQFromCloud()
        if !list.isEmpty { qqSavedAt = Date() }
        qqLoading = false
        // 封面兜底：歌单封面缺失时默认取第一首歌曲封面（列表先展示，封面后台补齐）
        if !list.isEmpty { await fillQQPlaylistCovers(list) }
    }

    private func loadKugouPlaylists(force: Bool = false) async {
        guard kugouAuth.isLoggedIn else {
            kugouPlaylists = []
            kugouLoading = false
            return
        }
        if !force, !kugouPlaylists.isEmpty, Date().timeIntervalSince(kugouSavedAt) < 300 { return }
        kugouLoading = true
        do {
            let list = try await KugouMusicAPI.shared.userPlaylists()
            kugouPlaylists = list
            if !list.isEmpty { kugouSavedAt = Date() }
        } catch {
            BeansLogger.shared.log("酷狗歌单同步失败：\(error.localizedDescription)", level: .error)
            kugouPlaylists = []
        }
        kugouLoading = false
    }

    private func fillQQPlaylistCovers(_ list: [Playlist]) async {
        let missing = list.filter { $0.coverURL == nil }
        guard !missing.isEmpty else { return }
        var covers: [Int: URL] = [:]
        await withTaskGroup(of: (Int, URL?).self) { group in
            for playlist in missing {
                group.addTask {
                    let cover = try? await QQMusicAPI.shared.firstSongCover(listID: playlist.id)
                    return (playlist.id, cover)
                }
            }
            for await (id, url) in group {
                if let url { covers[id] = url }
            }
        }
        for i in qqPlaylists.indices where qqPlaylists[i].coverURL == nil {
            if let url = covers[qqPlaylists[i].id] { qqPlaylists[i].coverURL = url }
        }
    }

    private func createPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            ToastCenter.shared.show("请输入歌单名称")
            return
        }
        switch source {
        case .netease:
            guard auth.isLoggedIn else {
                ToastCenter.shared.show("请先登录后再创建歌单")
                return
            }
            Task {
                do {
                    _ = try await NetEaseAPI.shared.createPlaylist(name: name)
                    ToastCenter.shared.show("歌单「\(name)」已创建")
                    newPlaylistName = ""
                    await auth.loadLibrary()
                } catch {
                    ToastCenter.shared.show("创建失败：\(error.localizedDescription)")
                }
            }
        case .qq:
            guard qqAuth.isLoggedIn else {
                ToastCenter.shared.show("请先登录 QQ 音乐后再创建歌单")
                return
            }
            Task {
                do {
                    let ok = try await QQMusicAPI.shared.createPlaylist(name: name)
                    if ok {
                        ToastCenter.shared.show("歌单「\(name)」已创建")
                        newPlaylistName = ""
                        await loadQQPlaylists(force: true)
                    } else {
                        ToastCenter.shared.show("创建失败，请确认已登录 QQ 音乐")
                    }
                } catch {
                    ToastCenter.shared.show("创建失败：\(error.localizedDescription)")
                }
            }
        case .kugou:
            ToastCenter.shared.show("酷狗歌单暂不支持新建")
        }
    }

    private func requestDelete(_ playlist: Playlist) {
        pendingDelete = playlist
        showDeleteConfirm = true
    }

    private func confirmDeletePlaylist() {
        guard let playlist = pendingDelete else { return }
        switch source {
        case .netease:
            Task {
                do {
                    let ok = try await NetEaseAPI.shared.deletePlaylist(id: playlist.id)
                    if ok {
                        ToastCenter.shared.show("已删除歌单「\(playlist.name)」")
                        await auth.loadLibrary()
                    } else {
                        ToastCenter.shared.show("删除失败，请稍后再试")
                    }
                } catch {
                    ToastCenter.shared.show("删除失败：\(error.localizedDescription)")
                }
            }
        case .qq:
            Task {
                do {
                    let ok = try await QQMusicAPI.shared.deletePlaylist(dirid: playlist.id)
                    if ok {
                        ToastCenter.shared.show("已删除歌单「\(playlist.name)」")
                        await loadQQPlaylists(force: true)
                    } else {
                        ToastCenter.shared.show("删除失败，请确认已登录 QQ 音乐")
                    }
                } catch {
                    ToastCenter.shared.show("删除失败：\(error.localizedDescription)")
                }
            }
        case .kugou:
            ToastCenter.shared.show("酷狗歌单暂不支持删除")
        }
    }

    private func playFromHistory(_ song: Song) {
        if let index = player.history.firstIndex(of: song) {
            player.play(songs: player.history, startAt: index)
        }
    }
}

