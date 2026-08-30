import SwiftUI

// MARK: - 本地音乐库区块（音乐库页面顶部：本机歌单，可新建 / 播放 / 添加歌曲）

struct LocalMusicSection: View {
    private enum SyncTarget: String, CaseIterable, Identifiable {
        case netease = "网易云音乐"
        case qq = "QQ音乐"
        case kugou = "酷狗音乐"
        case all = "全部平台"

        var id: String { rawValue }
    }

    @ObservedObject private var store = LocalLibraryStore.shared
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var favorites: FavoritesStore

    @State private var showCreate = false
    @State private var newName = ""
    @State private var selected: LocalPlaylist?
    @State private var syncing = false
    @State private var syncMessage = ""
    @State private var showSyncPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("本地音乐库")
                    .font(BeansFont.appFont(21, .bold))
                    .foregroundStyle(Color.beansLabel)
                Spacer(minLength: 8)
                Button {
                    newName = ""
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.beansAmber)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新建本地歌单")
                .help("新建本地歌单")
            }
            VStack(alignment: .leading, spacing: 6) {
                GlassButton(
                    title: syncing ? "正在同步歌单…" : "一键同步歌单",
                    systemName: "arrow.triangle.2.circlepath",
                    prominent: true
                ) {
                    showSyncPicker = true
                }
                .disabled(syncing)
                Text("选择平台后，将喜欢歌曲同步到对应的本地歌单")
                    .font(BeansFont.appFont(11))
                    .foregroundStyle(Color.beansComment)
            }
            if !syncMessage.isEmpty {
                Text(syncMessage)
                    .font(BeansFont.appFont(12, .medium))
                    .foregroundStyle(Color.beansSage)
            }
            if store.playlists.isEmpty {
                EmptyStateView(icon: "internaldrive", text: "还没有本地歌单\n新建一个歌单，把喜欢的歌曲收藏到本机")
            } else {
                VStack(spacing: 0) {
                    ForEach(store.playlists) { playlist in
                        Button {
                            selected = playlist
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(LinearGradient(colors: [Color.beansAmber.opacity(0.75), Color.beansAmber.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 56, height: 56)
                                    Image(systemName: "music.note.list")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(playlist.name)
                                        .font(BeansFont.appFont(15, .medium))
                                        .foregroundStyle(Color.beansLabel)
                                        .lineLimit(1)
                                    Text("\(playlist.songs.count) 首 · 本机")
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
                            Button(role: .destructive) {
                                BeansHaptics.tap()
                                store.deletePlaylist(id: playlist.id)
                                ToastCenter.shared.show("已删除本地歌单")
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
        .alert("新建本地歌单", isPresented: $showCreate) {
            TextField("歌单名称", text: $newName)
            Button("创建") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                let playlist = store.createPlaylist(name: name)
                selected = playlist
                newName = ""
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("本地歌单保存在设备上，覆盖安装不会丢失，不依赖平台账号")
        }
        .confirmationDialog("选择要同步的平台", isPresented: $showSyncPicker, titleVisibility: .visible) {
            Button("网易云音乐") { Task { await sync(target: .netease) } }
            Button("QQ音乐") { Task { await sync(target: .qq) } }
            Button("酷狗音乐") { Task { await sync(target: .kugou) } }
            Button("全部平台") { Task { await sync(target: .all) } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("选择后会创建或更新对应的本地歌单")
        }
        .sheet(item: $selected) { playlist in
            LocalPlaylistDetailSheet(playlistID: playlist.id)
                .environmentObject(player)
                .environmentObject(auth)
        }
    }

    private func sync(target: SyncTarget) async {
        guard !syncing else { return }
        syncing = true
        syncMessage = ""
        var songs: [Song] = []
        var details: [String] = []
        if target == .netease || target == .all, let user = auth.user, auth.isLoggedIn {
            do {
                let lists = try await NetEaseAPI.shared.userPlaylists(uid: user.uid)
                let liked = lists.first { list in
                    let name = list.name.replacingOccurrences(of: " ", with: "")
                    return name.contains("喜欢") || name.contains("我喜欢")
                }
                if let liked {
                    let neteaseSongs = try await NetEaseAPI.shared.playlistTracks(id: liked.id)
                    songs.append(contentsOf: neteaseSongs)
                    details.append("网易云 \(neteaseSongs.count) 首")
                } else {
                    details.append("网易云未找到喜欢歌单")
                }
            } catch {
                BeansLogger.shared.log("三平台同步：网易云失败 \(error.localizedDescription)", level: .error)
                details.append("网易云请求失败")
            }
        } else if target == .netease || target == .all {
            details.append("网易云未登录")
        }
        if (target == .netease || target == .all), !favorites.neteaseFavoriteSongs.isEmpty {
            let cachedIDs = Set(songs.filter { $0.source == .netease }.map(\.id))
            let cached = favorites.neteaseFavoriteSongs.filter { !cachedIDs.contains($0.id) }
            songs.append(contentsOf: cached)
            if !cached.isEmpty { details.append("网易云缓存补充 \(cached.count) 首") }
        }
        if target == .qq || target == .all, QQMusicAuth.shared.isLoggedIn {
            do {
                let qqSongs = try await QQMusicAPI.shared.favoriteSongs(limit: 300)
                songs.append(contentsOf: qqSongs)
                details.append("QQ音乐 \(qqSongs.count) 首")
            } catch {
                BeansLogger.shared.log("三平台同步：QQ音乐失败 \(error.localizedDescription)", level: .error)
                details.append("QQ音乐请求失败")
            }
        } else if target == .qq || target == .all {
            details.append("QQ音乐未登录")
        }
        if target == .kugou || target == .all, KugouMusicAuth.shared.isLoggedIn {
            do {
                let lists = try await KugouMusicAPI.shared.userPlaylists()
                BeansLogger.shared.log("三平台同步：酷狗歌单 \(lists.map(\.name).joined(separator: "|"))", level: .info)
                let liked = lists.first { list in
                    let name = list.name.replacingOccurrences(of: " ", with: "")
                    return name.contains("喜欢") || name.contains("收藏") || name.contains("红心")
                }
                if let liked {
                    let kugouSongs = try await KugouMusicAPI.shared.playlistSongs(listID: liked.id)
                    songs.append(contentsOf: kugouSongs)
                    details.append("酷狗音乐 \(kugouSongs.count) 首")
                } else {
                    details.append("酷狗音乐未找到喜欢歌单")
                }
            } catch {
                BeansLogger.shared.log("三平台同步：酷狗音乐失败 \(error.localizedDescription)", level: .error)
                details.append("酷狗音乐请求失败")
            }
        } else if target == .kugou || target == .all {
            details.append("酷狗音乐未登录")
        }
        var unique: [Song] = []
        var seen = Set<String>()
        for song in songs where seen.insert(song.identityKey).inserted { unique.append(song) }
        let playlistName: String
        switch target {
        case .netease: playlistName = "网易云喜欢"
        case .qq: playlistName = "QQ音乐喜欢"
        case .kugou: playlistName = "酷狗音乐喜欢"
        case .all: playlistName = "三平台喜欢"
        }
        let added = store.syncSongs(unique, intoPlaylistNamed: playlistName)
        syncing = false
        syncMessage = details.joined(separator: "，") + "；合计 \(unique.count) 首"
        ToastCenter.shared.show(unique.isEmpty ? "没有获取到该平台的喜欢歌曲" : "已同步 \(unique.count) 首，新增 \(added) 首到本地歌单“\(playlistName)”")
    }
}

// MARK: - 本地歌单详情（播放全部 / 单曲播放 / 移除歌曲 / 添加歌曲）

struct LocalPlaylistDetailSheet: View {
    @ObservedObject private var store = LocalLibraryStore.shared
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    let playlistID: UUID

    @State private var showSearchAdd = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var playlistSearchText = ""
    @State private var multiSelectMode = false
    @State private var selectedSongKeys: Set<String> = []
    @State private var showAddSelectedDestination = false

    private var playlist: LocalPlaylist? {
        store.playlists.first { $0.id == playlistID }
    }

    private var visibleSongs: [(offset: Int, element: Song)] {
        guard let playlist else { return [] }
        let keyword = playlistSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let songs = Array(playlist.songs.enumerated())
        guard !keyword.isEmpty else { return songs }
        return songs.filter { _, song in
            song.name.lowercased().contains(keyword)
                || song.artists.lowercased().contains(keyword)
                || song.album.lowercased().contains(keyword)
        }
    }

    var body: some View {
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                Group {
                if let playlist {
                    List {
                        Section {
                            HStack(spacing: 12) {
                                GlassButton(title: "播放全部", systemName: "play.fill", prominent: true) {
                                    let songs = visibleSongs.map(\.element)
                                    guard !songs.isEmpty else { return }
                                    player.play(songs: songs, startAt: 0)
                                }
                                GlassButton(title: "随机播放", systemName: "shuffle") {
                                    let songs = visibleSongs.map(\.element)
                                    guard !songs.isEmpty else { return }
                                    player.play(songs: songs.shuffled(), startAt: 0)
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                        Section {
                            if visibleSongs.isEmpty {
                                EmptyStateView(icon: "magnifyingglass", text: "没有找到匹配歌曲")
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            } else {
                                ForEach(visibleSongs, id: \.element.identityKey) { index, song in
                                    if multiSelectMode {
                                        HStack(spacing: 10) {
                                            Image(systemName: selectedSongKeys.contains(song.identityKey) ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(selectedSongKeys.contains(song.identityKey) ? Color.beansAmber : Color.beansComment)
                                            SongCell(song: song, glassRow: true) {
                                                toggleSelection(song)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            toggleSelection(song)
                                        }
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                    } else {
                                        SongCell(song: song, glassRow: true, playbackContext: playlist.songs, playbackIndex: index) {
                                            player.play(songs: playlist.songs, startAt: index)
                                        }
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                BeansHaptics.tap()
                                                store.removeSong(playlistID: playlistID, songIdentity: song.identityKey)
                                            } label: {
                                                Label("移除", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .beansScrollContentBackgroundHidden()
                    .listStyle(.plain)
                    .searchable(text: $playlistSearchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索本地歌单歌曲")
                } else {
                    EmptyStateView(icon: "music.note.list", text: "歌单不存在或已删除")
                }
            }
            }
            .navigationTitle(playlist?.name ?? "本地歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            multiSelectMode.toggle()
                            if !multiSelectMode {
                                selectedSongKeys.removeAll()
                            }
                        } label: {
                            Label(multiSelectMode ? "退出多选" : "多选编辑", systemImage: multiSelectMode ? "xmark.circle" : "checklist")
                        }
                        if multiSelectMode {
                            Button(role: .destructive) {
                                removeSelectedSongs()
                            } label: {
                                Label("移除选中歌曲", systemImage: "trash")
                            }
                            .disabled(selectedSongKeys.isEmpty)
                            Button {
                                showAddSelectedDestination = true
                            } label: {
                                Label("添加到其他本地歌单", systemImage: "folder.badge.plus")
                            }
                            .disabled(selectedSongKeys.isEmpty || !hasOtherPlaylist)
                        }
                        Button {
                            if let song = player.currentSong {
                                store.addSong(song, to: playlistID)
                                BeansHaptics.success()
                                ToastCenter.shared.show("已加入本地歌单")
                            } else {
                                ToastCenter.shared.show("当前没有播放中的歌曲")
                            }
                        } label: {
                            Label("添加当前播放歌曲", systemImage: "plus.circle")
                        }
                        Button {
                            showSearchAdd = true
                        } label: {
                            Label("搜索添加歌曲", systemImage: "magnifyingglass")
                        }
                        Button {
                            renameText = playlist?.name ?? ""
                            showRename = true
                        } label: {
                            Label("重命名歌单", systemImage: "pencil")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
        }
        .sheet(isPresented: $showSearchAdd) {
            LocalSearchAddSheet(playlistID: playlistID)
                .environmentObject(player)
                .environmentObject(auth)
        }
        .alert("重命名歌单", isPresented: $showRename) {
            TextField("歌单名称", text: $renameText)
            Button("保存") {
                let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                store.renamePlaylist(id: playlistID, name: name)
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(
            "添加 \(selectedSongKeys.count) 首歌曲到其他本地歌单",
            isPresented: $showAddSelectedDestination,
            titleVisibility: .visible
        ) {
            ForEach(store.playlists.filter { $0.id != playlistID }) { target in
                Button(target.name) {
                    addSelectedSongs(to: target.id)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("已选歌曲会复制到目标歌单，当前歌单中的歌曲不会被移除。")
        }
        .modifier(BeansSheetModifier(detents: [.medium, .large], dragIndicator: true))
    }

    private var hasOtherPlaylist: Bool {
        store.playlists.contains { $0.id != playlistID }
    }

    private func toggleSelection(_ song: Song) {
        BeansHaptics.select()
        if selectedSongKeys.contains(song.identityKey) {
            selectedSongKeys.remove(song.identityKey)
        } else {
            selectedSongKeys.insert(song.identityKey)
        }
    }

    private func removeSelectedSongs() {
        guard !selectedSongKeys.isEmpty else { return }
        let count = selectedSongKeys.count
        selectedSongKeys.forEach { key in
            store.removeSong(playlistID: playlistID, songIdentity: key)
        }
        selectedSongKeys.removeAll()
        multiSelectMode = false
        BeansHaptics.success()
        ToastCenter.shared.show("已移除 \(count) 首歌曲")
    }

    private func addSelectedSongs(to destinationID: UUID) {
        guard let playlist else { return }
        let songs = playlist.songs.filter { selectedSongKeys.contains($0.identityKey) }
        let added = store.addSongs(songs, to: destinationID)
        selectedSongKeys.removeAll()
        multiSelectMode = false
        BeansHaptics.success()
        let targetName = store.playlists.first(where: { $0.id == destinationID })?.name ?? "目标歌单"
        ToastCenter.shared.show(added == songs.count
            ? "已添加 \(added) 首到「\(targetName)」"
            : "已添加 \(added) 首到「\(targetName)」（重复歌曲已跳过）")
    }
}

// MARK: - 本地歌单搜索添加（网易云 / QQ 音乐）

struct LocalSearchAddSheet: View {
    @ObservedObject private var store = LocalLibraryStore.shared
    @ObservedObject private var platformPrefs = PlatformPreferenceStore.shared
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    let playlistID: UUID
    @State private var keyword = ""
    @State private var results: [Song] = []
    @State private var searching = false
    @State private var provider: SearchProvider = .netease
    private var searchProviders: [SearchProvider] { platformPrefs.enabledSearchProviders }
    @State private var task: Task<Void, Never>?

    var body: some View {
        BeansNavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    TextField("输入歌名搜索", text: $keyword)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.beansGlassFill))
                        .submitLabel(.search)
                        .onSubmit { runSearch() }
                    Button {
                        runSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color.beansAmber))
                    }
                }
                .padding(12)
                Picker("平台", selection: $provider) {
                    ForEach(searchProviders) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                if searching {
                    Spacer()
                    ProgressView().tint(Color.beansAmber)
                    Spacer()
                } else if results.isEmpty {
                    Spacer()
                    Text("输入歌名搜索，点击结果加入本地歌单")
                        .font(BeansFont.appFont(13))
                        .foregroundStyle(Color.beansComment)
                    Spacer()
                } else {
                    List {
                        ForEach(Array(results.enumerated()), id: \.element.identityKey) { index, song in
                            SongCell(song: song, glassRow: true) {
                                store.addSong(song, to: playlistID)
                                BeansHaptics.success()
                                ToastCenter.shared.show("已加入本地歌单")
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("添加歌曲")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .modifier(BeansSheetModifier(detents: [.medium, .large], dragIndicator: true))
        .onAppear {
            provider = platformPrefs.ensureVisible(provider)
        }
        .onReceive(platformPrefs.changes) { _ in
            let next = platformPrefs.ensureVisible(provider)
            if next != provider { provider = next }
        }
    }

    private func runSearch() {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        task?.cancel()
        task = Task {
            searching = true
            defer { if !Task.isCancelled { searching = false } }
            do {
                let songs: [Song]
                switch provider {
                case .netease:
                    songs = try await NetEaseAPI.shared.search(keyword: trimmed, limit: 30)
                case .qq:
                    songs = try await QQMusicAPI.shared.searchSongs(keyword: trimmed)
                case .kugou:
                    songs = try await KugouMusicAPI.shared.searchSongs(keyword: trimmed)
                }
                guard !Task.isCancelled else { return }
                results = songs
            } catch {
                guard !Task.isCancelled else { return }
                ToastCenter.shared.show("搜索失败，请稍后再试")
            }
        }
    }

}


// MARK: - 加入本地歌单（播放页入口：选择已创建的本地歌单，或新建并加入）

struct AddToLocalPlaylistSheet: View {
    @ObservedObject private var store = LocalLibraryStore.shared
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    let song: Song
    @State private var showCreateField = false
    @State private var newName = ""
    @State private var message: String?

    var body: some View {
        let _ = theme.accent
        BeansNavigationStack {
            List {
                if store.playlists.isEmpty {
                    Text("还没有本地歌单，先创建一个吧")
                        .foregroundStyle(Color.beansComment)
                } else {
                    Section("选择本地歌单") {
                        ForEach(store.playlists) { playlist in
                            Button {
                                store.addSong(song, to: playlist.id)
                                BeansHaptics.success()
                                ToastCenter.shared.show("已加入「\(playlist.name)」")
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(LinearGradient(colors: [Color.beansAmber.opacity(0.75), Color.beansAmber.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .frame(width: 40, height: 40)
                                        Image(systemName: "music.note.list")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.white)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.name)
                                            .font(BeansFont.appFont(15, .medium))
                                            .foregroundStyle(Color.beansLabel)
                                            .lineLimit(1)
                                        Text("\(playlist.songs.count) 首 · 本机")
                                            .font(BeansFont.appFont(11))
                                            .foregroundStyle(Color.beansComment)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color.beansAmber)
                                }
                            }
                        }
                    }
                }

                if showCreateField {
                    Section("新建本地歌单") {
                        TextField("歌单名称", text: $newName)
                            .submitLabel(.done)
                        Button {
                            createAndAdd()
                        } label: {
                            Text("创建并加入")
                                .font(BeansFont.appFont(15, .semibold))
                                .foregroundStyle(Color.beansAmber)
                        }
                    }
                } else {
                    Section {
                        Button {
                            showCreateField = true
                        } label: {
                            Label("新建歌单并加入", systemImage: "plus.circle")
                        }
                    }
                }

                if let message {
                    Section {
                        Text(message)
                            .font(BeansFont.appFont(13))
                            .foregroundStyle(Color.beansSage)
                    }
                }
            }
            .navigationTitle("加入本地歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .modifier(BeansSheetModifier(detents: [.medium, .large], dragIndicator: true))
        .onAppear {
            if store.playlists.isEmpty {
                ToastCenter.shared.show(store.addToDefaultFavorites(song))
                BeansHaptics.success()
                dismiss()
            }
        }
    }

    private func createAndAdd() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let playlist = store.createPlaylist(name: name)
        store.addSong(song, to: playlist.id)
        BeansHaptics.success()
        ToastCenter.shared.show("已创建「\(name)」并加入")
        dismiss()
    }
}
