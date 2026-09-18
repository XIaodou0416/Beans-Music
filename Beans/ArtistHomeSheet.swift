import SwiftUI

// MARK: - 歌手主页（点击播放器顶部歌手名跳转：热门歌曲 + 专辑）

@MainActor
struct ArtistHomeSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.dismiss) private var dismiss
    let artistName: String
    var artistSource: SongSource = .netease
    var artistID: String?
    /// 从已有导航栈推入时不再创建嵌套 NavigationStack，也不应用 sheet 专用修饰器。
    var embeddedInNavigation = false

    init(artist: Artist, embeddedInNavigation: Bool = false) {
        self.artistName = artist.name
        self.artistSource = artist.source
        self.artistID = artist.id
        self.embeddedInNavigation = embeddedInNavigation
        _artist = State(initialValue: artist)
    }

    init(artistName: String, artistSource: SongSource = .netease, embeddedInNavigation: Bool = false) {
        self.artistName = artistName
        self.artistSource = artistSource
        self.artistID = nil
        self.embeddedInNavigation = embeddedInNavigation
        _artist = State(initialValue: nil)
    }

    @State private var artist: Artist?
    @State private var hotSongs: [Song] = []
    @State private var albums: [Album] = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var showBatchDownload = false
    @State private var selectedAlbum: Album?
    @State private var loadTask: Task<Void, Never>?
    @AppStorage(BeansBackendSettings.downloadUnlockKey) private var downloadFeatureUnlocked = false

    private var cacheKey: String {
        let identity = artistID?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? artistName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(artistSource.rawValue):\(identity)"
    }

    var body: some View {
        Group {
            if embeddedInNavigation {
                artistPage
            } else {
                BeansNavigationStack { artistPage }
                    .modifier(BeansSheetModifier(detents: [.large], dragIndicator: true))
            }
        }
        .onAppear {
            loadTask?.cancel()
            loadTask = Task { await load() }
        }
        .onDisappear {
            loadTask?.cancel()
        }
        .sheet(isPresented: $showBatchDownload) {
            BatchDownloadSheet(songs: displayedHotSongs, title: "下载歌手歌曲")
                .environmentObject(theme)
        }
        .sheet(item: $selectedAlbum) { album in
            AlbumDetailView(album: album)
                .environmentObject(player)
                .environmentObject(theme)
        }
    }

    @ViewBuilder
    private var artistPage: some View {
        ZStack {
            // 歌手页沿用主页壁纸，不受“同步到全部页面”开关影响。
            GlassBackdrop(customColor: theme.customBackground, homeMode: true)
            Group {
                if loading {
                    artistLoadingState
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) {
                        Task { await load() }
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            artistHeader
                            hotSongsSection
                            albumsSection
                        }
                        .padding(.top, 6)
                        .padding(.bottom, 16)
                    }
                    .beansScrollIndicatorsHidden()
                }
            }
        }
        .navigationTitle("歌手主页")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: beansLocalized("搜索歌手歌曲", "Search artist songs")
        )
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
    }

    private var artistHeader: some View {
        HStack(spacing: 14) {
            BeansAvatarView(remoteURL: artist?.coverURL, size: 72)
            .background(Color.beansGlassFill, in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(artist?.name ?? artistName)
                    .font(BeansFont.appFont(20, .bold))
                    .foregroundStyle(Color.beansLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                Text(beansLocalized("热门歌曲 \(hotSongs.count) 首 · 专辑 \(albums.count) 张", "Popular songs: \(hotSongs.count) · Albums: \(albums.count)"))
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansComment)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var artistLoadingState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    BeansShimmerSkeleton(cornerRadius: 36)
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 9) {
                        BeansShimmerSkeleton(cornerRadius: 6)
                            .frame(width: 150, height: 18)
                        BeansShimmerSkeleton(cornerRadius: 5)
                            .frame(width: 180, height: 12)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)

                BeansShimmerSkeleton(cornerRadius: 7)
                    .frame(width: 86, height: 18)
                    .padding(.horizontal, 16)

                HStack(spacing: 10) {
                    BeansShimmerSkeleton(cornerRadius: 16)
                        .frame(height: 38)
                    BeansShimmerSkeleton(cornerRadius: 16)
                        .frame(height: 38)
                }
                .padding(.horizontal, 16)

                BeansSongRowsLoadingState(rowCount: 8, coverSize: 40, showsRank: true, horizontalPadding: 16)
            }
            .padding(.top, 6)
            .padding(.bottom, 170)
        }
        .beansScrollIndicatorsHidden()
    }

    private var hotSongsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("热门歌曲")
                .font(BeansFont.appFont(17, .bold))
                .foregroundStyle(Color.beansLabel)
                .padding(.horizontal, 16)
            if !hotSongs.isEmpty {
                HStack(spacing: 12) {
                    GlassButton(title: "播放全部", systemName: "play.fill", prominent: true) {
                        BeansHaptics.tap()
                        player.play(songs: displayedHotSongs, startAt: 0)
                    }
                    GlassButton(title: "随机播放", systemName: "shuffle", forceLiquid: true) {
                        BeansHaptics.tap()
                        player.play(songs: displayedHotSongs.shuffled(), startAt: 0)
                    }
                    if downloadFeatureUnlocked, displayedHotSongs.count > 1 {
                        GlassIconButton(systemName: "arrow.down.to.line.compact", size: 44, forceLiquid: true) {
                            BeansHaptics.tap()
                            showBatchDownload = true
                        }
                        .accessibilityLabel("批量下载")
                        .help("批量下载")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 2)
            }
            if hotSongs.isEmpty {
                Text("暂无歌曲")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansComment)
                    .padding(.horizontal, 16)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(displayedHotSongs.enumerated()), id: \.element.identityKey) { index, song in
                        Button {
                            BeansHaptics.tap()
                            player.play(songs: displayedHotSongs, startAt: index)
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(BeansFont.appFont(13, .semibold, .rounded))
                                    .foregroundStyle(index < 3 ? Color.beansAmber : Color.beansComment)
                                    .frame(width: 22)
                                CoverImage(url: song.coverURL, song: song, size: 40, cornerRadius: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.name)
                                        .font(BeansFont.appFont(14, .medium))
                                        .foregroundStyle(Color.beansLabel)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                    Text(song.album)
                                        .font(BeansFont.appFont(11))
                                        .foregroundStyle(Color.beansComment)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                player.playNext(song)
                            } label: {
                                Label("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward")
                            }
                            Button {
                                player.play(songs: displayedHotSongs, startAt: index)
                            } label: {
                                Label("立即播放", systemImage: "play.fill")
                            }
                        }
                    }
                }
            }
        }
    }

    private var displayedHotSongs: [Song] {
        let kw = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !kw.isEmpty else { return hotSongs }
        return hotSongs.filter { song in
            song.name.lowercased().contains(kw)
                || song.artists.lowercased().contains(kw)
                || song.album.lowercased().contains(kw)
        }
    }

    private var albumsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("专辑")
                .font(BeansFont.appFont(17, .bold))
                .foregroundStyle(Color.beansLabel)
                .padding(.horizontal, 16)
            if albums.isEmpty {
                Text("暂无专辑")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansComment)
                    .padding(.horizontal, 16)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 12) {
                    ForEach(albums) { album in
                        Button {
                            openAlbum(album)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                CoverImage(url: album.coverURL, size: 88, cornerRadius: 12)
                                    .frame(maxWidth: .infinity)
                                Text(album.name)
                                    .font(BeansFont.appFont(11, .medium))
                                    .foregroundStyle(Color.beansLabel)
                                    .lineLimit(1)
                                if let count = album.trackCount {
                                    Text(beansSongCountText(count))
                                        .font(BeansFont.appFont(10))
                                        .foregroundStyle(Color.beansComment)
                                }
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background { BeansSurface(shape: RoundedRectangle(cornerRadius: 16, style: .continuous)) }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
            }
        }
    }

    private func openAlbum(_ album: Album) {
        BeansHaptics.tap()
        selectedAlbum = album
    }

    private func load() async {
        let cache = ArtistHomeCache.shared
        let cachedEntry = cache.cached(for: cacheKey)
        if let cached = cachedEntry {
            artist = cached.artist ?? artist
            hotSongs = cached.songs
            albums = cached.albums
            loading = false
            errorMessage = nil
            if cache.isFresh(cached), !BeansNetworkStatus.shared.isReachable {
                return
            }
        } else {
            loading = true
        }
        errorMessage = nil
        if artistSource == .qq {
            await loadQQArtist()
        } else if artistSource == .kugou {
            await loadKugouArtist()
        } else if artistSource == .kuwo || artistSource == .migu {
            await loadAdditionalCatalogArtist()
        } else {
            await loadNetEaseArtist()
        }
        // A transient catalog response must never replace a visible cached page with
        // empty sections. Keep the last successful section independently while the
        // other section refreshes in the background.
        if let cached = cachedEntry {
            if hotSongs.isEmpty, !cached.songs.isEmpty {
                hotSongs = cached.songs
            }
            if albums.isEmpty, !cached.albums.isEmpty {
                albums = cached.albums
            }
            if artist == nil {
                artist = cached.artist
            }
        }
        if !hotSongs.isEmpty || !albums.isEmpty {
            cache.save(artist: artist, songs: hotSongs, albums: albums, for: cacheKey)
        }
        loading = false
        if !hotSongs.isEmpty || !albums.isEmpty { errorMessage = nil }
    }

    private func loadNetEaseArtist() async {
        do {
            let id: Int
            if let artistID, let parsed = Int(artistID.replacingOccurrences(of: "netease-", with: "")), parsed > 0 {
                id = parsed
            } else {
                let artists = try await NetEaseAPI.shared.searchArtists(keyword: artistName, limit: 5)
                guard let first = artists.first else {
                    errorMessage = "未找到歌手「\(artistName)」"
                    loading = false
                    return
                }
                artist = first
                id = Int(first.id.replacingOccurrences(of: "netease-", with: "")) ?? 0
            }
            async let songsTask = (try? NetEaseAPI.shared.artistHotSongs(artistID: id, limit: 300)) ?? []
            async let albumsTask = (try? NetEaseAPI.shared.artistAlbums(artistID: id)) ?? []
            let fetchedSongs = await songsTask
            if !fetchedSongs.isEmpty {
                hotSongs = fetchedSongs
            }
            // 接口异常时兜底：分页搜索补全歌手歌曲（避免再次退回 30 首）。
            if fetchedSongs.isEmpty {
                var fallback: [Song] = []
                for offset in stride(from: 0, to: 300, by: 30) {
                    let page = (try? await NetEaseAPI.shared.search(keyword: artistName, limit: 30, offset: offset)) ?? []
                    if page.isEmpty { break }
                    fallback.append(contentsOf: page)
                    if page.count < 30 { break }
                }
                if !fallback.isEmpty {
                    hotSongs = fallback
                }
            }
            persistLoadedContent()
            let fetchedAlbums = await albumsTask
            if !fetchedAlbums.isEmpty {
                self.albums = fetchedAlbums
            }
            loading = false
        } catch {
            errorMessage = error.localizedDescription
            loading = false
        }
    }

    /// QQ 歌手：优先用歌手 mid 拉热门歌曲，失败则按歌手名搜索 QQ 歌曲（保证不是网易云数据）
    private func loadQQArtist() async {
        async let albumsTask = searchedAlbumsForCurrentArtist()
        var mid: String? = nil
        if let artistID, !artistID.hasPrefix("qq-") {
            mid = artistID
        } else if let first = (try? await QQMusicAPI.shared.searchArtists(keyword: artistName, limit: 5))?.first {
            artist = first
            mid = first.id
        }
        var songs = (try? await QQMusicAPI.shared.artistHotSongs(mid: mid, name: artistName, limit: 300)) ?? []
        if songs.isEmpty {
            var fallback: [Song] = []
            for offset in stride(from: 0, to: 300, by: 30) {
                let page = (try? await QQMusicAPI.shared.searchSongs(keyword: artistName, limit: 30, offset: offset)) ?? []
                if page.isEmpty { break }
                fallback.append(contentsOf: page)
                if page.count < 30 { break }
            }
            var seen = Set<String>()
            songs = fallback.filter { seen.insert($0.identityKey).inserted }
        }
        if !songs.isEmpty {
            hotSongs = songs
        }
        persistLoadedContent()
        let fetchedAlbums = await albumsTask
        if !fetchedAlbums.isEmpty {
            albums = fetchedAlbums
        }
        loading = false
    }

    /// 酷狗歌手主页优先走作者歌曲接口，再补 `singer/song` 和综合搜索结果，
    /// 避免部分歌手页只停在首批 19 首。
    private func loadKugouArtist() async {
        async let albumsTask = searchedAlbumsForCurrentArtist()
        let resolvedArtist: Artist?
        if let artistID,
           !artistID.isEmpty,
           !artistID.hasPrefix("qq-") {
            let rawID = artistID.replacingOccurrences(of: "kugou-", with: "")
            resolvedArtist = artist ?? Artist(id: rawID, name: artistName, coverURL: nil, source: .kugou)
        } else {
            resolvedArtist = (try? await KugouMusicAPI.shared.searchArtists(keyword: artistName, limit: 10))?.first
        }
        if let resolvedArtist {
            artist = resolvedArtist
        }
        var songs: [Song] = []
        var primarySongs: [Song] = []
        if let resolvedArtist,
           !resolvedArtist.id.isEmpty,
           !resolvedArtist.id.hasPrefix("qq-") {
            var seen = Set<String>()
            let pageSize = 100
            let maxSongs = 1_000
            for page in 1...(maxSongs / pageSize) {
                let batch = (try? await KugouMusicAPI.shared.artistSongs(
                    authorID: resolvedArtist.id,
                    page: page,
                    limit: pageSize
                )) ?? []
                if batch.isEmpty { break }
                let before = songs.count
                for song in batch where seen.insert(song.identityKey).inserted {
                    songs.append(song)
                    primarySongs.append(song)
                    if songs.count >= maxSongs { break }
                }
                if songs.count >= maxSongs || songs.count == before {
                    break
                }
            }
        }

        // The author endpoint has historically returned only 19 rows for some
        // accounts/charts. Supplement a short result with paged song search.
        if songs.count < 100 {
            async let exact = KugouMusicAPI.shared.searchSongs(keyword: artistName, limit: 300)
            async let works = KugouMusicAPI.shared.searchSongs(keyword: "\(artistName) 歌曲", limit: 300)
            let candidates = [
                (try? await exact) ?? [],
                (try? await works) ?? [],
            ]
            var seen = Set(songs.map(\.identityKey))
            for song in candidates.flatMap({ $0 }) {
                guard seen.insert(song.identityKey).inserted else { continue }
                songs.append(song)
            }
        }

        if songs.isEmpty {
            async let exact = KugouMusicAPI.shared.searchSongs(keyword: artistName, limit: 300)
            async let hot = KugouMusicAPI.shared.searchSongs(keyword: "\(artistName) 热门", limit: 200)
            async let works = KugouMusicAPI.shared.searchSongs(keyword: "\(artistName) 歌曲", limit: 200)
            let batches = [
                (try? await exact) ?? [],
                (try? await hot) ?? [],
                (try? await works) ?? [],
            ]
            var seen = Set<String>()
            songs = batches.flatMap { $0 }.filter { song in
                seen.insert(song.identityKey).inserted
            }
        }

        if !songs.isEmpty {
            hotSongs = songs
        }
        if songs.isEmpty, !primarySongs.isEmpty {
            hotSongs = primarySongs
        }
        if !hotSongs.isEmpty {
            hotSongs = Array(hotSongs.prefix(1_000))
        }
        persistLoadedContent()
        let fetchedAlbums = await albumsTask
        if !fetchedAlbums.isEmpty {
            albums = fetchedAlbums
        }
        BeansLogger.shared.log("酷狗歌手主页完成：artist=\(artistName) songs=\(hotSongs.count)", level: .debug)
        loading = false
    }

    /// 补充目录没有独立的歌手详情接口时，使用同源歌曲搜索构建歌手页，
    /// 不回退到其它平台，避免来源和封面错位。
    private func loadAdditionalCatalogArtist() async {
        async let albumsTask = searchedAlbumsForCurrentArtist()
        if artist?.coverURL == nil {
            let candidates: [Artist]
            switch artistSource {
            case .kuwo:
                candidates = (try? await AdditionalCatalogSearchAPI.searchKuwoArtists(keyword: artistName, limit: 20)) ?? []
            case .migu:
                candidates = (try? await AdditionalCatalogSearchAPI.searchMiguArtists(keyword: artistName, limit: 20)) ?? []
            default:
                candidates = []
            }
            let normalizedName = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let resolved = candidates.first(where: { $0.name == normalizedName }) ?? candidates.first {
                artist = resolved
            }
        }
        let songs: [Song]
        switch artistSource {
        case .kuwo:
            songs = (try? await AdditionalCatalogSearchAPI.searchKuwo(keyword: artistName, limit: 100)) ?? []
        case .migu:
            songs = (try? await AdditionalCatalogSearchAPI.searchMigu(keyword: artistName, limit: 100)) ?? []
        default:
            songs = []
        }
        let normalized = artistName
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let matched = songs.filter { song in
            song.artists
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
                .contains(normalized)
        }
        let fetchedSongs = matched.isEmpty ? songs : matched
        if !fetchedSongs.isEmpty {
            hotSongs = fetchedSongs
        }
        persistLoadedContent()
        let fetchedAlbums = await albumsTask
        if !fetchedAlbums.isEmpty {
            albums = fetchedAlbums
        }
        if artist == nil {
            artist = Artist(
                id: artistID ?? "\(artistSource.rawValue)-\(artistName)",
                name: artistName,
                coverURL: fetchedSongs.first?.coverURL,
                source: artistSource
            )
        }
        loading = false
        if hotSongs.isEmpty { errorMessage = "未找到歌手「\(artistName)」" }
    }

    private func searchedAlbumsForCurrentArtist() async -> [Album] {
        let candidates: [Album]
        switch artistSource {
        case .qq:
            candidates = (try? await QQMusicAPI.shared.searchAlbums(keyword: artistName, limit: 60)) ?? []
        case .kugou:
            candidates = (try? await KugouMusicAPI.shared.searchAlbums(keyword: artistName, limit: 60)) ?? []
        case .kuwo:
            candidates = (try? await AdditionalCatalogSearchAPI.searchKuwoAlbums(keyword: artistName, limit: 60)) ?? []
        case .migu:
            candidates = (try? await AdditionalCatalogSearchAPI.searchMiguAlbums(keyword: artistName, limit: 60)) ?? []
        case .netease:
            return []
        }
        let expected = normalizedArtistName(artistName)
        guard !expected.isEmpty else { return Array(candidates.prefix(60)) }
        let matched = candidates.filter { album in
            let albumArtist = normalizedArtistName(album.artistName)
            return !albumArtist.isEmpty && (albumArtist.contains(expected) || expected.contains(albumArtist))
        }
        return Array((matched.isEmpty ? candidates : matched).prefix(60))
    }

    private func normalizedArtistName(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    /// 歌曲列表先到时立即落盘，不能因为专辑请求较慢或用户返回上一页而丢掉
    /// 已经成功加载的歌手页内容。
    private func persistLoadedContent() {
        guard !hotSongs.isEmpty || !albums.isEmpty else { return }
        ArtistHomeCache.shared.save(artist: artist, songs: hotSongs, albums: albums, for: cacheKey)
    }
}
