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

enum SearchResultType: String, CaseIterable, Identifiable {
    case song = "歌曲"
    case artist = "歌手"
    case album = "专辑"

    var id: String { rawValue }
}

/// 搜索页可用的平台不等同于首页或账号体系的平台。附加目录只在搜索页出现，
/// 不会改变现有首页、歌单和登录流程。
private enum SearchCatalogProvider: String, CaseIterable, Identifiable, Hashable {
    case netease = "网易云音乐"
    case qq = "QQ音乐"
    case kugou = "酷狗音乐"
    case kuwo = "酷我音乐"
    case migu = "咪咕音乐"

    var id: String { rawValue }

    var englishName: String {
        switch self {
        case .netease: return "NetEase Cloud Music"
        case .qq: return "QQ Music"
        case .kugou: return "Kugou Music"
        case .kuwo: return "Kuwo Music"
        case .migu: return "Migu Music"
        }
    }

    var songSource: SongSource {
        switch self {
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
        if #available(iOS 26, *) {
            GlassEffectContainer {
                fieldContent
                    .frame(minHeight: 56)
                    .glassEffect(.regular.interactive(), in: Capsule())
            }
        } else {
            legacyField
        }
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
        .contentShape(Capsule())
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
    @AppStorage("beans.search.catalogProvider.v2") private var providerRaw = SearchCatalogProvider.netease.rawValue
    @State private var provider: SearchCatalogProvider = .netease
    private var searchProviders: [SearchCatalogProvider] { SearchCatalogProvider.allCases }
    /// 已加载热门搜索的 provider（避免切 tab 反复加载）
    @State private var hotLoadedProvider: SearchCatalogProvider?
    @State private var resultType: SearchResultType = .song
    @State private var songResults: [Song] = []
    @State private var artistResults: [Artist] = []
    @State private var albumResults: [Album] = []
    @State private var hotWords: [String] = []
    @State private var searching = false
    @State private var errorMessage: String?
    @State private var showAddToPlaylist: Song?
    @State private var selectedArtist: Artist?
    @State private var selectedAlbum: Album?
    @ObservedObject private var historyStore = SearchHistoryStore.shared
    @State private var debounceTask: Task<Void, Never>?
    @State private var searchTask: Task<Void, Never>?
    /// UIKit 输入框控制器（提交拼音、收起键盘等由它统一处理）
    @State private var searchController = SearchFieldController()

    private var isNativeClean: Bool {
        BeansUIStyle(rawValue: uiStyleRaw) == .nativeClean
    }

    private var usesTabletHotSearchLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        BeansNavigationStack {
            pageContent
                .navigationTitle(keyword.isEmpty ? "搜索" : keyword)
                .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: provider) {
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
                errorMessage = nil
                return
            }
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                await startSearch(trimmed)
            }
        }
        .onChange(of: provider) { _ in
            providerRaw = provider.rawValue
            if !provider.supportsDetailedResults { resultType = .song }
            let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            debounceTask?.cancel()
            Task { await startSearch(trimmed) }
        }
        .onAppear {
            provider = SearchCatalogProvider(rawValue: providerRaw) ?? .netease
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
                    contentArea
                    Color.clear.frame(height: 74)
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .beansScrollIndicatorsHidden()
            .beansScrollDismissesKeyboard()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            searchField
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .zIndex(20)
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
                    legacyProviderPicker
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
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
        }
    }

    private var legacyProviderPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(searchProviders) { candidate in
                    providerButton(candidate)
                }
            }
            .padding(4)
            .background { BeansGlass(shape: Capsule(), forceLiquid: true) }
            .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var legacyContentArea: some View {
        if keyword.isEmpty {
            hotSection
        } else {
            VStack(spacing: 0) {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        Task { await startSearch(trimmed) }
    }

    // MARK: - 搜索结果平台选择

    private var resultProviderPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(searchProviders) { candidate in
                    providerButton(candidate)
                }
            }
            .padding(4)
            .background { BeansGlass(shape: Capsule(), forceLiquid: true) }
            .clipShape(Capsule())
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
            Text(LocalizedStringKey(candidate.rawValue))
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
        HStack(spacing: 4) {
            ForEach(availableResultTypes) { type in
                Button {
                    selectResultType(type)
                } label: {
                    Text(LocalizedStringKey(type.rawValue))
                        .font(BeansFont.appFont(13, .semibold))
                        .foregroundStyle(resultType == type ? Color.white : Color.beansLabel)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if resultType == type {
                                Capsule().fill(Color.beansAmber)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background { BeansGlass(shape: Capsule(), forceLiquid: true) }
        .clipShape(Capsule())
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private var availableResultTypes: [SearchResultType] {
        provider.supportsDetailedResults ? SearchResultType.allCases : [.song]
    }

    private func selectResultType(_ type: SearchResultType) {
        BeansHaptics.tap()
        guard resultType != type else { return }
        resultType = type
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        debounceTask?.cancel()
        searchTask?.cancel()
        switch type {
        case .song: songResults = []
        case .artist: artistResults = []
        case .album: albumResults = []
        }
        errorMessage = nil
        searching = true
        Task { await startSearch(trimmed) }
    }

    // MARK: - 热门搜索

    private var hotSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Color.beansComment.opacity(0.72))
                    .padding(.top, 44)
                Text("搜索歌曲、歌手或专辑")
                    .font(BeansFont.appFont(18, .semibold))
                    .foregroundStyle(Color.beansLabel)
                Text("使用底部搜索框开始搜索")
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
                    Text(LocalizedStringKey(provider.rawValue))
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
            ForEach(0..<10, id: \.self) { _ in
                BeansShimmerSkeleton(cornerRadius: 22)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }

    // MARK: - 结果区

    @ViewBuilder
    private var resultsArea: some View {
        switch resultType {
        case .song: songResultsArea
        case .artist: artistResultsArea
        case .album: albumResultsArea
        }
    }

    private var searchResultsLoadingState: some View {
        VStack(alignment: .leading, spacing: 8) {
            BeansShimmerSkeleton(cornerRadius: 5)
                .frame(width: resultType == .song ? 160 : 132, height: 12)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            BeansSongRowsLoadingState(
                rowCount: 8,
                coverSize: resultType == .artist ? 46 : 46,
                showsRank: false,
                horizontalPadding: 20
            )
        }
        .padding(.top, 4)
        .padding(.bottom, 180)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        ForEach(Array(songResults.enumerated()), id: \.element.identityKey) { index, song in
                            SongCell(song: song, suppressNativeCleanRowGlass: isNativeClean) {
                                BeansHaptics.tap()
                                player.play(songs: songResults, startAt: index)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background {
                                BeansSurface(shape: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                VStack {
                    LazyVStack(spacing: 8) {
                        HStack {
                            Text(beansLocalized("找到 \(artistResults.count) 位 · \(provider.rawValue)", "Found \(artistResults.count) artists · \(provider.englishName)"))
                                .font(BeansFont.appFont(12))
                                .foregroundStyle(Color.beansComment)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .truncationMode(.tail)
                                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                .layoutPriority(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        ForEach(artistResults) { artist in
                            Button {
                                BeansHaptics.tap()
                                searchController.dismissKeyboard()
                                selectedArtist = artist
                            } label: {
                                HStack(spacing: 12) {
                                    CoverImage(url: artist.coverURL, size: 46, cornerRadius: 23)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(artist.name)
                                            .font(BeansFont.appFont(15, .medium))
                                            .foregroundStyle(Color.beansLabel)
                                            .lineLimit(1)
                                        Text("查看歌手主页")
                                            .font(BeansFont.appFont(12))
                                            .foregroundStyle(Color.beansComment)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.beansComment)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                                .background {
                                BeansSurface(shape: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                            .buttonStyle(GlassPressButtonStyle(scale: 0.97))
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

    private var albumResultsArea: some View {
        Group {
            if let errorMessage, albumResults.isEmpty {
                ErrorStateView(message: errorMessage) { submitSearch() }
            } else if searching && albumResults.isEmpty {
                searchResultsLoadingState
            } else if albumResults.isEmpty {
                EmptyStateView(icon: "square.stack", text: "\(provider.rawValue)未找到相关专辑")
            } else {
                VStack {
                    LazyVStack(spacing: 8) {
                        HStack {
                            Text(beansLocalized("找到 \(albumResults.count) 张 · \(provider.rawValue)", "Found \(albumResults.count) albums · \(provider.englishName)"))
                                .font(BeansFont.appFont(12))
                                .foregroundStyle(Color.beansComment)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .truncationMode(.tail)
                                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                .layoutPriority(1)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        ForEach(albumResults) { album in
                            Button {
                                BeansHaptics.tap()
                                searchController.dismissKeyboard()
                                selectedAlbum = album
                            } label: {
                                HStack(spacing: 12) {
                                    CoverImage(url: album.coverURL, size: 46, cornerRadius: 10)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(album.name)
                                            .font(BeansFont.appFont(15, .medium))
                                            .foregroundStyle(Color.beansLabel)
                                            .lineLimit(1)
                                        Text(album.artistName.isEmpty ? "未知歌手" : album.artistName)
                                            .font(BeansFont.appFont(12))
                                            .foregroundStyle(Color.beansComment)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.beansComment)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                                .background {
                                BeansSurface(shape: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                            .buttonStyle(GlassPressButtonStyle(scale: 0.97))
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

    // MARK: - 动作

    /// 重新搜索（错误重试按钮调用：读取当前输入框文本）
    private func submitSearch() {
        debounceTask?.cancel()
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        historyStore.record(trimmed)
        Task { await startSearch(trimmed) }
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
        if provider == .qq {
            if let words = try? await QQMusicAPI.shared.hotKeys() {
                hotWords = words
            }
        } else if provider == .kugou {
            hotWords = await KugouMusicAPI.shared.hotWords()
        } else if provider == .kuwo || provider == .migu {
            hotWords = (try? await AdditionalCatalogSearchAPI.hotKeywords(for: provider.songSource)) ?? []
        } else if let words = try? await NetEaseAPI.shared.hotSearch() {
            hotWords = words
        }
    }

    private func startSearch(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchTask?.cancel()
        let selectedProvider = provider
        let selectedType = resultType
        searchTask = Task {
            await MainActor.run {
                searching = true
                errorMessage = nil
            }
            BeansLogger.shared.log("搜索：\(selectedProvider.rawValue) [\(selectedType.rawValue)] \(trimmed)", level: .info)
            defer {
                if !Task.isCancelled {
                    Task { @MainActor in searching = false }
                }
            }
            do {
                switch (selectedProvider, selectedType) {
                case (.netease, .song):
                    let songs = try await NetEaseAPI.shared.search(keyword: trimmed, limit: 40)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        songResults = songs
                        if !songs.isEmpty { BeansHaptics.success() }
                    }
                case (.netease, .artist):
                    let artists = try await NetEaseAPI.shared.searchArtists(keyword: trimmed)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { artistResults = artists }
                case (.netease, .album):
                    let albums = try await NetEaseAPI.shared.searchAlbums(keyword: trimmed)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { albumResults = albums }
                case (.qq, .song):
                    let songs = try await QQMusicAPI.shared.searchSongs(keyword: trimmed)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        songResults = songs
                        if !songs.isEmpty { BeansHaptics.success() }
                    }
                case (.qq, .artist):
                    let artists = try await QQMusicAPI.shared.searchArtists(keyword: trimmed)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { artistResults = artists }
                case (.qq, .album):
                    let albums = try await QQMusicAPI.shared.searchAlbums(keyword: trimmed)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { albumResults = albums }
                case (.kugou, .song):
                    let songs = try await KugouMusicAPI.shared.searchSongs(keyword: trimmed, limit: 40)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        songResults = songs
                        if !songs.isEmpty { BeansHaptics.success() }
                    }
                case (.kugou, .artist):
                    let artists = try await KugouMusicAPI.shared.searchArtists(keyword: trimmed)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { artistResults = artists }
                case (.kugou, .album):
                    let albums = try await KugouMusicAPI.shared.searchAlbums(keyword: trimmed)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { albumResults = albums }
                case (.kuwo, .song):
                    let songs = try await AdditionalCatalogSearchAPI.searchKuwo(keyword: trimmed, limit: 40)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        songResults = songs
                        if !songs.isEmpty { BeansHaptics.success() }
                    }
                case (.migu, .song):
                    let songs = try await AdditionalCatalogSearchAPI.searchMigu(keyword: trimmed, limit: 40)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        songResults = songs
                        if !songs.isEmpty { BeansHaptics.success() }
                    }
                case (.kuwo, .artist):
                    let artists = try await AdditionalCatalogSearchAPI.searchKuwoArtists(keyword: trimmed)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { artistResults = artists }
                case (.kuwo, .album):
                    let albums = try await AdditionalCatalogSearchAPI.searchKuwoAlbums(keyword: trimmed)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { albumResults = albums }
                case (.migu, .artist):
                    let artists = try await AdditionalCatalogSearchAPI.searchMiguArtists(keyword: trimmed)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { artistResults = artists }
                case (.migu, .album):
                    let albums = try await AdditionalCatalogSearchAPI.searchMiguAlbums(keyword: trimmed)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { albumResults = albums }
                }
                let count = await MainActor.run {
                    selectedType == .song ? songResults.count : (selectedType == .artist ? artistResults.count : albumResults.count)
                }
                BeansLogger.shared.log("搜索完成：\(selectedProvider.rawValue) [\(selectedType.rawValue)] \(trimmed) 结果=\(count)", level: .info)
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
                BeansLogger.shared.log("搜索失败：\(selectedProvider.rawValue) \(trimmed) - \(error.localizedDescription)", level: .error)
            }
        }
        await searchTask?.value
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

    var body: some View {
        Group {
            if embeddedInNavigation {
                albumPage
            } else {
                BeansNavigationStack { albumPage }
            }
        }
        .task { await load() }
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
                            GlassButton(title: "播放全部", systemName: "play.fill", prominent: true) {
                                player.play(songs: tracks, startAt: 0)
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    ForEach(Array(tracks.enumerated()), id: \.element.identityKey) { index, song in
                        SongCell(song: song, glassRow: true, playbackContext: tracks, playbackIndex: index) {
                            player.play(songs: tracks, startAt: index)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .beansScrollContentBackgroundHidden()
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
            case .kuwo, .migu:
                throw NSError(
                    domain: "BeansAlbum",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "当前平台暂不支持专辑详情"]
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
