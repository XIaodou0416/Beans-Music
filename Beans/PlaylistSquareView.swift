import SwiftUI

/// 独立的歌单广场页，主页和这里共用各平台默认推荐接口。
struct PlaylistSquareView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var platformPrefs = PlatformPreferenceStore.shared

    @AppStorage("beans.playlistSquareSource") private var playlistSourceRaw = SearchProvider.netease.rawValue
    @AppStorage("beans.uiStyle") private var uiStyleRaw = BeansUIStyle.liquid.rawValue
    @AppStorage("beans.appleSolidSurface") private var appleSolidSurface = false
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

    private var usesSolidSurface: Bool {
        isNativeClean && appleSolidSurface
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

    var body: some View {
        let _ = theme.accent
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)

                VStack(spacing: 0) {
                    headerTitle
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 10)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            playlistSearchField

                            if categories.count > 1 {
                                categoryChips
                            }

                            if isSearching && isSearchLoading {
                                ShimmerLoadingView(style: .page)
                                    .frame(maxWidth: .infinity, minHeight: 180)
                            } else if isSearching {
                                searchGrid
                            } else if isLoading && playlists.isEmpty {
                                ShimmerLoadingView(style: .page)
                                    .frame(maxWidth: .infinity, minHeight: 180)
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
                        .padding(.horizontal, isNativeClean ? 20 : 16)
                        .padding(.top, 2)
                    }
                    .beansScrollIndicatorsHidden()
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
        }
    }

    private var headerTitle: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(source == .netease
                 ? beansLocalized("精选", "Curated")
                 : beansLocalized("歌单广场", "Playlist Square"))
                .font(BeansFont.appFont(32, .bold))
                .foregroundStyle(Color.beansLabel)

            Spacer(minLength: 0)

            // 右上角快捷平台切换，不再占用内容区一整行。
            Menu {
                ForEach(providers) { provider in
                    Button {
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
                    } label: {
                        Label(
                            LocalizedStringKey(provider.rawValue),
                            systemImage: provider == source ? "checkmark" : provider.icon
                        )
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    if let imageName = source.brandImageName {
                        Image(imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 15, height: 15)
                    } else {
                        Image(systemName: source.icon)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text(LocalizedStringKey(source.rawValue))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(BeansFont.appFont(12, .semibold))
                .foregroundStyle(Color.beansComment)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background {
                    if usesSolidSurface {
                        Capsule().fill(Color.primary.opacity(0.045))
                    } else {
                        BeansGlass(shape: Capsule())
                    }
                }
                .overlay {
                    if usesSolidSurface {
                        Capsule().strokeBorder(Color.primary.opacity(0.075), lineWidth: 0.7)
                    }
                }
            }
            .disabled(providers.count < 2)
        }
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
                                Capsule().fill(selectedCategory == category.id ? Color.beansAmber : Color.primary.opacity(0.06))
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var playlistGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16)],
            alignment: .leading,
            spacing: 18
        ) {
            ForEach(visiblePlaylists) { playlist in
                NavigationLink(destination: PlaylistView(playlist: playlist)) {
                    playlistCard(playlist, showsContainer: false)
                }
                .buttonStyle(GlassPressButtonStyle(scale: 0.97))
            }
        }
    }

    private func playlistCard(_ playlist: Playlist, showsContainer: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            CoverImage(url: playlist.coverURL, size: 150, cornerRadius: isNativeClean ? 14 : 16)
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
        .padding(isNativeClean || source == .netease ? 0 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if showsContainer {
                if usesSolidSurface {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.075), lineWidth: 0.7)
                        }
                } else if !isNativeClean {
                    BeansGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
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
                    columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16)],
                    alignment: .leading,
                    spacing: 18
                ) {
                    ForEach(searchResults) { playlist in
                        NavigationLink(destination: PlaylistView(playlist: playlist)) {
                            playlistCard(playlist)
                        }
                        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
                    }
                }
            }
        }
    }

    private var playlistSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.beansComment)
            TextField(beansLocalized("搜索歌单", "Search playlists"), text: $searchText)
                .font(BeansFont.appFont(14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { submitSearch() }

            if !searchText.isEmpty {
                Button { clearSearch() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.beansComment.opacity(0.85))
                }
                .buttonStyle(.plain)
            }

            Button { submitSearch() } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(Color.beansAmber)
            }
            .buttonStyle(.plain)
            .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
        .background {
            if usesSolidSurface {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.075), lineWidth: 0.7)
                    }
            } else if #available(iOS 26, *) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
            } else {
                BeansGlass(shape: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            ShimmerLoadingView(style: .compact)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
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
            if cache.isFresh(entry) { return }
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
