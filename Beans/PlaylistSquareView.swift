import SwiftUI

/// 独立的歌单广场页，主页和这里共用各平台默认推荐接口。
struct PlaylistSquareView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.beansUsesSharedRootBackdrop) private var usesSharedRootBackdrop
    @ObservedObject private var platformPrefs = PlatformPreferenceStore.shared

    @AppStorage("beans.playlistSquareSource") private var playlistSourceRaw = SearchProvider.netease.rawValue
    @AppStorage("beans.uiStyle") private var uiStyleRaw = BeansUIStyle.liquid.rawValue
    @State private var playlists: [Playlist] = []
    @State private var selectedCategory = PlaylistSquareCategory.all.id
    @State private var categories: [PlaylistSquareCategory] = [.all]
    @State private var searchText = ""
    @State private var searchResults: [Playlist] = []
    @State private var isSearching = false
    @State private var isSearchLoading = false
    @State private var searchTask: Task<Void, Never>?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var expanded = false
    @State private var loadRequestID = UUID()
    @State private var neteaseHasMore = false
    @State private var neteaseOffset = 0
    @State private var isLoadingMore = false
    @State private var showPlaylistPlatformMenu = false
    @State private var showProfile = false

    private let neteasePageSize = 30

    // 分类请求通过 /playlist/list 的 cat 参数区分内容。
    private let neteaseCategories = [
        "全部", "推荐歌单", "精品歌单", "官方", "华语", "流行", "摇滚", "民谣", "电子",
        "轻音乐", "说唱", "爵士", "古典", "影视原声", "ACG", "古风", "怀旧", "治愈",
        "放松", "伤感", "快乐", "学习", "工作", "运动", "驾车", "夜晚"
    ]

    private var isNativeClean: Bool {
        BeansUIStyle(rawValue: uiStyleRaw) == .nativeClean
    }

    private var providers: [SearchProvider] {
        platformPrefs.enabledSearchProviders
    }

    private var source: SearchProvider {
        guard let saved = SearchProvider(rawValue: playlistSourceRaw), providers.contains(saved) else {
            return providers.first ?? .netease
        }
        return saved
    }

    private var visiblePlaylists: [Playlist] {
        if source == .netease { return playlists }
        return expanded ? playlists : Array(playlists.prefix(18))
    }

    /// Keep the original adaptive catalogue layout on iPad. The later two-column
    /// large-card treatment is retained for iPhone, where it was introduced.
    private var usesIPadCatalogueLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        let _ = theme.accent
        BeansNavigationStack {
            ZStack {
                if !usesSharedRootBackdrop {
                    GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                }

                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            // Older systems keep the original in-page field;
                            // iOS 26+ uses the system navigation search field.
                            playlistSearchField

                            if categories.count > 1 {
                                categoryChips
                            }

                            if isSearching && isSearchLoading {
                                playlistLoadingGrid
                            } else if isSearching {
                                searchGrid
                            } else if isLoading && playlists.isEmpty {
                                playlistLoadingGrid
                            } else if let errorMessage, playlists.isEmpty {
                                ErrorStateView(message: errorMessage) {
                                    Task { await load(force: true) }
                                }
                                .frame(minHeight: 220)
                            } else if playlists.isEmpty {
                                EmptyStateView(icon: "music.note.list", text: emptyText)
                                    .frame(maxWidth: .infinity, minHeight: 220)
                            } else {
                                playlistGrid
                                if source == .netease {
                                    neteaseLoadMoreFooter
                                } else if playlists.count > 18 {
                                    expandButton
                                }
                            }

                            Color.clear.frame(height: 100)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 2)
                    }
                    .beansScrollIndicatorsHidden()
                    .background(Color.clear)
                }
            }
            .task(id: "\(source.rawValue)-\(selectedCategory)") {
                await load(force: false)
            }
            .task(id: source.rawValue) {
                await loadCategories()
            }
            .onReceive(platformPrefs.changes) { _ in
                if !providers.contains(source) {
                    playlistSourceRaw = (providers.first ?? .netease).rawValue
                    playlists = []
                }
            }
            .onChange(of: searchText) { value in
                if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, isSearching {
                    clearSearch()
                }
            }
            .modifier(
                PlaylistNativeSearchModifier(
                    text: $searchText,
                    prompt: beansLocalized("搜索歌单", "Search playlists"),
                    onSubmit: { submitSearch() }
                )
            )
            .toolbar {
                ToolbarItem(placement: .principal) {
                    playlistNavigationTitle
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    BeansProfileShortcutButton {
                        showProfile = true
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .confirmationDialog("精选平台", isPresented: $showPlaylistPlatformMenu, titleVisibility: .visible) {
            ForEach(providers) { provider in
                Button {
                    selectSource(provider)
                } label: {
                    Label(
                        LocalizedStringKey(provider.rawValue),
                        systemImage: provider == source ? "checkmark" : provider.icon
                    )
                }
            }
        }
        .sheet(isPresented: $showProfile) {
            ProfileView(forceHomeBackdrop: true)
                .environmentObject(theme)
                .environmentObject(auth)
                .environmentObject(player)
                .modifier(BeansProfileSheetBackground())
        }
        // 保留系统搜索栏，但让顶部导航区域随滚动内容透明化，歌单封面可以自然透出。
        .beansHomeNavigationBarTransparent()
        .background(Color.clear)
    }

    private var playlistColumns: [GridItem] {
        if usesIPadCatalogueLayout {
            return [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16)]
        }
        return [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    }

    private var playlistNavigationTitle: some View {
        Text(source == .netease
             ? beansLocalized("精选", "Curated")
             : beansLocalized("歌单广场", "Playlist Square"))
            .font(.headline)
            .foregroundStyle(Color.beansLabel)
            .contentShape(Rectangle())
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.55)
                    .onEnded { _ in
                        guard providers.count > 1 else { return }
                        BeansHaptics.select()
                        showPlaylistPlatformMenu = true
                    }
            )
    }

    private func selectSource(_ provider: SearchProvider) {
        BeansHaptics.tap()
        guard source != provider else { return }
        playlistSourceRaw = provider.rawValue
        selectedCategory = PlaylistSquareCategory.all.id
        playlists = []
        categories = [.all]
        expanded = false
        resetNeteasePaging()
        loadRequestID = UUID()
        clearSearch()
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { category in
                    Button {
                        guard selectedCategory != category.id else { return }
                        BeansHaptics.tap()
                        selectedCategory = category.id
                        playlists = []
                        expanded = false
                        resetNeteasePaging()
                        loadRequestID = UUID()
                    } label: {
                        Text(LocalizedStringKey(category.name))
                            .font(BeansFont.appFont(12, .medium))
                            .foregroundStyle(selectedCategory == category.id ? Color.white : Color.beansComment)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background {
                                ZStack {
                                    BeansGlass(shape: Capsule(), forceLiquid: true)
                                    if selectedCategory == category.id {
                                        Capsule().fill(Color.beansAmber.opacity(0.78))
                                    }
                                }
                            }
                    }
                    .buttonStyle(GlassPressButtonStyle(scale: 0.95))
                }
            }
        }
    }

    private var playlistGrid: some View {
        LazyVGrid(
            columns: playlistColumns,
            alignment: .center,
            spacing: usesIPadCatalogueLayout ? 18 : 20
        ) {
            ForEach(visiblePlaylists) { playlist in
                NavigationLink(destination: PlaylistView(playlist: playlist)) {
                    if usesIPadCatalogueLayout {
                        playlistCard(playlist, showsContainer: false)
                    } else {
                        largePlaylistCard(playlist)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .buttonStyle(GlassPressButtonStyle(scale: 0.97))
            }
        }
    }

    @ViewBuilder
    private var playlistSearchField: some View {
        if #available(iOS 26, *) {
            EmptyView()
        } else {
            BeansUnifiedSearchField(
                text: $searchText,
                placeholder: beansLocalized("搜索歌单", "Search playlists"),
                isSearching: isSearchLoading,
                onClear: { clearSearch() },
                onSubmit: { _ in submitSearch() }
            )
        }
    }

    private var playlistLoadingGrid: some View {
        LazyVGrid(
            columns: playlistColumns,
            alignment: .center,
            spacing: usesIPadCatalogueLayout ? 18 : 20
        ) {
            ForEach(0..<6, id: \.self) { index in
                VStack(alignment: usesIPadCatalogueLayout ? .leading : .center, spacing: usesIPadCatalogueLayout ? 7 : 8) {
                    BeansShimmerSkeleton(cornerRadius: isNativeClean ? 14 : 16)
                        .aspectRatio(1, contentMode: .fit)
                    BeansShimmerSkeleton(cornerRadius: 5)
                        .frame(height: 12)
                        .frame(maxWidth: index.isMultiple(of: 3) ? 112 : 138, alignment: usesIPadCatalogueLayout ? .leading : .center)
                    BeansShimmerSkeleton(cornerRadius: 5)
                        .frame(width: 86, height: 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minHeight: 220)
    }

    private func playlistCard(_ playlist: Playlist, showsContainer: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            CoverImage(url: playlist.coverURL, size: 150, cornerRadius: 11)
            Text(playlist.name)
                .font(BeansFont.appFont(13, .medium))
                .foregroundStyle(Color.beansLabel)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 5) {
                if playlist.playCount > 0 {
                    Label(formatPlaylistPlayCount(playlist.playCount), systemImage: "play.fill")
                }
                if playlist.trackCount > 0 {
                    if playlist.playCount > 0 { Text("·") }
                    Text(beansSongCountText(playlist.trackCount))
                }
                if !playlist.creatorName.isEmpty {
                    if playlist.trackCount > 0 {
                        Text("·")
                    }
                    Text(playlist.creatorName)
                        .lineLimit(1)
                }
            }
            .font(BeansFont.appFont(10.5))
            .foregroundStyle(Color.beansComment)
            .opacity(playlist.trackCount > 0 || !playlist.creatorName.isEmpty ? 1 : 0)
            .frame(height: 14, alignment: .leading)
        }
        .frame(width: 150, alignment: .leading)
        .padding(isNativeClean || source == .netease ? 0 : 8)
        .background {
            if showsContainer {
                if !isNativeClean {
                    BeansGlass(shape: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func largePlaylistCard(_ playlist: Playlist) -> some View {
        GeometryReader { proxy in
            VStack(spacing: 8) {
                CoverImage(url: playlist.coverURL, size: proxy.size.width, cornerRadius: 11)
                Text(playlist.name)
                    .font(BeansFont.appFont(14, .semibold))
                    .foregroundStyle(Color.beansLabel)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text([sourceDisplayName(playlist.source), playlist.creatorName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "))
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansComment)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(width: proxy.size.width, alignment: .top)
        }
        .aspectRatio(0.78, contentMode: .fit)
        .contentShape(Rectangle())
    }

    private func sourceDisplayName(_ source: SongSource) -> String {
        switch source {
        case .netease: return "网易云"
        case .qq: return "QQ音乐"
        case .kugou: return "酷狗"
        case .kuwo: return "酷我"
        case .migu: return "咪咕"
        }
    }

    private func formatPlaylistPlayCount(_ count: Int) -> String {
        if count >= 100_000_000 { return String(format: "%.1f亿", Double(count) / 100_000_000) }
        if count >= 10_000 { return String(format: "%.1f万", Double(count) / 10_000) }
        return "\(count)"
    }

    private var searchGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(beansLocalized("歌单搜索结果", "Playlist search results"))
                .font(BeansFont.appFont(14, .semibold))
                .foregroundStyle(Color.beansLabel)
            if searchResults.isEmpty {
                EmptyStateView(icon: "magnifyingglass", text: beansLocalized("没有找到相关歌单", "No matching playlists found"))
            } else {
                LazyVGrid(
                    columns: playlistColumns,
                    alignment: .center,
                    spacing: usesIPadCatalogueLayout ? 18 : 20
                ) {
                    ForEach(searchResults) { playlist in
                        NavigationLink(destination: PlaylistView(playlist: playlist)) {
                            if usesIPadCatalogueLayout {
                                playlistCard(playlist)
                            } else {
                                largePlaylistCard(playlist)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
                    }
                }
            }
        }
    }

    private var expandButton: some View {
        Button {
            BeansHaptics.select()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text(expanded
                     ? beansLocalized("收起歌单", "Collapse playlists")
                     : beansLocalized("展开全部（\(playlists.count)）", "Show all (\(playlists.count))"))
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
            }
            .font(BeansFont.appFont(13, .semibold))
            .foregroundStyle(Color.beansAmber)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background {
                if isNativeClean {
                    Capsule().fill(Color.primary.opacity(0.045))
                } else {
                    BeansGlass(shape: Capsule())
                }
            }
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
    }

    @ViewBuilder
    private var neteaseLoadMoreFooter: some View {
        if isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .tint(Color.beansAmber)
        } else if neteaseHasMore {
            Color.clear
                .frame(height: 2)
                .onAppear {
                    Task { await loadMoreNetease() }
                }
        }
    }

    private var emptyText: String {
        switch source {
        case .netease: return beansLocalized("推荐歌单暂时没有内容", "No NetEase playlists available")
        case .qq: return beansLocalized("QQ音乐热门歌单暂时没有内容", "No QQ Music playlists available")
        case .kugou: return beansLocalized("酷狗歌单广场暂时没有内容", "No Kugou playlists available")
        }
    }

    @MainActor
    private func load(force: Bool) async {
        let requestedID = loadRequestID
        let requestedSource = source
        let category = selectedCategoryInfo
        let loggedIn = source == .netease && auth.isLoggedIn
        let cache = PlaylistSquareCache.shared

        // 网易云精选内容必须以当前分类的实时响应为准，不能把旧分类缓存回填到新分类。
        if requestedSource != .netease,
           !force,
           let entry = cache.entry(provider: requestedSource, category: category, loggedIn: loggedIn),
           isCurrent(requestedID, source: requestedSource, categoryID: category.id) {
            playlists = entry.playlists
            if requestedSource == .netease {
                neteaseHasMore = entry.hasMore
                neteaseOffset = entry.nextOffset
            }
            expanded = false
            errorMessage = nil
            isLoading = false
            if cache.isFresh(entry), !BeansNetworkStatus.shared.isReachable { return }
        }

        isLoading = true
        errorMessage = nil
        expanded = false
        do {
            let loadedPlaylists: [Playlist]
            var hasMore = false
            var nextOffset = 0
            switch requestedSource {
            case .netease:
                let page = try await loadNeteaseCategory(category.name, offset: 0)
                loadedPlaylists = page.playlists
                hasMore = page.hasMore
                nextOffset = page.nextOffset
            case .qq:
                loadedPlaylists = category.id == PlaylistSquareCategory.all.id
                    ? try await QQMusicAPI.shared.hotPlaylists(limit: 18)
                    : try await QQMusicAPI.shared.playlists(categoryID: category.remoteID ?? 10000000, limit: 30)
            case .kugou:
                loadedPlaylists = category.id == PlaylistSquareCategory.all.id
                    ? try await KugouMusicAPI.shared.recommendPlaylists(limit: 12)
                    : try await KugouMusicAPI.shared.playlists(categoryID: category.remoteID ?? 0, limit: 30)
            }
            guard isCurrent(requestedID, source: requestedSource, categoryID: category.id) else { return }
            playlists = loadedPlaylists
            if requestedSource == .netease {
                neteaseHasMore = hasMore
                neteaseOffset = nextOffset
            }
            BeansLogger.shared.log(
                "歌单广场分类加载完成：平台=\(requestedSource.rawValue) 分类=\(category.name) 数量=\(loadedPlaylists.count) 首个ID=\(loadedPlaylists.first?.id ?? 0)",
                level: .info
            )
            if loadedPlaylists.isEmpty {
                BeansLogger.shared.log(
                    "歌单广场返回空内容：平台=\(requestedSource.rawValue) 分类=\(category.name)，保留空状态供用户重试",
                    level: .warn
                )
            }
            if requestedSource != .netease {
                cache.save(
                    loadedPlaylists,
                    provider: requestedSource,
                    category: category,
                    loggedIn: loggedIn,
                    hasMore: hasMore,
                    nextOffset: nextOffset
                )
            }
        } catch {
            guard isCurrent(requestedID, source: requestedSource, categoryID: category.id) else { return }
            errorMessage = error.localizedDescription
            BeansLogger.shared.log(
                "歌单广场加载失败：平台=\(requestedSource.rawValue) 分类=\(category.name) error=\(error.localizedDescription)",
                level: .warn
            )
        }
        if isCurrent(requestedID, source: requestedSource, categoryID: category.id) {
            isLoading = false
        }
    }

    private func isCurrent(_ requestID: UUID, source requestedSource: SearchProvider, categoryID: String) -> Bool {
        requestID == loadRequestID && requestedSource == source && categoryID == selectedCategory
    }

    private var selectedCategoryInfo: PlaylistSquareCategory {
        categories.first(where: { $0.id == selectedCategory }) ?? .all
    }

    private func loadNeteaseCategory(_ category: String, offset: Int) async throws -> PlaylistSquarePage {
        switch category {
        case "推荐歌单":
            let page = try await FeaturedPlaylistAPI.recommended(limit: 100)
            BeansLogger.shared.log("精选页请求：推荐歌单 endpoint=/personalized/playlist 数量=\(page.playlists.count)", level: .debug)
            return page
        case "精品歌单":
            let page = try await FeaturedPlaylistAPI.highQuality(category: "全部", limit: neteasePageSize, before: offset)
            BeansLogger.shared.log("精选页请求：精品歌单 endpoint=/playlist/highquality/list cursor=\(offset) 数量=\(page.playlists.count)", level: .debug)
            return page
        default:
            let page = try await FeaturedPlaylistAPI.categoryPage(category: category, limit: neteasePageSize, offset: offset)
            BeansLogger.shared.log("精选页请求：分类=\(category) endpoint=/playlist/list offset=\(offset) 数量=\(page.playlists.count)", level: .debug)
            return page
        }
    }

    @MainActor
    private func loadMoreNetease() async {
        guard source == .netease, neteaseHasMore, !isLoading, !isLoadingMore, !isSearching else { return }
        let requestedID = loadRequestID
        let category = selectedCategoryInfo
        let offset = neteaseOffset
        isLoadingMore = true
        defer {
            if isCurrent(requestedID, source: .netease, categoryID: category.id) {
                isLoadingMore = false
            }
        }

        do {
            let page = try await loadNeteaseCategory(category.name, offset: offset)
            guard isCurrent(requestedID, source: .netease, categoryID: category.id) else { return }
            var existing = Set(playlists.map(\.id))
            let newItems = page.playlists.filter { existing.insert($0.id).inserted }
            playlists.append(contentsOf: newItems)
            neteaseOffset = page.nextOffset
            neteaseHasMore = page.hasMore && !newItems.isEmpty
        } catch {
            guard isCurrent(requestedID, source: .netease, categoryID: category.id) else { return }
            neteaseHasMore = false
            BeansLogger.shared.log("网易云歌单广场加载下一页失败：分类=\(category.name) offset=\(offset) error=\(error.localizedDescription)", level: .warn)
        }
    }

    @MainActor
    private func resetNeteasePaging() {
        neteaseOffset = 0
        neteaseHasMore = false
        isLoadingMore = false
    }

    @MainActor
    private func loadCategories() async {
        let requestedSource = source
        let loadedCategories: [PlaylistSquareCategory]
        do {
            switch requestedSource {
            case .netease:
                loadedCategories = neteaseCategories.map { name in
                    PlaylistSquareCategory(
                        id: name == "全部" ? PlaylistSquareCategory.all.id : "netease-\(name)",
                        name: name,
                        remoteID: nil
                    )
                }
            case .qq:
                loadedCategories = try await QQMusicAPI.shared.playlistCategories()
            case .kugou:
                loadedCategories = try await KugouMusicAPI.shared.playlistCategories()
            }
        } catch {
            loadedCategories = [.all]
        }
        guard requestedSource == source else {
            return
        }
        categories = loadedCategories
        if !categories.contains(where: { $0.id == selectedCategory }) {
            selectedCategory = PlaylistSquareCategory.all.id
        }
    }

    @MainActor
    private func submitSearch() {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        guard !keyword.isEmpty else {
            clearSearch()
            return
        }

        isSearching = true
        isSearchLoading = true
        searchResults = []
        searchTask = Task {
            let requestedSource = source
            let results: [Playlist]
            switch source {
            case .netease:
                results = (try? await NetEaseAPI.shared.searchPlaylists(keyword: keyword, limit: 30)) ?? []
            case .qq:
                results = (try? await QQMusicAPI.shared.searchPlaylists(keyword: keyword, limit: 30)) ?? []
            case .kugou:
                // 酷狗歌单搜索接口不稳定，分类浏览保持可用。
                results = []
            }
            guard !Task.isCancelled, requestedSource == source else { return }
            searchResults = results
            isSearchLoading = false
        }
    }

    @MainActor
    private func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchText = ""
        searchResults = []
        isSearching = false
        isSearchLoading = false
    }
}

/// 精选页在 iOS 26+ 使用系统导航栏搜索，低系统保留原有页面内搜索框。
private struct PlaylistNativeSearchModifier: ViewModifier {
    @Binding var text: String
    let prompt: String
    let onSubmit: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .searchable(
                    text: $text,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: prompt
                )
                .onSubmit(of: .search) {
                    onSubmit()
                }
        } else {
            content
        }
    }
}
