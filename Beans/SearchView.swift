import SwiftUI

// MARK: - 流式标签布局（热搜标签云）

@available(iOS 16, *)
struct FlowLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

enum SearchProvider: String, CaseIterable, Identifiable, Hashable {
    case netease = "网易云音乐"
    case qq = "QQ音乐"
    case kugou = "酷狗音乐"

    var id: String { rawValue }

    /// 主题色渐变：网易云红 / QQ 绿
    var tint: LinearGradient {
        switch self {
        case .netease: return LinearGradient(
            colors: [Color(red: 0.93, green: 0.22, blue: 0.16), Color(red: 0.80, green: 0.15, blue: 0.12)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        case .qq: return LinearGradient(
            colors: [Color(red: 0.15, green: 0.78, blue: 0.55), Color(red: 0.05, green: 0.58, blue: 0.42)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        case .kugou: return LinearGradient(
            colors: [Color(red: 0.12, green: 0.58, blue: 0.95), Color(red: 0.02, green: 0.32, blue: 0.72)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
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

enum SearchResultType: String, CaseIterable, Identifiable, Hashable {
    case all = "综合"
    case song = "单曲"
    case artist = "歌手"
    case album = "专辑"
    case playlist = "歌单"

    var id: String { rawValue }
}

private struct SearchResultCacheKey: Hashable {
    let keyword: String
    let provider: SearchCatalogProvider
    let resultType: SearchResultType
}

private struct SearchResultCacheEntry {
    let songs: [Song]
    let artists: [Artist]
    let albums: [Album]
    let playlists: [Playlist]
}

/// 搜索页可用的平台不等同于首页或账号体系的平台。附加目录只在搜索页出现，
/// 不会改变现有首页、歌单和登录流程。
private enum SearchCatalogProvider: String, CaseIterable, Identifiable, Hashable {
    case aggregate = "聚合"
    case netease = "网易云音乐"
    case qq = "QQ音乐"
    case kugou = "酷狗音乐"
    case kuwo = "酷我音乐"
    case migu = "咪咕音乐"

    var id: String { rawValue }

    var englishName: String {
        switch self {
        case .aggregate: return "Aggregate"
        case .netease: return "NetEase Cloud Music"
        case .qq: return "QQ Music"
        case .kugou: return "Kugou Music"
        case .kuwo: return "Kuwo Music"
        case .migu: return "Migu Music"
        }
    }

    var songSource: SongSource? {
        switch self {
        case .aggregate: return nil
        case .netease: return .netease
        case .qq: return .qq
        case .kugou: return .kugou
        case .kuwo: return .kuwo
        case .migu: return .migu
        }
    }

    var supportsDetailedResults: Bool {
        true
    }
}

/// 底部搜索控件在新系统使用可交互的原生液态玻璃，旧系统保留材质回退。
struct BeansUnifiedSearchField: View {
    @Binding var text: String
    var controller: SearchFieldController? = nil
    @State private var fallbackController = SearchFieldController()
    let placeholder: String
    let isSearching: Bool
    let onClear: () -> Void
    let onSubmit: (String) -> Void

    @ViewBuilder
    var body: some View {
        fieldContent
            .frame(minHeight: 56)
            .background {
                BeansGlass(shape: Capsule(), forceLiquid: true)
            }
            .clipShape(Capsule())
    }

    /// 保留旧系统原有的圆角、尺寸与材质，避免 iOS 26 的液态搜索栏影响低系统布局。
    private var legacyField: some View {
        fieldContent
            .padding(.vertical, 6)
            .background {
                BeansGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .beansCardShadow(radius: 4, y: 2)
    }

    private var fieldContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.beansComment)
            SearchTextField(
                text: $text,
                controller: controller ?? fallbackController,
                placeholder: placeholder,
                textColor: UIColor.beansLabel,
                onSubmit: onSubmit
            )
            .frame(height: 32)
            .frame(maxWidth: .infinity)
            ZStack {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.beansAmber)
                    .opacity(isSearching ? 1 : 0)
            }
            .frame(width: 20, height: 22)
            .animation(nil, value: isSearching)
            ZStack {
                Button {
                    text = ""
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.beansComment.opacity(0.85))
                }
                .buttonStyle(.plain)
                .opacity(text.isEmpty ? 0 : 1)
                .disabled(text.isEmpty)
            }
            .frame(width: 20, height: 22)
        }
        .padding(.horizontal, 15)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .allowsHitTesting(true)
        .zIndex(20)
    }
}

/// 仅在 iOS 26 及以上使用系统搜索栏，保证入口与设置页由同一套系统组件负责布局和交互。
struct BeansSystemSearchModifier: ViewModifier {
    @Binding var text: String
    let prompt: String
    let onSubmit: (String) -> Void

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
                    onSubmit(text)
                }
        } else {
            content
        }
    }
}

struct SearchView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.beansUsesSharedRootBackdrop) private var usesSharedRootBackdrop
    @AppStorage("beans.uiStyle") private var uiStyleRaw = BeansUIStyle.liquid.rawValue

    @State private var keyword = ""
    @State private var provider: SearchCatalogProvider = .aggregate
    /// 搜索平台是页面内状态；保留进入搜索前的首页平台，避免搜索筛选意外影响首页。
    @State private var homeSourceSnapshot = UserDefaults.standard.string(forKey: "beans.homeSource") ?? SearchProvider.netease.rawValue
    private var searchProviders: [SearchCatalogProvider] { SearchCatalogProvider.allCases }
    /// 已加载热门搜索的 provider（避免切 tab 反复加载）
    @State private var hotLoadedProvider: SearchCatalogProvider?
    @State private var resultType: SearchResultType = .all
    @State private var songResults: [Song] = []
    @State private var artistResults: [Artist] = []
    @State private var albumResults: [Album] = []
    @State private var playlistResults: [Playlist] = []
    @State private var hotWords: [String] = []
    @State private var hotWordsCache: [SearchCatalogProvider: [String]] = [:]
    @State private var searchResultCache: [SearchResultCacheKey: SearchResultCacheEntry] = [:]
    @State private var searching = false
    @State private var errorMessage: String?
    @State private var showAddToPlaylist: Song?
    @State private var selectedArtist: Artist?
    @State private var selectedAlbum: Album?
    @State private var selectedPlaylist: Playlist?
    @ObservedObject private var historyStore = SearchHistoryStore.shared
    @State private var debounceTask: Task<Void, Never>?
    @State private var searchTask: Task<Void, Never>?
    @State private var searchRequestID = UUID()
    @State private var playlistSearchTask: Task<Void, Never>?
    @State private var playlistSearchRequestID = UUID()
    @State private var showBatchDownload = false
    @State private var showProfile = false
    @State private var artistCoverCache: [String: URL] = [:]
    /// UIKit 输入框控制器（提交拼音、收起键盘等由它统一处理）
    @State private var searchController = SearchFieldController()
    @AppStorage(BeansBackendSettings.downloadUnlockKey) private var downloadFeatureUnlocked = false

    private var isNativeClean: Bool {
        BeansUIStyle(rawValue: uiStyleRaw) == .nativeClean
    }

