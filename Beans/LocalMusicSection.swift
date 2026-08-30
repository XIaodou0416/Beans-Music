import SwiftUI

// MARK: - 本地音乐库区块（音乐库页面顶部：本机歌单，可新建 / 播放 / 添加歌曲）

struct LocalMusicSection: View {
    @ObservedObject private var store = LocalLibraryStore.shared
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var favorites: FavoritesStore

    @State private var showCreate = false
    @State private var newName = ""
    @State private var selected: LocalPlaylist?
    @State private var syncing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "本地音乐库")
                Button {
                    Task { await syncAllLikes() }
                } label: {
                    Image(systemName: syncing ? "arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.beansAmber)
                        .rotationEffect(.degrees(syncing ? 360 : 0))
                        .animation(syncing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: syncing)
                }
                .buttonStyle(.plain)
                .disabled(syncing)
                .accessibilityLabel("一键同步三平台喜欢")
                Button {
                    newName = ""
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.beansAmber)
                }
                .buttonStyle(.plain)
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
        .sheet(item: $selected) { playlist in
            LocalPlaylistDetailSheet(playlistID: playlist.id)
                .environmentObject(player)
                .environmentObject(auth)
        }
    }

    private func syncAllLikes() async {
        guard !syncing else { return }
        syncing = true
        var songs: [Song] = []
        songs.append(contentsOf: favorites.neteaseFavoriteSongs)
        songs.append(contentsOf: favorites.qqFavoriteSongs)
        if let user = auth.user,
           let lists = try? await NetEaseAPI.shared.userPlaylists(uid: user.uid),
           let liked = lists.first(where: { $0.name == "我喜欢的音乐" }) {
            songs.append(contentsOf: (try? await NetEaseAPI.shared.playlistTracks(id: liked.id)) ?? [])
        }
        if QQMusicAuth.shared.isLoggedIn {
            songs.append(contentsOf: (try? await QQMusicAPI.shared.favoriteSongs(limit: 300)) ?? [])
        }
        if KugouMusicAuth.shared.isLoggedIn,
           let liked = (try? await KugouMusicAPI.shared.userPlaylists())?.first(where: {
               $0.name.contains("喜欢") || $0.name.contains("收藏")
           }) {
            songs.append(contentsOf: (try? await KugouMusicAPI.shared.playlistSongs(listID: liked.id)) ?? [])
        }
        var unique: [Song] = []
        var seen = Set<String>()
        for song in songs where seen.insert(song.identityKey).inserted { unique.append(song) }
        let added = store.syncSongs(unique)
        syncing = false
        ToastCenter.shared.show(unique.isEmpty ? "没有获取到已登录平台的喜欢歌曲" : "已同步 \(unique.count) 首，新增 \(added) 首到三平台喜欢")
    }
}

// MARK: - 本地歌单详情（播放全部 / 单曲播放 / 移除歌曲 / 添加歌曲）

struct LocalPlaylistDetailSheet: View {
    @ObservedObject private var store = LocalLibraryStore.shared
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    let playlistID: UUID

    @State private var showSearchAdd = false
    @State private var showRename = false
    @State private var renameText = ""

    private var playlist: LocalPlaylist? {
        store.playlists.first { $0.id == playlistID }
    }

    var body: some View {
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(ignoreCustomBackground: true)
                Group {
                if let playlist {
                    List {
                        Section {
                            HStack(spacing: 12) {
                                GlassButton(title: "播放全部", systemName: "play.fill", prominent: true) {
                                    guard !playlist.songs.isEmpty else { return }
                                    player.play(songs: playlist.songs, startAt: 0)
                                }
                                GlassButton(title: "随机播放", systemName: "shuffle") {
                                    guard !playlist.songs.isEmpty else { return }
                                    player.play(songs: playlist.songs.shuffled(), startAt: 0)
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                        Section {
                            ForEach(Array(playlist.songs.enumerated()), id: \.element.identityKey) { index, song in
                                SongCell(song: song, glassRow: true) {
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
                    .beansScrollContentBackgroundHidden()
                    .listStyle(.plain)
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
        .modifier(BeansSheetModifier(detents: [.medium, .large], dragIndicator: true))
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
