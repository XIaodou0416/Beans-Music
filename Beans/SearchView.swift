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

struct SearchView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("beans.uiStyle") private var uiStyleRaw = BeansUIStyle.liquid.rawValue
    @AppStorage(PlatformPreferenceStore.hidePickerKey) private var hidePlatformPicker = false

    @State private var keyword = ""
    @AppStorage("beans.search.provider") private var providerRaw = SearchProvider.netease.rawValue
    @State private var provider: SearchProvider = .netease
    @ObservedObject private var platformPrefs = PlatformPreferenceStore.shared
    private var searchProviders: [SearchProvider] { platformPrefs.enabledSearchProviders }
    /// 已加载热门搜索的 provider（避免切 tab 反复加载）
    @State private var hotLoadedProvider: SearchProvider?
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

    var body: some View {
        let _ = theme.accent
        ZStack(alignment: .top) {
            // 页面背景：同步开启时显示壁纸/背景色，否则默认氛围渐变
            GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
            // 实例级 UITabBar 清透风格（固定全透明，无需调节）
            TabBarAppearanceConfigurator()
            VStack(spacing: 0) {
                headerTitle
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 10)

                searchField
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                if !hidePlatformPicker {
                    providerPicker
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }

                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            debounceTask?.cancel()
            Task { await startSearch(trimmed) }
        }
        .onAppear {
            provider = platformPrefs.ensureVisible(SearchProvider(rawValue: providerRaw) ?? .netease)
        }
        .onReceive(platformPrefs.changes) { _ in
            let next = platformPrefs.ensureVisible(provider)
            if next != provider {
                provider = next
                hotLoadedProvider = nil
            }
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

    // MARK: - 顶部标题

    private var headerTitle: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("搜索")
                .font(BeansFont.appFont(32, .bold))
                .foregroundStyle(Color.beansLabel)
            Spacer(minLength: 0)
            Menu {
                ForEach(searchProviders) { candidate in
                    Button {
                        BeansHaptics.tap()
                        provider = candidate
                    } label: {
                        Label(LocalizedStringKey(candidate.rawValue), systemImage: candidate == provider ? "checkmark" : candidate.icon)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if let imageName = provider.brandImageName {
                        Image(imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 15, height: 15)
                    } else {
                        Image(systemName: provider.icon)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text(LocalizedStringKey(provider.rawValue))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(BeansFont.appFont(12, .semibold))
                .foregroundStyle(Color.beansComment)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background { BeansGlass(shape: Capsule()) }
            }
            .disabled(searchProviders.count < 2)
        }
    }

    // MARK: - 内容区（热搜 / 分类+结果 固定占满剩余高度，切换不引起布局跳动）

    @ViewBuilder
    private var contentArea: some View {
        if keyword.isEmpty {
            hotSection
        } else {
            VStack(spacing: 0) {
                typeTabs
                resultsArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 搜索框（液态玻璃胶囊）

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.beansComment)
            // UIKit 输入框：回车/点搜索时先 unmarkText 强制提交拼音，再读取最新文本，
            // 根治 SwiftUI TextField 在中文组字中 onSubmit 后输入消失、搜索无结果的问题
            SearchTextField(
                text: $keyword,
                controller: searchController,
                placeholder: beansLocalized("搜索歌曲、歌手、专辑", "Search songs, artists, or albums"),
                textColor: UIColor.beansLabel,
                onSubmit: { text in
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    debounceTask?.cancel()
                    historyStore.record(trimmed)
                    Task { await startSearch(trimmed) }
                }
            )
            .frame(height: 32)
            .frame(maxWidth: .infinity)
            ZStack {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.beansAmber)
                    .opacity(searching ? 1 : 0)
            }
            .frame(width: 20, height: 22)
            .animation(nil, value: searching)
            ZStack {
                Button {
                    keyword = ""
                    songResults = []
                    artistResults = []
                    albumResults = []
                    errorMessage = nil
                    debounceTask?.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.beansComment.opacity(0.85))
                }
                .buttonStyle(.plain)
                .opacity(keyword.isEmpty ? 0 : 1)
                .disabled(keyword.isEmpty)
            }
            .frame(width: 20, height: 22)
            Button {
                // 先提交拼音再读取，避免组字中读到旧值或输入被清空
                let text = searchController.commit()
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                debounceTask?.cancel()
                historyStore.record(trimmed)
                Task { await startSearch(trimmed) }
            } label: {
                Text("搜索")
                    .font(BeansFont.appFont(13, .semibold))
                    .foregroundStyle(Color.beansAmber)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 6)
                    .background { BeansGlass(shape: Capsule()) }
            }
            .buttonStyle(GlassPressButtonStyle(scale: 0.9))
            .frame(width: 54, height: 30)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 6)
        .background {
            BeansGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .beansCardShadow(radius: 4, y: 2)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 平台选择（等宽分段控件）

    private var providerPicker: some View {
        HStack(spacing: 4) {
            ForEach(searchProviders) { p in
                Button {
                    BeansHaptics.tap()
                    if provider != p { provider = p }
                } label: {
                    HStack(spacing: 6) {
                        if let imageName = p.brandImageName {
                            Image(imageName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: p.icon)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(LocalizedStringKey(p.rawValue))
                            .font(BeansFont.appFont(13, .semibold))
                    }
                    .foregroundStyle(provider == p ? Color.white : Color.beansComment)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if provider == p {
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
    }

    // MARK: - 分类选择（歌曲 / 歌手 / 专辑）

    private var typeTabs: some View {
        HStack(spacing: 4) {
            ForEach(SearchResultType.allCases) { type in
                Button {
                    BeansHaptics.tap()
                    guard resultType != type else { return }
                    resultType = type
                    let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    // 切换分类：清空该分类旧结果并立即进入加载态，避免显示过期数据或空态闪烁
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
                } label: {
                        Text(LocalizedStringKey(type.rawValue))
                        .font(BeansFont.appFont(13, .semibold))
                        .foregroundStyle(resultType == type ? Color.beansLabel : Color.beansComment)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if resultType == type {
                                Capsule().fill(.white.opacity(colorScheme == .dark ? 0.24 : 0.20))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            BeansSurface(shape: Capsule())
        }
        .clipShape(Capsule())
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    // MARK: - 热搜（排名卡片）

    private var hotSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SearchHistorySection { word in
                    keyword = word
                    searchController.dismissKeyboard()
                    debounceTask?.cancel()
                    historyStore.record(word)
                    Task { await startSearch(word) }
                }
                SectionHeader(title: provider == .netease ? "网易云音乐热搜" : provider == .qq ? "QQ音乐热搜" : "酷狗音乐热搜")
                if hotWords.isEmpty {
                    LoadingStateView()
                } else {
                    if #available(iOS 16, *) {
                        FlowLayout(spacing: 10) {
                            ForEach(Array(hotWords.enumerated()), id: \.offset) { index, word in
                                hotTag(index: index, word: word)
                            }
                        }
                    } else {
                        // iOS 15 降级：自适应网格实现流式标签
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], alignment: .leading, spacing: 10) {
                            ForEach(Array(hotWords.enumerated()), id: \.offset) { index, word in
                                hotTag(index: index, word: word)
                            }
                        }
                    }
                }
                Spacer().frame(height: 130)
            }
            .padding(.horizontal, 20)
        }
        .beansScrollIndicatorsHidden()
        .beansScrollDismissesKeyboard()
    }

    /// 热搜前三名渐变配色（更亮眼：橙红 / 金黄 / 冰蓝）
    private let hotRankColors: [[Color]] = [
        [Color(red: 1.00, green: 0.62, blue: 0.18), Color(red: 0.95, green: 0.25, blue: 0.18)],
        [Color(red: 1.00, green: 0.82, blue: 0.30), Color(red: 0.98, green: 0.56, blue: 0.12)],
        [Color(red: 0.55, green: 0.85, blue: 1.00), Color(red: 0.30, green: 0.52, blue: 0.98)],
    ]
    private let hotRankIcons = ["crown.fill", "flame.fill", "sparkles"]

    /// 热搜标签：前三名渐变发光圆标（更亮眼），其余为普通序号
    private func hotTag(index: Int, word: String) -> some View {
        let top3 = index < 3
        return Button {
            BeansHaptics.tap()
            keyword = word
            searchController.dismissKeyboard()
            debounceTask?.cancel()
            Task { await startSearch(word) }
        } label: {
            HStack(spacing: 7) {
                if top3 {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: hotRankColors[index],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 24, height: 24)
                            .shadow(color: hotRankColors[index][0].opacity(0.6), radius: 6, y: 2)
                            .overlay {
                                Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1)
                            }
                        Image(systemName: hotRankIcons[index])
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                } else {
                    Text("\(index + 1)")
                        .font(BeansFont.appFont(11, .bold, .rounded))
                        .foregroundStyle(Color.beansComment)
                        .frame(width: 18, height: 18)
                }
                Text(word)
                    .font(BeansFont.appFont(top3 ? 15 : 14, top3 ? .bold : .medium))
                    .foregroundStyle(top3 ? Color.beansLabel : Color.beansComment)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                BeansGlass(shape: Capsule())
            }
            .overlay {
                if top3 {
                    Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
                }
            }
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.92))
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

    private var songResultsArea: some View {
        Group {
            if let errorMessage, songResults.isEmpty {
                ErrorStateView(message: errorMessage) { submitSearch() }
            } else if searching && songResults.isEmpty {
                LoadingStateView()
            } else if songResults.isEmpty {
                EmptyStateView(icon: "music.note", text: "\(provider.rawValue)未找到相关歌曲")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Text(beansLocalized("找到 \(songResults.count) 首 · \(provider.rawValue)", "Found \(songResults.count) songs · \(beansPlatformName(provider))"))
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
                .beansScrollIndicatorsHidden()
                .beansScrollDismissesKeyboard()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                LoadingStateView()
            } else if artistResults.isEmpty {
                EmptyStateView(icon: "person.crop.circle", text: "\(provider.rawValue)未找到相关歌手")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        HStack {
                            Text(beansLocalized("找到 \(artistResults.count) 位 · \(provider.rawValue)", "Found \(artistResults.count) artists · \(beansPlatformName(provider))"))
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
                .beansScrollIndicatorsHidden()
                .beansScrollDismissesKeyboard()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                LoadingStateView()
            } else if albumResults.isEmpty {
                EmptyStateView(icon: "square.stack", text: "\(provider.rawValue)未找到相关专辑")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        HStack {
                            Text(beansLocalized("找到 \(albumResults.count) 张 · \(provider.rawValue)", "Found \(albumResults.count) albums · \(beansPlatformName(provider))"))
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
                .beansScrollIndicatorsHidden()
                .beansScrollDismissesKeyboard()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @State private var tracks: [Song] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                if isLoading {
                    LoadingStateView()
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
        .task { await load() }
    }

    private func load() async {
        await MainActor.run {
            isLoading = true
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
                result = await searchFallbackSongs(
                    queries: [albumSearchQuery, album.name],
                    search: { query in
                        (try? await QQMusicAPI.shared.searchSongs(keyword: query, limit: 100)) ?? []
                    }
                )
            case .kugou:
                result = await searchFallbackSongs(
                    queries: [albumSearchQuery, album.name],
                    search: { query in
                        (try? await KugouMusicAPI.shared.searchSongs(keyword: query, limit: 100)) ?? []
                    }
                )
            }
            await MainActor.run {
                tracks = result
                isLoading = false
                if result.isEmpty { errorMessage = "未找到专辑歌曲" }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
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

    /// 提交拼音组字并返回最新文本，同时收起键盘（点“搜索”按钮调用）
    func commit() -> String {
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