    private var usesTabletHotSearchLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        BeansNavigationStack {
            if #available(iOS 26, *) {
                pageContent
                    .navigationTitle(keyword.isEmpty ? "搜索" : keyword)
            } else {
                pageContent
            }
        }
        .task(id: provider) {
            if let cached = hotWordsCache[provider] {
                hotLoadedProvider = provider
                hotWords = cached
                return
            }
            guard hotLoadedProvider != provider else { return }
            hotLoadedProvider = provider
            hotWords = []
            await loadHotWords()
        }
        .onChange(of: keyword) { newValue in
            debounceTask?.cancel()
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                songResults = []
                artistResults = []
                albumResults = []
                playlistResults = []
                errorMessage = nil
                return
            }
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                if resultType == .playlist {
                    await searchPlaylistTab(trimmed)
                } else {
                    await startSearch(trimmed)
                }
            }
        }
        .onChange(of: provider) { _ in
            restoreHomeSourceSnapshot()
            let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            debounceTask?.cancel()
            Task {
                if resultType == .playlist {
                    await searchPlaylistTab(trimmed)
                } else {
                    await startSearch(trimmed)
                }
            }
        }
        .onChange(of: resultType) { _ in
            let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            BeansHaptics.tap()
            debounceTask?.cancel()
            Task {
                if resultType == .playlist {
                    await searchPlaylistTab(trimmed)
                } else {
                    await startSearch(trimmed)
                }
            }
        }
        .onAppear {
            homeSourceSnapshot = UserDefaults.standard.string(forKey: "beans.homeSource")
                ?? SearchProvider.netease.rawValue
        }
        .sheet(item: $showAddToPlaylist) { song in
            AddToLocalPlaylistSheet(song: song)
                .environmentObject(theme)
        }
        .sheet(item: $selectedArtist) { artist in
            ArtistHomeSheet(artist: artist)
                .environmentObject(player)
        }
        .sheet(item: $selectedAlbum) { album in
            AlbumDetailView(album: album)
                .environmentObject(player)
                .environmentObject(theme)
        }
        .sheet(item: $selectedPlaylist) { playlist in
            BeansNavigationStack {
                PlaylistView(playlist: playlist)
                    .environmentObject(player)
                    .environmentObject(auth)
                    .environmentObject(theme)
            }
        }
        .sheet(isPresented: $showBatchDownload) {
            BatchDownloadSheet(songs: songResults, title: "下载搜索结果")
                .environmentObject(theme)
        }
        .sheet(isPresented: $showProfile) {
            ProfileView(forceHomeBackdrop: true)
                .environmentObject(theme)
                .environmentObject(auth)
                .environmentObject(player)
                .modifier(BeansProfileSheetBackground())
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        if #available(iOS 26, *) {
            modernPageContent
        } else {
            legacyPageContent
        }
    }

    private var modernPageContent: some View {
        let _ = theme.accent
        return ZStack {
            if !usesSharedRootBackdrop {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
            }
            TabBarAppearanceConfigurator()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        searchField
                        BeansProfileShortcutButton {
                            showProfile = true
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    contentArea
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .beansScrollIndicatorsHidden()
            .beansScrollDismissesKeyboard()
        }
    }

    private var legacyPageContent: some View {
        let _ = theme.accent
        return ZStack {
            if !usesSharedRootBackdrop {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
            }
            TabBarAppearanceConfigurator()
            ScrollView {
                VStack(spacing: 0) {
                    legacyHeaderTitle
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 10)
                    searchField
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                    legacyContentArea
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .beansScrollIndicatorsHidden()
            .beansScrollDismissesKeyboard()
        }
    }

    private var legacyHeaderTitle: some View {
        HStack {
            Text("搜索")
                .font(BeansFont.appFont(32, .bold))
                .foregroundStyle(Color.beansLabel)
            Spacer(minLength: 0)
            BeansProfileShortcutButton {
                showProfile = true
            }
        }
    }

    @ViewBuilder
    private var legacyContentArea: some View {
        if keyword.isEmpty {
            hotSection
        } else {
            VStack(spacing: 0) {
                resultProviderPicker
                typeTabs
                resultsArea
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    // MARK: - 内容区（热搜 / 分类+结果 固定占满剩余高度，切换不引起布局跳动）

    @ViewBuilder
    private var contentArea: some View {
        if keyword.isEmpty {
            hotSection
        } else {
            VStack(spacing: 0) {
                resultProviderPicker
                typeTabs
                resultsArea
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    // MARK: - 搜索框

    private var searchField: some View {
        BeansUnifiedSearchField(
            text: $keyword,
            controller: searchController,
            placeholder: beansLocalized("搜索歌曲、歌手、专辑", "Search songs, artists, or albums"),
            isSearching: searching,
            onClear: {
                songResults = []
                artistResults = []
                albumResults = []
                playlistResults = []
                errorMessage = nil
                debounceTask?.cancel()
            },
            onSubmit: submitSearch
        )
    }

    private func submitSearch(_ text: String) {
        performSearch(text)
    }

    private func performSearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        keyword = trimmed
        searchController.dismissKeyboard()
        debounceTask?.cancel()
        historyStore.record(trimmed)
        Task {
            if resultType == .playlist {
                await searchPlaylistTab(trimmed)
            } else {
                await startSearch(trimmed)
            }
        }
    }

    private func restoreHomeSourceSnapshot() {
        guard UserDefaults.standard.string(forKey: "beans.homeSource") != homeSourceSnapshot else { return }
        UserDefaults.standard.set(homeSourceSnapshot, forKey: "beans.homeSource")
    }

    // MARK: - 搜索结果平台选择

    private var resultProviderPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("搜索平台")
                    .font(BeansFont.appFont(13, .medium))
                    .foregroundStyle(Color.beansComment)
                Spacer(minLength: 0)
                Text(provider.rawValue)
                    .font(BeansFont.appFont(12, .semibold))
                    .foregroundStyle(Color.beansAmber)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(searchProviders) { candidate in
                        providerButton(candidate)
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func providerButton(_ candidate: SearchCatalogProvider) -> some View {
        Button {
            BeansHaptics.tap()
            guard provider != candidate else { return }
            provider = candidate
        } label: {
            HStack(spacing: 5) {
                if provider == candidate {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(LocalizedStringKey(candidate.rawValue))
            }
                .font(BeansFont.appFont(13, .semibold))
                .foregroundStyle(provider == candidate ? Color.white : Color.beansLabel)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background {
                    if provider == candidate {
                        Capsule().fill(Color.beansAmber)
                    } else {
                        BeansGlass(shape: Capsule(), forceLiquid: true)
                    }
                }
        }
        .buttonStyle(.plain)
        .frame(minHeight: 40)
    }

    // MARK: - 分类选择（歌曲 / 歌手 / 专辑）

    private var typeTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchResultType.allCases) { type in
                    Button {
                        guard resultType != type else { return }
                        BeansHaptics.tap()
                        resultType = type
                    } label: {
                        Text(LocalizedStringKey(type.rawValue))
                            .font(BeansFont.appFont(13, .semibold))
                            .foregroundStyle(resultType == type ? Color.beansAmber : Color.beansLabel)
                            .frame(minWidth: 58, minHeight: 40)
                            .padding(.horizontal, 7)
                            .background {
                                BeansGlass(shape: Capsule(), forceLiquid: true)
                            }
                            .overlay {
                                Capsule()
                                    .strokeBorder(
                                        resultType == type ? Color.beansAmber.opacity(0.72) : Color.beansLabel.opacity(0.08),
                                        lineWidth: resultType == type ? 1.1 : 0.6
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .padding(.bottom, 4)
    }

    // MARK: - 热门搜索

    private var hotSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Color.beansComment.opacity(0.72))
                    .padding(.top, 44)
                Text("搜索歌曲、歌手、专辑或歌单")
                    .font(BeansFont.appFont(18, .semibold))
                    .foregroundStyle(Color.beansLabel)
                Text("使用搜索框开始，聚合搜索也可以切换到单个平台。")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansComment)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("热门搜索", systemImage: "flame.fill")
                        .font(BeansFont.appFont(16, .bold))
                        .foregroundStyle(Color.beansLabel)
                    Spacer(minLength: 0)
                    Text(provider.rawValue)
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                }

                if hotWords.isEmpty {
                    hotSearchLoadingState
                } else {
                    LazyVGrid(columns: hotSearchColumns, alignment: .leading, spacing: 10) {
                        ForEach(hotWords, id: \.self) { word in
                            searchTag(word, icon: "magnifyingglass")
                        }
                    }
                }
            }

            if !historyStore.history.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("搜索历史", systemImage: "clock.arrow.circlepath")
                            .font(BeansFont.appFont(16, .bold))
                            .foregroundStyle(Color.beansLabel)
                        Spacer(minLength: 0)
                        Button("清空") {
                            BeansHaptics.tap()
                            historyStore.clear()
                        }
                        .font(BeansFont.appFont(13))
                        .foregroundStyle(Color.beansComment)
                        .buttonStyle(.plain)
                    }

                    LazyVGrid(columns: historySearchColumns, alignment: .leading, spacing: 10) {
                        ForEach(historyStore.history, id: \.self) { word in
                            HStack(spacing: 6) {
                                Button {
                                    performSearch(word)
                                } label: {
                                    Text(word)
                                        .font(BeansFont.appFont(13, .medium))
                                        .foregroundStyle(Color.beansLabel)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    BeansHaptics.tap()
                                    historyStore.remove(word)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color.beansComment)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("删除搜索记录")
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background { BeansGlass(shape: Capsule(), forceLiquid: true) }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hotSearchColumns: [GridItem] {
        [GridItem(.adaptive(minimum: usesTabletHotSearchLayout ? 160 : 140), spacing: 10)]
    }

    private var historySearchColumns: [GridItem] {
        [GridItem(.adaptive(minimum: usesTabletHotSearchLayout ? 150 : 120), spacing: 10)]
    }

    private func searchTag(_ word: String, icon: String) -> some View {
        Button {
            BeansHaptics.tap()
            performSearch(word)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.beansAmber)
                Text(word)
                    .font(BeansFont.appFont(13, .medium))
                    .foregroundStyle(Color.beansLabel)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background { BeansGlass(shape: Capsule(), forceLiquid: true) }
        }
        .buttonStyle(.plain)
    }

    private var hotSearchLoadingState: some View {
        LazyVGrid(columns: hotSearchColumns, alignment: .leading, spacing: 10) {
                ForEach(0..<6, id: \.self) { _ in
                BeansShimmerSkeleton(cornerRadius: 22)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }

    // MARK: - 结果区

    @ViewBuilder
    private var resultsArea: some View {
        switch resultType {
        case .all: allResultsArea
        case .song: songResultsArea
        case .artist: artistResultsArea
        case .album: albumResultsArea
        case .playlist: playlistResultsArea
        }
    }

    private var searchResultsLoadingState: some View {
        ProgressView()
            .controlSize(.regular)
            .tint(Color.beansAmber)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .top)
            .padding(.top, 20)
            .padding(.bottom, 120)
    }

    private var isCurrentResultEmpty: Bool {
        switch resultType {
        case .all:
            return songResults.isEmpty && artistResults.isEmpty && albumResults.isEmpty && playlistResults.isEmpty
        case .song: return songResults.isEmpty
        case .artist: return artistResults.isEmpty
        case .album: return albumResults.isEmpty
        case .playlist: return playlistResults.isEmpty
        }
    }

    private var allResultsArea: some View {
        Group {
            if let errorMessage, isCurrentResultEmpty {
                ErrorStateView(message: errorMessage) { submitSearch() }
            } else if searching && isCurrentResultEmpty {
                searchResultsLoadingState
            } else if isCurrentResultEmpty {
                EmptyStateView(icon: "magnifyingglass", text: "未找到相关结果")
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    if !songResults.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            searchSectionHeader("单曲") { resultType = .song }
                            HStack {
                                Text("\(min(songResults.count, 6)) 首歌曲")
                                    .font(BeansFont.appFont(14, .medium))
                                    .foregroundStyle(Color.beansComment)
                                Spacer(minLength: 8)
                                if downloadFeatureUnlocked, songResults.count > 1 {
                                    Button {
                                        BeansHaptics.tap()
                                        showBatchDownload = true
                                    } label: {
                                        Label("批量下载", systemImage: "arrow.down.circle")
                                            .font(BeansFont.appFont(13, .semibold))
                                            .foregroundStyle(Color.beansAmber)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background { Capsule().fill(Color.beansAmber.opacity(0.14)) }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            ForEach(Array(songResults.prefix(6).enumerated()), id: \.element.identityKey) { index, song in
                                BeansSearchSongRow(song: song) {
                                    BeansHaptics.tap()
                                    player.play(songs: songResults, startAt: index)
                                }
                            }
                        }
                    }
                    if !artistResults.isEmpty {
                        searchCardShelf(title: "歌手", seeAll: { resultType = .artist }) {
                            ForEach(Array(artistResults.prefix(8))) { artist in
                                artistCard(artist)
                            }
                        }
                    }
                    if !albumResults.isEmpty {
                        searchCardShelf(title: "专辑", seeAll: { resultType = .album }) {
                            ForEach(Array(albumResults.prefix(8))) { album in
                                albumCard(album)
                            }
                        }
                    }
                    if !playlistResults.isEmpty {
                        searchCardShelf(title: "歌单", seeAll: { resultType = .playlist }) {
                            ForEach(Array(playlistResults.prefix(8))) { playlist in
                                playlistCard(playlist)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 180)
                .overlay(alignment: .top) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.beansAmber)
                        .padding(.top, 6)
                        .opacity(searching ? 1 : 0)
                }
            }
        }
    }

    private func searchSectionHeader(_ title: String, action: @escaping () -> Void) -> some View {
        HStack {
            Button(action: action) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(BeansFont.appFont(27, .bold))
                        .foregroundStyle(Color.beansLabel)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.beansComment)
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
        }
    }

    private func searchCardShelf<Content: View>(
        title: String,
        seeAll: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            searchSectionHeader(title, action: seeAll)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14, content: content)
                    .padding(.horizontal, 1)
            }
        }
    }

    private func artistCard(_ artist: Artist) -> some View {
        Button {
            BeansHaptics.tap()
            searchController.dismissKeyboard()
            selectedArtist = artist
        } label: {
            VStack(spacing: 10) {
                CoverImage(url: artist.coverURL ?? artistCoverCache[artist.id], size: 124, cornerRadius: 62)
                    .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
                Text(artist.name)
                    .font(BeansFont.appFont(13, .medium))
                    .foregroundStyle(Color.beansLabel)
                    .lineLimit(1)
            }
            .frame(width: 132)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
    }

    private func albumCard(_ album: Album) -> some View {
        Button {
            BeansHaptics.tap()
            searchController.dismissKeyboard()
            selectedAlbum = album
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                CoverImage(url: album.coverURL, size: 132, cornerRadius: 12)
                Text(album.name)
                    .font(BeansFont.appFont(13, .medium))
                    .foregroundStyle(Color.beansLabel)
                    .lineLimit(1)
                Text(album.artistName.isEmpty ? "未知歌手" : album.artistName)
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansComment)
                    .lineLimit(1)
            }
            .frame(width: 132, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
    }

    private func playlistCard(_ playlist: Playlist) -> some View {
        Button {
            BeansHaptics.tap()
            searchController.dismissKeyboard()
            selectedPlaylist = playlist
        } label: {
            VStack(spacing: 7) {
                CoverImage(url: playlist.coverURL, size: 132, cornerRadius: 12)
                Text(playlist.name)
                    .font(BeansFont.appFont(13, .medium))
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
            .frame(width: 132, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
    }

    private func largePlaylistCard(_ playlist: Playlist) -> some View {
        Button {
            BeansHaptics.tap()
            searchController.dismissKeyboard()
            selectedPlaylist = playlist
        } label: {
            GeometryReader { proxy in
                VStack(spacing: 8) {
                    CoverImage(url: playlist.coverURL, size: proxy.size.width, cornerRadius: 14)
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
        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
    }

    private var songResultsArea: some View {
        Group {
            if let errorMessage, songResults.isEmpty {
                ErrorStateView(message: errorMessage) { submitSearch() }
            } else if searching && songResults.isEmpty {
                searchResultsLoadingState
            } else if songResults.isEmpty {
                EmptyStateView(icon: "music.note", text: "\(provider.rawValue)未找到相关歌曲")
            } else {
                VStack {
                    LazyVStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Text(beansLocalized("找到 \(songResults.count) 首 · \(provider.rawValue)", "Found \(songResults.count) songs · \(provider.englishName)"))
                                .font(BeansFont.appFont(12))
                                .foregroundStyle(Color.beansComment)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .truncationMode(.tail)
                                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                .layoutPriority(1)
                            Button {
                                BeansHaptics.tap()
                                player.play(songs: songResults, startAt: 0)
                            } label: {
                                Label("播放全部", systemImage: "play.fill")
                                    .font(BeansFont.appFont(12, .semibold))
                                    .foregroundStyle(Color.beansAmber)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                            .background { BeansSurface(shape: Capsule()) }
                            }
                            .buttonStyle(.plain)
                            .fixedSize(horizontal: true, vertical: false)
                            if downloadFeatureUnlocked, songResults.count > 1 {
                                Button {
                                    BeansHaptics.tap()
                                    showBatchDownload = true
                                } label: {
                                    Label("批量下载", systemImage: "arrow.down.circle")
                                        .font(BeansFont.appFont(12, .semibold))
                                        .foregroundStyle(Color.beansAmber)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background { BeansSurface(shape: Capsule()) }
                                }
                                .buttonStyle(.plain)
                                .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        ForEach(Array(songResults.enumerated()), id: \.element.identityKey) { index, song in
                            BeansSearchSongRow(song: song) {
                                BeansHaptics.tap()
                                player.play(songs: songResults, startAt: index)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 180)
                }
                .overlay(alignment: .top) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.beansAmber)
                        .padding(.top, 10)
                        .opacity(searching ? 1 : 0)
                }
            }
        }
    }

    private var artistResultsArea: some View {
        Group {
            if let errorMessage, artistResults.isEmpty {
                ErrorStateView(message: errorMessage) { submitSearch() }
            } else if searching && artistResults.isEmpty {
                searchResultsLoadingState
            } else if artistResults.isEmpty {
                EmptyStateView(icon: "person.crop.circle", text: "\(provider.rawValue)未找到相关歌手")
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    Text(beansLocalized("找到 \(artistResults.count) 位 · \(provider.rawValue)", "Found \(artistResults.count) artists · \(provider.englishName)"))
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .truncationMode(.tail)
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 18),
                            GridItem(.flexible(), spacing: 18),
                        ],
                        spacing: 26
                    ) {
                        ForEach(artistResults) { artist in
                            artistSearchResultCard(artist)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 180)
                .overlay(alignment: .top) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.beansAmber)
                        .padding(.top, 10)
                        .opacity(searching ? 1 : 0)
                }
            }
        }
    }

    private var albumResultsArea: some View {
        Group {
            if let errorMessage, albumResults.isEmpty {
                ErrorStateView(message: errorMessage) { submitSearch() }
            } else if searching && albumResults.isEmpty {
                searchResultsLoadingState
            } else if albumResults.isEmpty {
                EmptyStateView(icon: "square.stack", text: "\(provider.rawValue)未找到相关专辑")
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    Text(beansLocalized("找到 \(albumResults.count) 张 · \(provider.rawValue)", "Found \(albumResults.count) albums · \(provider.englishName)"))
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .truncationMode(.tail)
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 14),
                            GridItem(.flexible(), spacing: 14),
                        ],
                        spacing: 22
                    ) {
                        ForEach(albumResults) { album in
                            albumSearchResultCard(album)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 180)
                .overlay(alignment: .top) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.beansAmber)
                        .padding(.top, 10)
                        .opacity(searching ? 1 : 0)
                }
            }
        }
    }

    // MARK: - 动作

    /// 重新搜索（错误重试按钮调用：读取当前输入框文本）
    private func submitSearch() {
        debounceTask?.cancel()
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        historyStore.record(trimmed)
        Task {
            if resultType == .playlist {
                await searchPlaylistTab(trimmed)
            } else {
                await startSearch(trimmed)
            }
        }
    }

    /// 点击歌手 / 专辑：以其名称搜索歌曲
    private func searchBy(_ name: String) {
        BeansHaptics.tap()
        keyword = name
        searchController.dismissKeyboard()
        debounceTask?.cancel()
        historyStore.record(name)
        resultType = .song
        Task { await startSearch(name) }
    }

    private func loadHotWords() async {
        let requestedProvider = provider
        if provider == .aggregate {
            let values = await withTaskGroup(of: [String].self, returning: [[String]].self) { group in
                for candidate in searchProviders where candidate != .aggregate {
                    group.addTask {
                        switch candidate {
                        case .netease:
                            return (try? await NetEaseAPI.shared.hotSearch()) ?? []
                        case .qq:
                            return (try? await QQMusicAPI.shared.hotKeys()) ?? []
                        case .kugou:
                            return await KugouMusicAPI.shared.hotWords()
                        case .kuwo, .migu:
                            guard let source = candidate.songSource else { return [] }
                            return (try? await AdditionalCatalogSearchAPI.hotKeywords(for: source)) ?? []
                        case .aggregate:
                            return []
                        }
                    }
                }
                var collected: [[String]] = []
                for await result in group { collected.append(result) }
                return collected
            }
            var seen = Set<String>()
            hotWords = Array(values.flatMap { $0 }.filter {
                let normalized = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return !normalized.isEmpty && seen.insert(normalized.localizedLowercase).inserted
            }.prefix(8))
        } else if provider == .qq {
            if let words = try? await QQMusicAPI.shared.hotKeys() {
                hotWords = words
            }
        } else if provider == .kugou {
            hotWords = await KugouMusicAPI.shared.hotWords()
        } else if (provider == .kuwo || provider == .migu), let source = provider.songSource {
            hotWords = (try? await AdditionalCatalogSearchAPI.hotKeywords(for: source)) ?? []
        } else if let words = try? await NetEaseAPI.shared.hotSearch() {
            hotWords = words
        }
        guard requestedProvider == provider else { return }
        hotWords = Array(hotWords.prefix(8))
        hotWordsCache[requestedProvider] = hotWords
    }

    private func startSearch(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchTask?.cancel()
        let requestID = UUID()
        searchRequestID = requestID
        let selectedProvider = provider
        let selectedType = resultType
        let cacheKey = SearchResultCacheKey(
            keyword: trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased(),
            provider: selectedProvider,
            resultType: selectedType
        )
        // 歌单结果不复用搜索页内缓存。QQ 歌单的服务端偶发返回空列表，
        // 缓存会让用户停留在“暂无”而无法走与精选页相同的实时请求。
        if selectedType != .playlist,
           let cached = searchResultCache[cacheKey],
           cacheEntryHasResults(cached, for: selectedType) {
            songResults = cached.songs
            artistResults = cached.artists
            albumResults = cached.albums
            playlistResults = cached.playlists
            searching = false
            errorMessage = nil
            return
        }
        searchTask = Task {
            await MainActor.run {
                searching = true
                errorMessage = nil
                switch selectedType {
                case .all:
                    songResults = []
                    artistResults = []
                    albumResults = []
                    playlistResults = []
                case .song: songResults = []
                case .artist: artistResults = []
                case .album: albumResults = []
                case .playlist: playlistResults = []
                }
            }
            defer {
                if !Task.isCancelled {
                    Task { @MainActor in
                        guard searchRequestID == requestID else { return }
                        searching = false
                    }
                }
            }
            do {
                switch selectedType {
                case .all:
                    async let songsTask = catalogSongs(keyword: trimmed, provider: selectedProvider, limit: 12)
                    async let playlistsTask = catalogPlaylists(keyword: trimmed, provider: selectedProvider, limit: 12)
                    // 网易云单曲结果只携带关联专辑封面，且没有可用于详情页的歌手、
                    // 专辑标识。综合页改用对应目录接口，避免把歌曲封面或拼接名称误当作
                    // 歌手头像、专辑 ID。
                    async let artistsTask: [Artist] = selectedProvider == .netease
                        ? catalogArtists(keyword: trimmed, provider: selectedProvider, limit: 12)
                        : []
                    async let albumsTask: [Album] = selectedProvider == .netease
                        ? catalogAlbums(keyword: trimmed, provider: selectedProvider, limit: 12)
                        : []
                    let songs = await songsTask
                    let playlists = await playlistsTask
                    let neteaseArtists = await artistsTask
                    let neteaseAlbums = await albumsTask
                    let metadata = catalogMetadata(from: songs)
                    let artists = selectedProvider == .netease ? neteaseArtists : metadata.artists
                    let albums = selectedProvider == .netease ? neteaseAlbums : metadata.albums
                    guard !Task.isCancelled, searchRequestID == requestID else { return }
                    await MainActor.run {
                        guard searchRequestID == requestID else { return }
                        songResults = songs
                        artistResults = artists
                        albumResults = albums
                        playlistResults = playlists
                        searchResultCache[cacheKey] = SearchResultCacheEntry(
                            songs: songs,
                            artists: artists,
                            albums: albums,
                            playlists: playlists
                        )
                        if !songs.isEmpty || !playlists.isEmpty { BeansHaptics.success() }
                    }
                case .song:
                    let songs = await catalogSongs(keyword: trimmed, provider: selectedProvider, limit: 100)
                    guard !Task.isCancelled, searchRequestID == requestID else { return }
                    await MainActor.run {
                        guard searchRequestID == requestID else { return }
                        songResults = songs
                        searchResultCache[cacheKey] = SearchResultCacheEntry(
                            songs: songs,
                            artists: [],
                            albums: [],
                            playlists: []
                        )
                        if !songs.isEmpty { BeansHaptics.success() }
                    }
                case .artist:
                    let artists = await catalogArtists(keyword: trimmed, provider: selectedProvider, limit: 100)
                    guard !Task.isCancelled, searchRequestID == requestID else { return }
                    await MainActor.run {
                        guard searchRequestID == requestID else { return }
                        artistResults = artists
                        searchResultCache[cacheKey] = SearchResultCacheEntry(songs: [], artists: artists, albums: [], playlists: [])
                    }
                case .album:
                    let albums = await catalogAlbums(keyword: trimmed, provider: selectedProvider, limit: 100)
                    guard !Task.isCancelled, searchRequestID == requestID else { return }
                    await MainActor.run {
                        guard searchRequestID == requestID else { return }
                        albumResults = albums
                        searchResultCache[cacheKey] = SearchResultCacheEntry(songs: [], artists: [], albums: albums, playlists: [])
                    }
                case .playlist:
                    let playlists = await livePlaylistSearch(keyword: trimmed, provider: selectedProvider, limit: 100)
                    guard !Task.isCancelled, searchRequestID == requestID else { return }
                    await MainActor.run {
                        guard searchRequestID == requestID else { return }
                        playlistResults = playlists
                    }
                }
                let count = await MainActor.run {
                    switch selectedType {
                    case .all: return songResults.count + artistResults.count + albumResults.count + playlistResults.count
                    case .song: return songResults.count
                    case .artist: return artistResults.count
                    case .album: return albumResults.count
                    case .playlist: return playlistResults.count
                    }
                }
                _ = count
            } catch {
                guard !Task.isCancelled, searchRequestID == requestID else { return }
                await MainActor.run {
                    guard searchRequestID == requestID else { return }
                    errorMessage = error.localizedDescription
                }
            }
        }
        await searchTask?.value
    }

    /// 歌单分类页始终使用实时结果；QQ 分支与精选页使用相同的 API，
    /// 并在短暂空响应时做一次轻量重试，避免切换分类后误显示“暂无”。
    private func livePlaylistSearch(
        keyword: String,
        provider: SearchCatalogProvider,
        limit: Int
    ) async -> [Playlist] {
        if provider == .qq {
            for attempt in 0..<2 {
                let playlists = (try? await QQMusicAPI.shared.searchPlaylists(keyword: keyword, limit: limit)) ?? []
                if !playlists.isEmpty || Task.isCancelled { return playlists }
                if attempt == 0 {
                    try? await Task.sleep(nanoseconds: 220_000_000)
                }
            }
            return []
        }
        return await catalogPlaylists(keyword: keyword, provider: provider, limit: limit)
    }

    /// 歌单 tab 使用独立任务，不与“综合/单曲”等并发请求共享状态。
    /// 这条路径和精选页一样在用户切换到歌单后立即发起 QQ 歌单请求。
    private func searchPlaylistTab(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchTask?.cancel()
        playlistSearchTask?.cancel()

        let requestID = UUID()
        playlistSearchRequestID = requestID
        let selectedProvider = provider

        searching = true
        errorMessage = nil
        playlistResults = []

        playlistSearchTask = Task {
            let playlists = await livePlaylistSearch(keyword: trimmed, provider: selectedProvider, limit: 100)
            guard !Task.isCancelled, playlistSearchRequestID == requestID else { return }
            await MainActor.run {
                guard playlistSearchRequestID == requestID,
                      resultType == .playlist,
                      provider == selectedProvider else { return }
                playlistResults = playlists
                searching = false
                if !playlists.isEmpty { BeansHaptics.success() }
            }
        }
        await playlistSearchTask?.value
    }

    private func cacheEntryHasResults(_ entry: SearchResultCacheEntry, for type: SearchResultType) -> Bool {
        switch type {
        case .all:
            return !entry.songs.isEmpty || !entry.artists.isEmpty || !entry.albums.isEmpty || !entry.playlists.isEmpty
        case .song: return !entry.songs.isEmpty
        case .artist: return !entry.artists.isEmpty
        case .album: return !entry.albums.isEmpty
        case .playlist: return !entry.playlists.isEmpty
        }
    }

    private func artistSearchResultCard(_ artist: Artist) -> some View {
        Button {
            BeansHaptics.tap()
            searchController.dismissKeyboard()
            selectedArtist = artist
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    BeansGlass(shape: Circle(), forceLiquid: true)
                    CoverImage(url: artist.coverURL, size: 120, cornerRadius: 60)
                        .clipShape(Circle())
                }
                .frame(width: 132, height: 132)
                .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
                Text(artist.name)
                    .font(BeansFont.appFont(14, .medium))
                    .foregroundStyle(Color.beansLabel)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
    }

    private func albumSearchResultCard(_ album: Album) -> some View {
        Button {
            BeansHaptics.tap()
            searchController.dismissKeyboard()
            selectedAlbum = album
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                CoverImage(url: album.coverURL, size: 148, cornerRadius: 16)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(album.name)
                    .font(BeansFont.appFont(14, .medium))
                    .foregroundStyle(Color.beansLabel)
                    .lineLimit(1)
                Text(album.artistName.isEmpty ? "未知歌手" : album.artistName)
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansComment)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
    }

    private var playlistResultsArea: some View {
        Group {
            if let errorMessage, playlistResults.isEmpty {
                ErrorStateView(message: errorMessage) { submitSearch() }
            } else if searching && playlistResults.isEmpty {
                searchResultsLoadingState
            } else if playlistResults.isEmpty {
                EmptyStateView(icon: "music.note.list", text: "\(provider.rawValue)未找到相关歌单")
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], alignment: .center, spacing: 20) {
                    ForEach(playlistResults) { playlist in
                        largePlaylistCard(playlist)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 180)
                .overlay(alignment: .top) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.beansAmber)
                        .padding(.top, 4)
                        .opacity(searching ? 1 : 0)
                }
            }
        }
    }

    private func deduplicatedSongs(_ songs: [Song]) -> [Song] {
        var seen = Set<String>()
        return songs.filter { song in
            let title = song.name
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
            let artists = song.artists
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
            return seen.insert("\(title)|\(artists)").inserted
        }
    }

    private func catalogSongs(
        keyword: String,
        provider: SearchCatalogProvider,
        limit: Int
    ) async -> [Song] {
        switch provider {
        case .aggregate:
            let providers: [SearchCatalogProvider] = [.netease, .qq, .kugou, .kuwo, .migu]
            let completedResults = await withTaskGroup(of: [Song].self, returning: [[Song]].self) { group in
                for candidate in providers {
                    group.addTask {
                        await self.catalogSongs(keyword: keyword, provider: candidate, limit: limit)
                    }
                }
                var values: [[Song]] = []
                for await value in group { values.append(value) }
                return values
            }
            return deduplicatedSongs(completedResults.flatMap { $0 })
        case .kuwo:
            return (try? await AdditionalCatalogSearchAPI.searchKuwo(keyword: keyword, limit: limit)) ?? []
        case .migu:
            return (try? await AdditionalCatalogSearchAPI.searchMigu(keyword: keyword, limit: limit)) ?? []
        case .netease:
            return (try? await NetEaseAPI.shared.search(keyword: keyword, limit: limit)) ?? []
        case .qq:
            return (try? await QQMusicAPI.shared.searchSongs(keyword: keyword, limit: limit)) ?? []
        case .kugou:
            return (try? await KugouMusicAPI.shared.searchSongs(keyword: keyword, limit: limit)) ?? []
        }
    }

    private func catalogArtists(keyword: String, provider: SearchCatalogProvider, limit: Int) async -> [Artist] {
        switch provider {
        case .aggregate:
            let providers: [SearchCatalogProvider] = [.netease, .qq, .kugou, .kuwo, .migu]
            let groups = await withTaskGroup(of: [Artist].self, returning: [[Artist]].self) { group in
                for candidate in providers {
                    group.addTask { await self.catalogArtists(keyword: keyword, provider: candidate, limit: limit) }
                }
                var result: [[Artist]] = []
                for await value in group { result.append(value) }
                return result
            }
            var seen = Set<String>()
            return groups.flatMap { $0 }.filter {
                seen.insert("\($0.source.rawValue)|\($0.name.localizedLowercase)").inserted
            }
        case .netease:
            return (try? await NetEaseAPI.shared.searchArtists(keyword: keyword, limit: limit)) ?? []
        case .qq:
            return (try? await QQMusicAPI.shared.searchArtists(keyword: keyword, limit: limit)) ?? []
        case .kugou:
            return (try? await KugouMusicAPI.shared.searchArtists(keyword: keyword, limit: limit)) ?? []
        case .kuwo:
            return (try? await AdditionalCatalogSearchAPI.searchKuwoArtists(keyword: keyword, limit: limit)) ?? []
        case .migu:
            return (try? await AdditionalCatalogSearchAPI.searchMiguArtists(keyword: keyword, limit: limit)) ?? []
        }
    }

    private func catalogAlbums(keyword: String, provider: SearchCatalogProvider, limit: Int) async -> [Album] {
        switch provider {
        case .aggregate:
            let providers: [SearchCatalogProvider] = [.netease, .qq, .kugou, .kuwo, .migu]
            let groups = await withTaskGroup(of: [Album].self, returning: [[Album]].self) { group in
                for candidate in providers {
                    group.addTask { await self.catalogAlbums(keyword: keyword, provider: candidate, limit: limit) }
                }
                var result: [[Album]] = []
                for await value in group { result.append(value) }
                return result
            }
            var seen = Set<String>()
            return groups.flatMap { $0 }.filter {
                seen.insert("\($0.source.rawValue)|\($0.name.localizedLowercase)|\($0.artistName.localizedLowercase)").inserted
            }
        case .netease:
            return (try? await NetEaseAPI.shared.searchAlbums(keyword: keyword, limit: limit)) ?? []
        case .qq:
            return (try? await QQMusicAPI.shared.searchAlbums(keyword: keyword, limit: limit)) ?? []
        case .kugou:
            return (try? await KugouMusicAPI.shared.searchAlbums(keyword: keyword, limit: limit)) ?? []
        case .kuwo:
            return (try? await AdditionalCatalogSearchAPI.searchKuwoAlbums(keyword: keyword, limit: limit)) ?? []
        case .migu:
            return (try? await AdditionalCatalogSearchAPI.searchMiguAlbums(keyword: keyword, limit: limit)) ?? []
        }
    }

    private func catalogPlaylists(keyword: String, provider: SearchCatalogProvider, limit: Int) async -> [Playlist] {
        (try? await catalogPlaylistsThrowing(keyword: keyword, provider: provider, limit: limit)) ?? []
    }

    private func catalogPlaylistsThrowing(keyword: String, provider: SearchCatalogProvider, limit: Int) async throws -> [Playlist] {
        switch provider {
        case .aggregate:
            async let netease = NetEaseAPI.shared.searchPlaylists(keyword: keyword, limit: limit)
            async let qq = QQMusicAPI.shared.searchPlaylists(keyword: keyword, limit: limit)
            async let kugou = AdditionalCatalogSearchAPI.searchKugouPlaylists(keyword: keyword, limit: limit)
            async let kuwo = AdditionalCatalogSearchAPI.searchKuwoPlaylists(keyword: keyword, limit: limit)
            async let migu = AdditionalCatalogSearchAPI.searchMiguPlaylists(keyword: keyword, limit: limit)
            let neteaseItems = (try? await netease) ?? []
            let qqItems = (try? await qq) ?? []
            let kugouItems = (try? await kugou) ?? []
            let kuwoItems = (try? await kuwo) ?? []
            let miguItems = (try? await migu) ?? []
            let all = neteaseItems + qqItems + kugouItems + kuwoItems + miguItems
            var seen = Set<String>()
            return all.filter {
                let key = "\($0.name.localizedLowercase)|\($0.creatorName.localizedLowercase)"
                return seen.insert(key).inserted
            }
        case .netease:
            return try await NetEaseAPI.shared.searchPlaylists(keyword: keyword, limit: limit)
        case .qq:
            return try await QQMusicAPI.shared.searchPlaylists(keyword: keyword, limit: limit)
        case .kugou:
            return try await AdditionalCatalogSearchAPI.searchKugouPlaylists(keyword: keyword, limit: limit)
        case .kuwo:
            return try await AdditionalCatalogSearchAPI.searchKuwoPlaylists(keyword: keyword, limit: limit)
        case .migu:
            return try await AdditionalCatalogSearchAPI.searchMiguPlaylists(keyword: keyword, limit: limit)
        }
    }

    private func sourceDisplayName(_ source: SongSource) -> String {
        switch source {
        case .netease: return "网易云音乐"
        case .qq: return "QQ音乐"
        case .kugou: return "酷狗音乐"
        case .kuwo: return "酷我音乐"
        case .migu: return "咪咕音乐"
        }
    }

    private func catalogMetadata(from songs: [Song]) -> (artists: [Artist], albums: [Album]) {
        var artists: [Artist] = []
        var albums: [Album] = []
        var artistIndex: [String: Int] = [:]
        var albumIndex: Set<String> = []

        for song in songs {
            let artistNames = song.artists
                .components(separatedBy: CharacterSet(charactersIn: "/／,，、&＆+＋|｜;；"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for name in artistNames {
                let key = "\(song.source.rawValue)|\(name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased())"
                if let index = artistIndex[key] {
                    if artists[index].coverURL == nil, song.coverURL != nil {
                        artists[index] = Artist(id: artists[index].id, name: artists[index].name, coverURL: song.coverURL, source: artists[index].source)
                    }
                } else {
                    artistIndex[key] = artists.count
                    artists.append(Artist(id: "\(song.source.rawValue)-\(name)", name: name, coverURL: song.coverURL, source: song.source))
                }
            }

            let albumName = song.album.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !albumName.isEmpty else { continue }
            let key = "\(song.source.rawValue)|\(albumName.localizedLowercase)|\(song.artists.localizedLowercase)"
            guard albumIndex.insert(key).inserted else { continue }
            albums.append(Album(
                id: "\(song.source.rawValue)-\(albumName)-\(song.artists)",
                name: albumName,
                artistName: song.artists,
                coverURL: song.coverURL,
                source: song.source
            ))
        }
        return (artists, albums)
    }
}

private struct BeansSearchSongRow: View {
    let song: Song
    let onTap: () -> Void
    @AppStorage("beans.showSongVIPBadge") private var showSongVIPBadge = true

    private var sourceName: String {
        switch song.source {
        case .netease: return "网易云"
        case .qq: return "QQ音乐"
        case .kugou: return "酷狗"
        case .kuwo: return "酷我"
        case .migu: return "咪咕"
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                CoverImage(url: song.coverURL, song: song, size: 56, cornerRadius: 10)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(song.name)
                            .font(BeansFont.appFont(17, .semibold))
                            .foregroundStyle(Color.beansLabel)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if showSongVIPBadge, song.isVIP {
                            Text("VIP")
                                .font(BeansFont.appFont(10, .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.red))
                        }
                    }
                    Text(song.artists.isEmpty ? song.album : song.artists)
                        .font(BeansFont.appFont(14))
                        .foregroundStyle(Color.beansComment)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("来源：\(sourceName) · 音质：待检测")
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment.opacity(0.72))
                        .lineLimit(1)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                Text(song.formattedDuration)
                    .font(BeansFont.appFont(14, .regular, .monospaced))
                    .foregroundStyle(Color.beansComment)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 专辑详情页：点击搜索结果直接进入专辑内容，不再把专辑名当作歌曲关键词重新搜索。
struct AlbumDetailView: View {
    let album: Album
    /// 从已有导航栈推入时不再创建嵌套 NavigationStack。
    var embeddedInNavigation = false
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @State private var tracks: [Song] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showBatchDownload = false
    @AppStorage(BeansBackendSettings.downloadUnlockKey) private var downloadFeatureUnlocked = false

    var body: some View {
        Group {
            if embeddedInNavigation {
                albumPage
            } else {
                BeansNavigationStack { albumPage }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showBatchDownload) {
            BatchDownloadSheet(songs: tracks, title: "下载专辑")
                .environmentObject(theme)
        }
    }

    @ViewBuilder
    private var albumPage: some View {
        ZStack {
            GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
            if isLoading {
                albumDetailLoadingState
            } else if let errorMessage {
                ErrorStateView(message: errorMessage) { Task { await load() } }
            } else {
                List {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            CoverImage(url: album.coverURL, size: 92, cornerRadius: 16)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(album.name)
                                    .font(BeansFont.appFont(19, .bold))
                                    .foregroundStyle(Color.beansLabel)
                                    .lineLimit(2)
                                Text(album.artistName.isEmpty ? "未知歌手" : album.artistName)
                                    .font(BeansFont.appFont(13))
                                    .foregroundStyle(Color.beansComment)
                                Text(beansSongCountText(tracks.count))
                                    .font(BeansFont.appFont(12))
                                    .foregroundStyle(Color.beansComment)
                            }
                            Spacer(minLength: 0)
                        }
                        if !tracks.isEmpty {
                            HStack(spacing: 10) {
                                GlassButton(title: "播放全部", systemName: "play.fill", prominent: true) {
                                    player.play(songs: tracks, startAt: 0)
                                }
                                if downloadFeatureUnlocked, tracks.count > 1 {
                                    GlassButton(title: "批量下载", systemName: "arrow.down.circle") {
                                        BeansHaptics.tap()
                                        showBatchDownload = true
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    ForEach(Array(tracks.enumerated()), id: \.element.identityKey) { index, song in
                        SongCell(song: song, groupedRow: true, playbackContext: tracks, playbackIndex: index) {
                            player.play(songs: tracks, startAt: index)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .beansScrollContentBackgroundHidden()
                .beansGroupedSongListSurface()
            }
        }
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        let cache = DetailSongsCache.shared
        let cacheKey = "album-\(album.source.rawValue)-\(album.id)"
        if let cached = cache.cachedSongs(for: cacheKey) {
            await MainActor.run {
                tracks = cached.songs
                isLoading = false
                errorMessage = nil
            }
            if cache.isFresh(cached), !BeansNetworkStatus.shared.isReachable {
                return
            }
        }
        await MainActor.run {
            if tracks.isEmpty {
                isLoading = true
            }
            errorMessage = nil
        }
        do {
            let result: [Song]
            switch album.source {
            case .netease:
                guard let id = Int(album.id.replacingOccurrences(of: "netease-", with: "")) else {
                    throw NSError(domain: "BeansAlbum", code: 1, userInfo: [NSLocalizedDescriptionKey: "专辑 ID 无效"])
                }
                let direct = (try? await NetEaseAPI.shared.albumSongs(albumID: id)) ?? []
                if !direct.isEmpty {
                    result = direct
                } else {
                    result = await searchFallbackSongs(
                        queries: [albumSearchQuery, album.name],
                        search: { query in
                            (try? await NetEaseAPI.shared.search(keyword: query, limit: 100)) ?? []
                        }
                    )
                }
            case .qq:
                let qqMID = album.id.trimmingCharacters(in: .whitespacesAndNewlines)
                let direct = (try? await QQMusicAPI.shared.albumSongs(albumMID: qqMID)) ?? []
                if !direct.isEmpty {
                    result = direct
                } else {
                    result = await searchFallbackSongs(
                        queries: [albumSearchQuery, album.name],
                        search: { query in
                            (try? await QQMusicAPI.shared.searchSongs(keyword: query, limit: 100)) ?? []
                        }
                    )
                }
            case .kugou:
                let albumID = album.id.trimmingCharacters(in: .whitespacesAndNewlines)
                let direct = (try? await KugouMusicAPI.shared.albumSongs(albumID: albumID)) ?? []
                result = direct.isEmpty
                    ? await searchFallbackSongs(
                        queries: [albumSearchQuery, album.name],
                        search: { query in
                            (try? await KugouMusicAPI.shared.searchSongs(keyword: query, limit: 100)) ?? []
                        }
                    )
                    : direct
            case .kuwo:
                result = await searchFallbackSongs(
                    queries: [albumSearchQuery, album.name],
                    search: { query in
                        (try? await AdditionalCatalogSearchAPI.searchKuwo(keyword: query, limit: 100)) ?? []
                    }
                )
            case .migu:
                result = await searchFallbackSongs(
                    queries: [albumSearchQuery, album.name],
                    search: { query in
                        (try? await AdditionalCatalogSearchAPI.searchMigu(keyword: query, limit: 100)) ?? []
                    }
                )
            }
            if !result.isEmpty {
                cache.save(result, for: cacheKey)
            }
            await MainActor.run {
                tracks = result
                isLoading = false
                if result.isEmpty { errorMessage = "未找到专辑歌曲" }
            }
        } catch {
            await MainActor.run {
                if tracks.isEmpty {
                    errorMessage = error.localizedDescription
                } else {
                    BeansLogger.shared.log(
                        "专辑详情后台刷新失败，继续使用缓存 album=\(album.id) error=\(error.localizedDescription)",
                        level: .warn
                    )
                }
                isLoading = false
            }
        }
    }

    private var albumDetailLoadingState: some View {
        BeansDetailSongsLoadingState(coverSize: 92, rowCount: 9)
    }

    private var albumSearchQuery: String {
        let artist = album.artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        return artist.isEmpty ? album.name : "\(artist) \(album.name)"
    }

    private func searchFallbackSongs(
        queries: [String],
        search: (String) async -> [Song]
    ) async -> [Song] {
        guard !normalizedArtist(album.artistName).isEmpty else {
            BeansLogger.shared.log(
                "专辑详情筛选跳过：缺少目标歌手，平台=\(album.source.rawValue) 专辑=\(album.name)",
                level: .debug
            )
            return []
        }
        var tried = Set<String>()
        for query in queries {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, tried.insert(trimmed).inserted else { continue }
            let songs = await search(trimmed)
            let matches = songs.filter(albumSongMatches)
            BeansLogger.shared.log(
                "专辑详情筛选：平台=\(album.source.rawValue) 查询=\(trimmed) 原始=\(songs.count) 专辑歌手匹配=\(matches.count)",
                level: .debug
            )
            if !matches.isEmpty {
                var seen = Set<String>()
                return matches.filter { seen.insert($0.identityKey).inserted }
            }
        }
        // Do not display an artist's unrelated songs just because the album-name
        // search returned something. An empty result is safer than a wrong album.
        return []
    }

    private func albumSongMatches(_ song: Song) -> Bool {
        guard albumNamesMatch(song.album, album.name) else { return false }
        guard !normalizedArtist(album.artistName).isEmpty else { return true }
        return artistsMatch(expected: album.artistName, actual: song.artists)
    }

    private func normalizedArtist(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: #"[（(].*?[）)]"#, with: "", options: .regularExpression)
            .filter { !$0.isWhitespace && !$0.isPunctuation }
    }

    private func artistTokens(_ value: String) -> [String] {
        let separators = CharacterSet(charactersIn: "/／,，、&＆+＋|｜;；")
        return value
            .components(separatedBy: separators)
            .map(normalizedArtist)
            .filter { !$0.isEmpty }
    }

    private func artistsMatch(expected: String, actual: String) -> Bool {
        let expectedTokens = artistTokens(expected)
        let actualTokens = artistTokens(actual)
        guard !expectedTokens.isEmpty, !actualTokens.isEmpty else { return false }

        // A song may add a featured artist, so one exact primary-artist token is
        // sufficient. Prefix matching is limited to longer names to avoid
        // treating an unrelated short name as the same artist.
        return expectedTokens.contains { expectedToken in
            actualTokens.contains { actualToken in
                if expectedToken == actualToken { return true }
                guard min(expectedToken.count, actualToken.count) >= 3 else { return false }
                return expectedToken.hasPrefix(actualToken) || actualToken.hasPrefix(expectedToken)
            }
        }
    }

    private func albumNamesMatch(_ lhs: String, _ rhs: String) -> Bool {
        func normalized(_ value: String) -> String {
            value
                .lowercased()
                .replacingOccurrences(of: "（", with: "(")
                .replacingOccurrences(of: "）", with: ")")
                .replacingOccurrences(of: "[（(].*?[）)]", with: "", options: .regularExpression)
                .filter { !$0.isWhitespace && $0 != "-" && $0 != "·" }
        }
        let a = normalized(lhs)
        let b = normalized(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || a.contains(b) || b.contains(a)
    }
}

// MARK: - 搜索输入框（UIKit 封装：根治中文输入法提交问题）
// SwiftUI TextField 在中文拼音组字中触发 onSubmit 时，binding 可能尚未拿到提交后的文本，
// 且提交瞬间的状态更新可能丢弃未上屏的组字，表现为“输入内容消失、搜索无结果”。
// 改用 UITextField 后：
//  1) 回车/点搜索前先 unmarkText() 强制把拼音提交为汉字，再直接读 field.text（必定最新）；
//  2) 输入内容由 UIKit 持有，SwiftUI 重绘不会清空输入框。

/// 搜索输入框控制器：持有 UITextField 弱引用，供“搜索”按钮与热搜标签操作
final class SearchFieldController {
    weak var textField: UITextField?
    weak var searchBar: UISearchBar?

    /// 提交拼音组字并返回最新文本，同时收起键盘（点“搜索”按钮调用）
    func commit() -> String {
        if let bar = searchBar {
            let field = bar.searchTextField
            if field.markedTextRange != nil {
                field.unmarkText()
            }
            let text = field.text ?? ""
            field.resignFirstResponder()
            return text
        }
        guard let field = textField else { return "" }
        if field.markedTextRange != nil {
            field.unmarkText()
        }
        let text = field.text ?? ""
        field.resignFirstResponder()
        return text
    }

    /// 收起键盘（点热搜标签 / 歌手 / 专辑时调用）
    func dismissKeyboard() {
        textField?.resignFirstResponder()
        searchBar?.searchTextField.resignFirstResponder()
    }
}

/// 原生 UISearchBar 封装，保留中文输入法提交和 SwiftUI 状态同步。
struct NativeSearchBar: UIViewRepresentable {
    @Binding var text: String
    var controller: SearchFieldController? = nil
    var placeholder: String = ""
    var onTextChange: ((String) -> Void)? = nil
    let onSubmit: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UISearchBar {
        let bar = UISearchBar()
        bar.searchBarStyle = .minimal
        bar.placeholder = NSLocalizedString(placeholder, comment: "")
        bar.autocorrectionType = .no
        bar.autocapitalizationType = .none
        bar.spellCheckingType = .no
        bar.returnKeyType = .search
        bar.delegate = context.coordinator
        bar.text = text
        bar.searchTextField.font = BeansFont.appUIFont(15)
        controller?.searchBar = bar
        return bar
    }

    func updateUIView(_ uiView: UISearchBar, context: Context) {
        context.coordinator.parent = self
        if uiView.text != text {
            uiView.text = text
        }
        uiView.placeholder = NSLocalizedString(placeholder, comment: "")
        uiView.searchTextField.font = BeansFont.appUIFont(15)
        controller?.searchBar = uiView
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        var parent: NativeSearchBar

        init(_ parent: NativeSearchBar) {
            self.parent = parent
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            parent.text = searchText
            parent.onTextChange?(searchText)
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            let field = searchBar.searchTextField
            if field.markedTextRange != nil {
                field.unmarkText()
            }
            let value = field.text ?? ""
            parent.text = value
            parent.onSubmit(value)
            field.resignFirstResponder()
        }
    }
}

struct SearchTextField: UIViewRepresentable {
    @Binding var text: String
    let controller: SearchFieldController
    var placeholder: String = ""
    let textColor: UIColor
    let onSubmit: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = NSLocalizedString(placeholder, comment: "")
        field.font = BeansFont.appUIFont(15)
        field.textColor = textColor
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.returnKeyType = .search
        field.clearButtonMode = .never
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        field.text = text
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        controller.textField = field
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        // 同步最新绑定值；同时刷新 coordinator 持有的父视图，保证闭包/绑定始终是最新实例
        context.coordinator.parent = self
        if uiView.text != text {
            uiView.text = text
        }
        uiView.font = BeansFont.appUIFont(15)
        uiView.textColor = textColor
        uiView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        uiView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SearchTextField

        init(_ parent: SearchTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            // 输入法回车：先强制提交拼音再读取，确保拿到完整中文文本
            if field.markedTextRange != nil {
                field.unmarkText()
            }
            let text = field.text ?? ""
            parent.onSubmit(text)
            field.resignFirstResponder()
            return true
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            parent.text = field.text ?? ""
        }
    }
}
