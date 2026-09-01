import SwiftUI
import UIKit

struct DiscoverView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerManager
    @ObservedObject private var platformPrefs = PlatformPreferenceStore.shared

    @State private var topLists: [TopList] = []
    @State private var dailySongs: [Song] = []
    @State private var personalized: [Playlist] = []

    @State private var loading = true
    @State private var errorMessage: String?
    @State private var selectedTopList: TopList?
    @State private var selectedPlaylist: Playlist?
    @State private var showDailyList = false
    @State private var showHomePlatformMenu = false
    @State private var showSectionSort = false
    /// 主页板块顺序（每日推荐 / 排行榜 / 歌单广场，可自定义）
    @State private var homeOrder = SectionOrderStore.load(SectionOrderStore.homeKey, defaults: SectionOrderStore.homeDefaults)

    /// 三个平台都保留每日推荐、排行榜和歌单板块，QQ 歌单板块展示官网推荐的热门歌单。
    private var availableSections: [String] { SectionOrderStore.homeDefaults }
    /// 首页数据源：记住上次选择，下次打开仍保持该平台（默认网易云）
    @AppStorage("beans.homeSource") private var homeSourceRaw = SearchProvider.netease.rawValue
    @AppStorage("beans.homeGreetingText") private var homeGreetingText = ""
    @AppStorage("beans.homeGreetingSize") private var homeGreetingSize = 30.0
    @AppStorage("beans.homeGreetingHeight") private var homeGreetingHeight = 0.0
    @AppStorage("beans.homeGreetingColorHex") private var homeGreetingColorHex = ""
    @AppStorage("beans.homeGreetingLine1Size") private var homeGreetingLine1Size = 0.0
    @AppStorage("beans.homeGreetingLine2Size") private var homeGreetingLine2Size = 0.0
    @AppStorage("beans.homeGreetingLine3Size") private var homeGreetingLine3Size = 0.0
    @AppStorage("beans.homeGreetingLine1ColorHex") private var homeGreetingLine1ColorHex = ""
    @AppStorage("beans.homeGreetingLine2ColorHex") private var homeGreetingLine2ColorHex = ""
    @AppStorage("beans.homeGreetingLine3ColorHex") private var homeGreetingLine3ColorHex = ""
    @AppStorage("beans.homeGreetingLine1OffsetY") private var homeGreetingLine1OffsetY = 0.0
    @AppStorage("beans.homeGreetingLine2OffsetY") private var homeGreetingLine2OffsetY = 0.0
    @AppStorage("beans.homeGreetingLine3OffsetY") private var homeGreetingLine3OffsetY = 0.0
    @AppStorage("beans.homeGreetingLine1GradientStartHex") private var homeGreetingLine1GradientStartHex = ""
    @AppStorage("beans.homeGreetingLine2GradientStartHex") private var homeGreetingLine2GradientStartHex = ""
    @AppStorage("beans.homeGreetingLine3GradientStartHex") private var homeGreetingLine3GradientStartHex = ""
    @AppStorage("beans.homeGreetingLine1GradientEndHex") private var homeGreetingLine1GradientEndHex = ""
    @AppStorage("beans.homeGreetingLine2GradientEndHex") private var homeGreetingLine2GradientEndHex = ""
    @AppStorage("beans.homeGreetingLine3GradientEndHex") private var homeGreetingLine3GradientEndHex = ""
    @AppStorage("beans.homeGreetingGlowEnabled") private var homeGreetingGlowEnabled = false
    @AppStorage("beans.homeGreetingGlowIntensity") private var homeGreetingGlowIntensity = 0.45
    @AppStorage("beans.homeGreetingUnderline") private var homeGreetingUnderline = false
    @AppStorage("beans.homeGreetingGradient") private var homeGreetingGradient = false
    @AppStorage("beans.homeGreetingGradientStartHex") private var homeGreetingGradientStartHex = ""
    @AppStorage("beans.homeGreetingGradientEndHex") private var homeGreetingGradientEndHex = ""
    @AppStorage("beans.homeGreetingFont") private var homeGreetingFontName = ""
    @AppStorage("beans.homeHideUsername") private var homeHideUsername = false
    @AppStorage("beans.pauseHomeRendering") private var homeRenderingPaused = false
    @AppStorage("beans.homeHeaderHideSort") private var homeHeaderHideSort = false
    @AppStorage("beans.homeHeaderHideRefresh") private var homeHeaderHideRefresh = true
    @AppStorage(PlatformPreferenceStore.hidePickerKey) private var hidePlatformPicker = false
    @AppStorage("beans.uiStyle") private var uiStyleRaw = BeansUIStyle.liquid.rawValue
    @AppStorage("beans.remoteAnnouncement.enabled") private var remoteAnnouncementEnabled = false
    @AppStorage("beans.remoteAnnouncement.text") private var remoteAnnouncementText = ""
    @AppStorage("beans.remoteAnnouncement.imageURL") private var remoteAnnouncementImageURL = ""
    @AppStorage("beans.remoteAnnouncement.mediaURL") private var remoteAnnouncementMediaURL = ""
    @AppStorage("beans.remoteAnnouncement.mediaType") private var remoteAnnouncementMediaType = ""
    @AppStorage("beans.remoteAnnouncement.textColor") private var remoteAnnouncementTextColor = ""
    @AppStorage("beans.showSongVIPBadge") private var showSongVIPBadge = true
    private var homeProviders: [SearchProvider] { platformPrefs.enabledSearchProviders }
    /// 首页数据源：网易云 / QQ音乐（与搜索页同一控件样式）
    private var source: SearchProvider {
        guard let saved = SearchProvider(rawValue: homeSourceRaw), homeProviders.contains(saved) else {
            return homeProviders.first ?? .netease
        }
        return saved
    }
    private var isNativeClean: Bool { BeansUIStyle(rawValue: uiStyleRaw) == .nativeClean }

    @State private var qqTopLists: [QQTopInfo] = []
    @State private var selectedQQTopList: QQTopInfo?
    @State private var kugouTopLists: [KugouTopInfo] = []
    @State private var selectedKugouTopList: KugouTopInfo?
    @State private var selectedQQPlaylist: Playlist?
    /// 排行榜展开状态：收起显示前 3，展开显示前 10
    @State private var ranksExpanded = false
    /// 歌单广场展开状态：收起显示前 6，展开显示全部
    @State private var playlistsExpanded = false
    /// 首页加载去重：SwiftUI 视图刷新时 .task 可能被重复触发，避免网络请求风暴。
    @State private var activeLoadKey: String?
    @State private var lastLoadedKey = ""
    @State private var lastLoadedAt = Date.distantPast
    /// 首次启动免责声明：确认进入后若加载失败自动刷新
    @AppStorage("beans.disclaimerAccepted") private var disclaimerAccepted = false
    /// 网易云歌单广场当前分类（「全部」展示官方精品歌单）
    @State private var neteaseCat = "全部"
    /// 官方歌单分类列表
    @State private var playlistCats: [String] = []

    var body: some View {
        let _ = theme.accent
        ZStack {
            // 主页背景：壁纸/背景色永远在发现页生效（homeMode），同步开启时其他页面也生效
            GlassBackdrop(customColor: theme.customBackground, homeMode: true)
            // 实例级 UITabBar 清透风格（固定全透明，无需调节）
            TabBarAppearanceConfigurator()
            ScrollView {
                if !homeRenderingPaused {
                    ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: isNativeClean ? 34 : 26) {
                        header
                        if remoteAnnouncementEnabled,
                           !remoteAnnouncementText.isEmpty || !remoteAnnouncementMediaURL.isEmpty || !remoteAnnouncementImageURL.isEmpty {
                            remoteAnnouncementBanner
                        }
                        if !hidePlatformPicker {
                            providerPicker
                        }
                        if let errorMessage {
                            ErrorStateView(message: errorMessage) {
                                Task { await load(force: true) }
                            }
                        } else if loading {
                            LoadingStateView()
                        } else {
                            // 板块按用户自定义顺序渲染（可拖拽排序）
                            ForEach(homeOrder.filter { availableSections.contains($0) }, id: \.self) { key in
                                switch key {
                                case "每日推荐":
                                    if !dailySongs.isEmpty {
                                        dailySection
                                            .sectionEntrance(delay: 0)
                                    }
                                case "排行榜":
                                    if hasRankData { topListsSection.sectionEntrance(delay: 0.08) }
                                case "歌单广场":
                                    if source == .qq || !personalized.isEmpty {
                                        personalizedSection.sectionEntrance(delay: 0.16)
                                    }
                                default:
                                    EmptyView()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, isNativeClean ? 24 : 16)
                    .padding(.top, isNativeClean ? 32 : 8)
                    .padding(.bottom, 190)
                    .frame(maxWidth: 860)
                    .frame(maxWidth: .infinity)
                    }
                }
            }
            .beansScrollIndicatorsHidden()
            .refreshable {
                guard !homeRenderingPaused else { return }
                await load(force: true)
            }
            .task(id: "\(source.rawValue)-\(homeRenderingPaused)") {
                guard !homeRenderingPaused else { return }
                await load(force: false)
            }
            .onAppear {
                guard !homeRenderingPaused else { return }
                guard let saved = SearchProvider(rawValue: homeSourceRaw), homeProviders.contains(saved) else {
                    homeSourceRaw = (homeProviders.first ?? .netease).rawValue
                    return
                }
            }
            .onReceive(platformPrefs.changes) { _ in
                guard !homeRenderingPaused else { return }
                let next = platformPrefs.ensureVisible(source)
                if next != source {
                    homeSourceRaw = next.rawValue
                }
            }
            .onChange(of: source) { _ in
                guard !homeRenderingPaused else { return }
                homeOrder = SectionOrderStore.load(SectionOrderStore.homeKey, defaults: availableSections)
            }
            .onChange(of: disclaimerAccepted) { accepted in
                guard !homeRenderingPaused else { return }
                // 免责声明确认进入后：若首页加载失败则自动刷新（无需手动下拉）
                if accepted, errorMessage != nil {
                    Task { await load(force: true) }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .beansNeteaseLoginDidUpdate)) { _ in
                guard !homeRenderingPaused else { return }
                guard platformPrefs.isEnabled(SearchProvider.netease) else { return }
                reloadAfterLoginUpdate(.netease)
            }
            .onReceive(NotificationCenter.default.publisher(for: .beansQQLoginDidUpdate)) { _ in
                guard !homeRenderingPaused else { return }
                guard platformPrefs.isEnabled(SearchProvider.qq) else { return }
                reloadAfterLoginUpdate(.qq)
            }
            .onReceive(NotificationCenter.default.publisher(for: .beansKugouLoginDidUpdate)) { _ in
                guard !homeRenderingPaused else { return }
                guard platformPrefs.isEnabled(SearchProvider.kugou) else { return }
                reloadAfterLoginUpdate(.kugou)
            }
            .sheet(item: $selectedTopList) { topList in
                TopListDetailView(topList: topList)
                    .environmentObject(player)
                    .environmentObject(auth)
            }
            .sheet(item: $selectedPlaylist) { playlist in
                PlaylistView(playlist: playlist)
                    .environmentObject(player)
                    .environmentObject(auth)
            }
            .sheet(item: $selectedQQTopList) { info in
                QQTopListDetailView(topID: info.id, name: info.name)
                    .environmentObject(player)
                    .environmentObject(auth)
            }
            .sheet(item: $selectedKugouTopList) { info in
                KugouTopListDetailView(topList: info)
                    .environmentObject(player)
            }
            .sheet(item: $selectedQQPlaylist) { playlist in
                PlaylistView(playlist: playlist)
                    .environmentObject(player)
                    .environmentObject(auth)
            }
            .sheet(isPresented: $showDailyList) {
                DailySongsSheet(songs: dailySongs)
                    .environmentObject(player)
                    .environmentObject(auth)
            }
            .sheet(isPresented: $showSectionSort) {
                SectionOrderSheet(
                    title: "主页板块排序",
                    sections: availableSections,
                    order: $homeOrder,
                    platformOrder: Binding(
                        get: { platformPrefs.orderedRaw },
                        set: { platformPrefs.orderedRaw = $0 }
                    )
                )
                    .onDisappear { SectionOrderStore.save(SectionOrderStore.homeKey, homeOrder) }
            }
        }
    }

    private var remoteAnnouncementBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "megaphone.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.beansAmber)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 8) {
                let mediaURL = remoteAnnouncementMediaURL.isEmpty ? remoteAnnouncementImageURL : remoteAnnouncementMediaURL
                if let url = URL(string: mediaURL), !mediaURL.isEmpty {
                    if remoteAnnouncementMediaType.lowercased() == "video" {
                        AnnouncementVideoView(url: url)
                            .frame(maxWidth: .infinity)
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFit()
                            } else if phase.error == nil {
                                ProgressView().frame(maxWidth: .infinity, minHeight: 60)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                Text(remoteAnnouncementText)
                    .foregroundStyle(remoteAnnouncementColor)
            }
                .font(BeansFont.appFont(13, .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background {
            BeansGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .beansCardShadow(radius: 8, y: 3)
    }

    private var remoteAnnouncementColor: Color {
        Color(hex: remoteAnnouncementTextColor) ?? Color.beansLabel
    }

    /// 顶部问候区：大标题 + 刷新按钮
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(greetingLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(BeansFont.greetingFont(isNativeClean ? max(42, greetingLineSize(index)) : greetingLineSize(index), .bold))
                                .foregroundStyle(greetingLineStyle(index))
                                .overlay(alignment: .bottomLeading) {
                                    if homeGreetingUnderline {
                                        Rectangle()
                                            .fill(greetingLineColor(index))
                                            .frame(height: 1.5)
                                            .offset(y: 2)
                                    }
                                }
                                .shadow(
                                    color: homeGreetingGlowEnabled
                                        ? greetingLineColor(index).opacity(min(1, 0.75 * homeGreetingGlowIntensity))
                                        : .clear,
                                    radius: homeGreetingGlowEnabled
                                        ? 8 + 28 * homeGreetingGlowIntensity
                                        : 0
                                )
                                .shadow(
                                    color: homeGreetingGlowEnabled
                                        ? greetingLineColor(index).opacity(min(1, 0.95 * homeGreetingGlowIntensity))
                                        : .clear,
                                    radius: homeGreetingGlowEnabled
                                        ? 2 + 10 * homeGreetingGlowIntensity
                                        : 0
                                )
                                .fixedSize(horizontal: false, vertical: true)
                                .offset(y: greetingLineOffsetY(index))
                        }
                    }
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.55)
                            .onEnded { _ in
                                BeansHaptics.select()
                                showHomePlatformMenu = true
                            }
                    )
                    if !homeHideUsername {
                        Text(auth.user?.nickname ?? "发现好音乐")
                            .font(BeansFont.appFont(13))
                            .foregroundStyle(Color.beansComment)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                HStack(spacing: 10) {
                    if !homeHeaderHideSort {
                        GlassIconButton(systemName: "arrow.up.arrow.down") {
                            BeansHaptics.tap()
                            showSectionSort = true
                        }
                    }
                    if !homeHeaderHideRefresh {
                        GlassIconButton(systemName: "arrow.clockwise") {
                            BeansHaptics.tap()
                            Task { await load(force: true) }
                        }
                    }
                }
            }
        }
        .padding(.top, isNativeClean ? 4 : 8)
        .frame(minHeight: homeGreetingHeight > 0 ? homeGreetingHeight : nil, alignment: .top)
    }

    /// 平台选择（网易云 / QQ音乐 / 酷狗音乐，样式与搜索页一致）
    private var providerPicker: some View {
        HStack(spacing: 4) {
            ForEach(homeProviders) { p in
                Button {
                    BeansHaptics.tap()
                    if source != p { homeSourceRaw = p.rawValue }
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
                        Text(p.rawValue)
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
        .background {
            if isNativeClean {
                BeansSurface(shape: Capsule())
            } else {
                BeansGlass(shape: Capsule())
            }
        }
        .clipShape(Capsule())
        .beansCardShadow(radius: isNativeClean ? 2 : 6, y: isNativeClean ? 1 : 2)
    }

    private var greeting: String {
        let custom = homeGreetingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        let hour = Calendar.current.component(.hour, from: Date())
        if isNativeClean { return "推荐" }
        switch hour {
        case 5..<12: return "早上好"
        case 12..<18: return "下午好"
        default: return "晚上好"
        }
    }


    /// 每日推荐封面右下角播放状态：当前播放中显示动态指示器，暂停显示暂停，其余显示播放
    @ViewBuilder
    private func dailyPlayStateBadge(for song: Song) -> some View {
        let isCurrent = player.currentSong?.identityKey == song.identityKey
        ZStack {
            if isCurrent && player.isPlaying {
                NowPlayingIndicator()
                    .frame(width: 24, height: 24)
                    .background(.black.opacity(0.45), in: Circle())
            } else {
                Image(systemName: isCurrent ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(.black.opacity(0.45), in: Circle())
            }
        }
        .padding(7)
    }

    /// 网易云排行榜：全部榜单保留，热歌榜置顶
    private var neteaseTopLists: [TopList] {
        var list = topLists
        if let hot = list.first(where: { $0.name.contains("热歌榜") }),
           let idx = list.firstIndex(where: { $0.id == hot.id }), idx != 0 {
            list.remove(at: idx)
            list.insert(hot, at: 0)
        }
        return list
    }

    /// 每平台排行榜最多 10 个（收起只显示前 3，展开显示前 10）
    private var visibleRankCount: Int {
        switch source {
        case .netease: return neteaseTopLists.count
        case .qq: return qqTopLists.count
        case .kugou: return kugouTopLists.count
        }
    }

    private var displayedRankCount: Int {
        ranksExpanded ? min(visibleRankCount, 10) : min(visibleRankCount, 3)
    }

    /// 当前平台是否有排行榜数据（网易云用 topLists，QQ 用 qqTopLists）
    private var hasRankData: Bool {
        switch source {
        case .netease: return !topLists.isEmpty
        case .qq: return !qqTopLists.isEmpty
        case .kugou: return !kugouTopLists.isEmpty
        }
    }

    // MARK: - 排行榜（竖排行列表）

    @ViewBuilder
    private var topListsSection: some View {
        if isNativeClean {
            nativeCleanTopListsSection
        } else {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "排行榜")
            VStack(spacing: 0) {
                if ranksExpanded {
                    rankToggleButton(label: "收起", icon: "chevron.up")
                    Divider().overlay(Color.beansComment.opacity(0.12))
                }
                rankRowsContent
                if !ranksExpanded, visibleRankCount > 3 {
                    rankToggleButton(label: "展开全部（\(min(visibleRankCount, 10))）", icon: "chevron.down")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.06))
                    .background {
                        BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .beansCardShadow(radius: 9, y: 3)
            .id("rankTopSection")
        }
        }
    }

    private var nativeCleanTopListsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "排行榜")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    if source == .netease {
                        ForEach(Array(neteaseTopLists.prefix(min(visibleRankCount, 10)).enumerated()), id: \.element.id) { index, topList in
                            nativeRankCard(index: index, name: topList.name, subtitle: topList.updateFrequency, coverURL: topList.coverURL) {
                                selectedTopList = topList
                            }
                        }
                    } else if source == .qq {
                        ForEach(Array(qqTopLists.prefix(min(visibleRankCount, 10)).enumerated()), id: \.element.id) { index, info in
                            nativeRankCard(index: index, name: info.name, subtitle: "QQ 峰尖榜", coverURL: info.coverURL) {
                                selectedQQTopList = info
                            }
                        }
                    } else {
                        ForEach(Array(kugouTopLists.prefix(min(visibleRankCount, 10)).enumerated()), id: \.element.id) { index, info in
                            nativeRankCard(index: index, name: info.name, subtitle: info.updateFrequency, coverURL: info.coverURL) {
                                selectedKugouTopList = info
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            // 保留首页左侧起始边距，右侧滚动时才延伸到屏幕边缘。
            .padding(.trailing, isNativeClean ? -24 : 0)
        }
        .id("rankTopSection")
    }

    private func nativeRankCard(index: Int, name: String, subtitle: String, coverURL: URL?, action: @escaping () -> Void) -> some View {
        Button {
            BeansHaptics.tap()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    CoverImage(url: coverURL, size: 148, cornerRadius: 10)
                    LinearGradient(
                        colors: [.black.opacity(0.08), .black.opacity(0.68)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    Image(systemName: "waveform")
                        .font(.system(size: 58, weight: .bold))
                        .foregroundStyle(.white.opacity(0.18))
                        .offset(x: 24, y: -16)
                }
                .frame(width: 148, height: 148)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(name)
                    .font(BeansFont.appFont(15, .bold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background { BeansGlass(shape: Capsule()) }
                Text(subtitle)
                    .font(BeansFont.appFont(12, .medium))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            .frame(width: 148, alignment: .leading)
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.96))
    }

    /// 排行榜行列表（按平台渲染）
    @ViewBuilder
    private var rankRowsContent: some View {
        if source == .netease {
            ForEach(Array(neteaseTopLists.prefix(displayedRankCount).enumerated()), id: \.element.id) { index, topList in
                rankRow(index: index, name: topList.name, subtitle: topList.updateFrequency, coverURL: topList.coverURL) {
                    BeansHaptics.tap()
                    selectedTopList = topList
                }
                Divider().overlay(Color.beansComment.opacity(0.12))
            }
        } else if source == .qq {
            ForEach(Array(qqTopLists.prefix(displayedRankCount).enumerated()), id: \.element.id) { index, info in
                rankRow(index: index, name: info.name, subtitle: "QQ 峰尖榜", coverURL: info.coverURL) {
                    BeansHaptics.tap()
                    selectedQQTopList = info
                }
                Divider().overlay(Color.beansComment.opacity(0.12))
            }
        } else if source == .kugou {
            ForEach(Array(kugouTopLists.prefix(displayedRankCount).enumerated()), id: \.element.id) { index, info in
                rankRow(index: index, name: info.name, subtitle: info.updateFrequency, coverURL: info.coverURL) {
                    BeansHaptics.tap()
                    selectedKugouTopList = info
                }
                Divider().overlay(Color.beansComment.opacity(0.12))
            }
        } else {
            EmptyView()
        }
    }

    /// 展开 / 收起切换按钮
    private func rankToggleButton(label: String, icon: String) -> some View {
        Button {
            BeansHaptics.select()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { ranksExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .font(BeansFont.appFont(13, .medium))
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.beansAmber)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rankRow(index: Int, name: String, subtitle: String, coverURL: URL?, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .font(BeansFont.appFont(16, .bold, .rounded))
                    .foregroundStyle(index < 3 ? Color.beansAmber : Color.beansComment)
                    .frame(width: 24)
                CoverImage(url: coverURL, size: 52, cornerRadius: 12)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(BeansFont.appFont(15, .semibold))
                        .foregroundStyle(Color.beansLabel)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.beansComment.opacity(0.6))
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// QQ 峰尖榜占位渐变（保留备用）
    private func qqRankGradient(_ name: String) -> LinearGradient {
        let palettes: [[Color]] = [
            [Color(red: 0.35, green: 0.55, blue: 0.95), Color(red: 0.20, green: 0.30, blue: 0.65)],
            [Color(red: 0.95, green: 0.42, blue: 0.36), Color(red: 0.70, green: 0.18, blue: 0.20)],
            [Color(red: 0.20, green: 0.78, blue: 0.62), Color(red: 0.08, green: 0.52, blue: 0.44)],
            [Color(red: 0.92, green: 0.62, blue: 0.25), Color(red: 0.72, green: 0.38, blue: 0.12)],
            [Color(red: 0.62, green: 0.45, blue: 0.90), Color(red: 0.40, green: 0.25, blue: 0.68)],
            [Color(red: 0.30, green: 0.70, blue: 0.85), Color(red: 0.16, green: 0.45, blue: 0.65)]
        ]
        let seed = abs(name.hashValue) % palettes.count
        return LinearGradient(colors: palettes[seed], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - 每日推荐（横滑歌曲卡 + 播放）

    private var dailySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 横滑歌曲卡：每日推荐前 8 首
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(dailySongs.prefix(8).enumerated()), id: \.element.identityKey) { index, song in
                        Button {
                            BeansHaptics.tap()
                            player.play(songs: dailySongs, startAt: index)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                CoverImage(url: song.coverURL, size: isNativeClean ? 156 : 108, cornerRadius: isNativeClean ? 14 : 16)
                                    .overlay(alignment: .topLeading) {
                                    if showSongVIPBadge, song.isVIP {
                                            Text("VIP")
                                                .font(BeansFont.appFont(9, .bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1.5)
                                                .background(Capsule().fill(Color(red: 0.93, green: 0.25, blue: 0.22)))
                                                .padding(6)
                                        }
                                    }
                                    .overlay(alignment: .bottomTrailing) {
                                        dailyPlayStateBadge(for: song)
                                    }
                                Text(song.name)
                                    .font(BeansFont.appFont(12, .medium))
                                    .foregroundStyle(Color.beansLabel)
                                    .lineLimit(1)
                                    .font(BeansFont.appFont(isNativeClean ? 15 : 12, isNativeClean ? .bold : .medium))
                                    .frame(width: isNativeClean ? 156 : 108, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background { BeansGlass(shape: Capsule(), forceLiquid: true) }
                                Text(song.artists.isEmpty ? song.album : song.artists)
                                    .font(BeansFont.appFont(10))
                                    .foregroundStyle(Color.beansComment)
                                    .lineLimit(1)
                                    .frame(width: isNativeClean ? 156 : 108, alignment: .leading)
                            }
                        }
                        .buttonStyle(GlassPressButtonStyle(scale: 0.94))
                    }
                    Button {
                        BeansHaptics.tap()
                        showDailyList = true
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 18, weight: .semibold))
                            Text("查看更多")
                                .font(BeansFont.appFont(13, .semibold))
                        }
                        .foregroundStyle(Color.beansLabel)
                        .frame(width: isNativeClean ? 72 : 68, height: isNativeClean ? 132 : 96)
                        .background { BeansGlass(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)) }
                    }
                    .buttonStyle(GlassPressButtonStyle(scale: 0.94))
                }
                .padding(.vertical, 2)
            }
            // 保留首页左侧起始边距，右侧滚动时才延伸到屏幕边缘。
            .padding(.trailing, isNativeClean ? -24 : 0)
        }
        .confirmationDialog("主页平台", isPresented: $showHomePlatformMenu, titleVisibility: .visible) {
            homePlatformSelectionMenu
        }
    }

    @ViewBuilder
    private var homePlatformSelectionMenu: some View {
        let current = SearchProvider(rawValue: homeSourceRaw) ?? homeProviders.first ?? .netease
        ForEach(homeProviders) { provider in
            Button {
                BeansHaptics.select()
                homeSourceRaw = provider.rawValue
            } label: {
                Label(provider.rawValue, systemImage: provider == current ? "checkmark" : provider.icon)
            }
        }
    }

    // MARK: - 歌单广场（官方分类 + 双列网格）

    /// 官方歌单分类：全部 + 热门分类（接口失败时用内置兜底）
    private var catChips: [String] {
        if playlistCats.isEmpty {
            return ["全部", "华语", "流行", "经典", "摇滚", "民谣", "电子", "影视原声", "ACG", "怀旧", "欧美", "日韩", "粤语", "古风", "轻音乐", "治愈", "学习", "运动", "夜晚"]
        }
        return ["全部"] + Array(playlistCats.prefix(18))
    }

    private var personalizedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: source == .qq ? "QQ音乐热门歌单" : "歌单广场")
            if source == .netease {
                // 官方分类标签：点击切换分类（「全部」为官方精品歌单）
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(catChips, id: \.self) { cat in
                            Button {
                                BeansHaptics.tap()
                                guard cat != neteaseCat else { return }
                                neteaseCat = cat
                                Task { await loadPlaylists(cat: cat) }
                            } label: {
                                Text(cat)
                                    .font(BeansFont.appFont(12, .medium))
                                    .foregroundStyle(neteaseCat == cat ? Color.white : Color.beansComment)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background {
                                        if neteaseCat == cat {
                                            Capsule().fill(Color.beansAmber.opacity(0.72))
                                        }
                                        BeansGlass(shape: Capsule())
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            if visiblePersonalizedPlaylists.isEmpty {
                EmptyStateView(icon: "music.note.list", text: source == .qq ? "QQ音乐热门歌单暂未加载成功\n下拉刷新可重新获取" : "歌单广场暂时没有内容")
            } else if isNativeClean {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(visiblePersonalizedPlaylists, id: \.id) { (playlist: Playlist) in
                            Button {
                                BeansHaptics.tap()
                                if source == .qq {
                                    selectedQQPlaylist = playlist
                                } else {
                                    selectedPlaylist = playlist
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    CoverImage(url: playlist.coverURL, size: 166, cornerRadius: 16)
                                    Text(playlist.name)
                                        .font(BeansFont.appFont(15, .bold))
                                        .foregroundStyle(Color.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .frame(width: 166, alignment: .leading)
                                    if playlist.trackCount > 0 {
                                        Text("\(playlist.trackCount) 首")
                                            .font(BeansFont.appFont(12, .medium))
                                            .foregroundStyle(Color.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(width: 166, alignment: .leading)
                            }
                            .buttonStyle(GlassPressButtonStyle(scale: 0.96))
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(visiblePersonalizedPlaylists) { playlist in
                        Button {
                            if source == .qq {
                                selectedQQPlaylist = playlist
                            } else {
                                selectedPlaylist = playlist
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                CoverImage(url: playlist.coverURL, size: 144, cornerRadius: 18)
                                    .frame(maxWidth: .infinity)
                                Text(playlist.name)
                                    .font(BeansFont.appFont(12, .medium))
                                    .foregroundStyle(Color.beansLabel)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            }
                        }
                        .buttonStyle(GlassPressButtonStyle(scale: 0.96))
                    }
                }
            }
            if personalized.count > collapsedPlaylistCount {
                Button {
                    BeansHaptics.select()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        playlistsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(playlistsExpanded ? "收起歌单广场" : "展开全部（\(personalized.count)）")
                            .font(BeansFont.appFont(13, .semibold))
                        Image(systemName: playlistsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.beansAmber)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background { BeansGlass(shape: Capsule()) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(GlassPressButtonStyle(scale: 0.97))
            }
        }
    }

    private var collapsedPlaylistCount: Int { 6 }

    private var visiblePersonalizedPlaylists: [Playlist] {
        playlistsExpanded ? personalized : Array(personalized.prefix(collapsedPlaylistCount))
    }

    // MARK: - 动作

    private func load(force: Bool = false) async {
        guard !homeRenderingPaused else { return }
        let cache = DiscoverCache.shared
        let requestedSource = source
        // 网易云非「全部」分类的歌单不缓存（切换分类即重新拉取）
        let requestedCat = neteaseCat
        let loadKey = "\(requestedSource.rawValue)|\(requestedCat)"
        if activeLoadKey == loadKey {
            return
        }
        if !force,
           lastLoadedKey == loadKey,
           Date().timeIntervalSince(lastLoadedAt) < 20,
           hasAnyData {
            loading = false
            errorMessage = nil
            return
        }
        activeLoadKey = loadKey
        defer {
            if activeLoadKey == loadKey {
                activeLoadKey = nil
            }
        }
        let cacheable = requestedCat == "全部" || requestedSource != .netease
        if let cached = cache.cached(for: requestedSource), !force, cacheable {
            guard !Task.isCancelled, requestedSource == source else { return }
            apply(cached)
            loading = false
            errorMessage = nil
            lastLoadedKey = loadKey
            lastLoadedAt = Date()
            if cache.isFresh(cached) { return }
            // 缓存过期：先用缓存展示，后台静默刷新
        } else {
            loading = true
            errorMessage = nil
        }

        do {
            let snapshot = try await fetchSnapshot(for: requestedSource, neteaseCat: requestedCat)
            guard !Task.isCancelled, requestedSource == source else { return }
            apply(snapshot)
            if cacheable, !snapshot.isEmpty {
                cache.save(snapshot, for: requestedSource)
            }
            loading = false
            errorMessage = nil
            lastLoadedKey = loadKey
            lastLoadedAt = Date()
        } catch {
            guard !Task.isCancelled, requestedSource == source else { return }
            loading = false
            if !hasAnyData {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var greetingLines: [String] {
        let custom = homeGreetingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if custom.isEmpty { return [greeting] }
        return custom.components(separatedBy: .newlines)
    }

    private func greetingLineSize(_ index: Int) -> CGFloat {
        guard index < 3 else { return CGFloat(homeGreetingSize) }
        let value: Double
        switch index {
        case 0: value = homeGreetingLine1Size
        case 1: value = homeGreetingLine2Size
        default: value = homeGreetingLine3Size
        }
        return CGFloat(value > 0 ? value : homeGreetingSize)
    }

    private func greetingLineColor(_ index: Int) -> Color {
        guard index < 3 else { return homeGreetingColor }
        let raw: String
        switch index {
        case 0: raw = homeGreetingLine1ColorHex
        case 1: raw = homeGreetingLine2ColorHex
        default: raw = homeGreetingLine3ColorHex
        }
        return Color(hex: raw) ?? homeGreetingColor
    }

    private func greetingLineStyle(_ index: Int) -> AnyShapeStyle {
        let color = greetingLineColor(index)
        if homeGreetingGradient {
            let startHex: String
            let endHex: String
            switch index {
            case 0:
                startHex = homeGreetingLine1GradientStartHex
                endHex = homeGreetingLine1GradientEndHex
            case 1:
                startHex = homeGreetingLine2GradientStartHex
                endHex = homeGreetingLine2GradientEndHex
            case 2:
                startHex = homeGreetingLine3GradientStartHex
                endHex = homeGreetingLine3GradientEndHex
            default:
                startHex = ""
                endHex = ""
            }
            let start = Color(hex: startHex) ?? Color(hex: homeGreetingGradientStartHex) ?? color
            let end = Color(hex: endHex) ?? Color(hex: homeGreetingGradientEndHex) ?? color.opacity(0.42)
            return AnyShapeStyle(LinearGradient(
                colors: [start, end],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
        return AnyShapeStyle(color)
    }

    private func greetingLineOffsetY(_ index: Int) -> CGFloat {
        guard index < 3 else { return 0 }
        switch index {
        case 0: return CGFloat(homeGreetingLine1OffsetY)
        case 1: return CGFloat(homeGreetingLine2OffsetY)
        default: return CGFloat(homeGreetingLine3OffsetY)
        }
    }

    private func reloadAfterLoginUpdate(_ provider: SearchProvider) {
        if source == provider {
            Task { await load(force: true) }
        } else {
            homeSourceRaw = provider.rawValue
        }
    }

    private var homeGreetingColor: Color {
        if let color = Color(hex: homeGreetingColorHex) { return color }
        return Color.beansLabel
    }

    /// 网易云歌单广场：切换官方分类时单独拉取（不写缓存）
    private func loadPlaylists(cat: String) async {
        guard source == .netease else { return }
        do {
            let pp = cat == "全部"
                ? try await NetEaseAPI.shared.highQualityPlaylists(limit: 18)
                : try await NetEaseAPI.shared.playlistSquare(cat: cat, order: "hot", limit: 18)
            personalized = pp
            errorMessage = nil
        } catch {
            // 分类拉取失败：保留现有歌单，不打断用户
        }
    }

    private func fetchSnapshot(for source: SearchProvider, neteaseCat: String) async throws -> DiscoverCache.Snapshot {
        var snapshot = DiscoverCache.Snapshot()
        snapshot.savedAt = Date()
        switch source {
        case .qq:
            async let a: [Song] = (try? await QQMusicAPI.shared.recommendSongs(limit: 30)) ?? []
            async let b: [QQTopInfo] = (try? await QQMusicAPI.shared.topLists()) ?? []
            async let c: [Playlist] = (try? await QQMusicAPI.shared.hotPlaylists(limit: 18)) ?? []
            let (dr, tl, pp) = await (a, b, c)
            if pp.isEmpty {
                BeansLogger.shared.log("QQ音乐热门歌单为空：保留板块并显示空状态", level: .warn)
            }
            snapshot.dailySongs = dr
            snapshot.qqTopLists = tl
            snapshot.personalized = pp
        case .netease:
            async let a = NetEaseAPI.shared.topLists()
            async let b = NetEaseAPI.shared.dailyRecommend()
            // 「全部」展示官方精品歌单，其他分类展示该分类热门歌单
            async let c = neteaseCat == "全部"
                ? NetEaseAPI.shared.highQualityPlaylists(limit: 18)
                : NetEaseAPI.shared.playlistSquare(cat: neteaseCat, order: "hot", limit: 18)
            async let d = NetEaseAPI.shared.playlistCatlist()
            let (tl, dr, pp, cats) = try await (a, b, c, d)
            snapshot.topLists = tl
            snapshot.dailySongs = dr
            snapshot.personalized = pp
            if !cats.isEmpty { playlistCats = cats }
        case .kugou:
            async let songs = KugouMusicAPI.shared.searchSongs(keyword: "热门歌曲", limit: 30)
            async let ranks = KugouMusicAPI.shared.topLists(limit: 10)
            async let playlists = KugouMusicAPI.shared.recommendPlaylists(limit: 12)
            let (daily, top, pp) = try await (songs, ranks, playlists)
            snapshot.dailySongs = daily
            snapshot.kugouTopLists = top
            snapshot.personalized = pp
        }
        return snapshot
    }

    private func apply(_ snapshot: DiscoverCache.Snapshot) {
        dailySongs = snapshot.dailySongs
        topLists = snapshot.topLists
        personalized = snapshot.personalized
        qqTopLists = snapshot.qqTopLists
        kugouTopLists = snapshot.kugouTopLists
    }

    private var hasAnyData: Bool {
        !dailySongs.isEmpty || !topLists.isEmpty || !personalized.isEmpty
            || !qqTopLists.isEmpty || !kugouTopLists.isEmpty
    }
}

// MARK: - QQ 峰尖榜详情

struct QQTopListDetailView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var theme: ThemeStore

    let topID: Int
    let name: String
    @State private var tracks: [Song] = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var searchText = ""

    var body: some View {
        let _ = theme.accent
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                Group {
                if loading {
                    LoadingStateView()
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) {
                        Task { await load() }
                    }
                } else {
                    List {
                        Section {
                            HStack(spacing: 12) {
                                GlassButton(title: "播放全部", systemName: "play.fill", prominent: true) {
                                    guard !filteredTracks.isEmpty else { return }
                                    BeansHaptics.tap()
                                    player.play(songs: filteredTracks, startAt: 0)
                                }
                                GlassButton(title: "随机播放", systemName: "shuffle") {
                                    guard !filteredTracks.isEmpty else { return }
                                    BeansHaptics.tap()
                                    player.play(songs: filteredTracks, startAt: Int.random(in: 0..<filteredTracks.count))
                                }
                            }
                            .listRowBackground(Color.clear)
                            .padding(.vertical, 8)
                        }
                        Section {
                            ForEach(Array(filteredTracks.enumerated()), id: \.element.identityKey) { index, song in
                                SongCell(song: song, glassRow: true) {
                                    player.play(songs: filteredTracks, startAt: index)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                    }
                    .beansScrollContentBackgroundHidden()
                    .listStyle(.plain)
                }
            }
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索榜单歌曲")
        }
        .task { await load() }
    }

    private var filteredTracks: [Song] {
        let kw = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !kw.isEmpty else { return tracks }
        return tracks.filter { song in
            song.name.lowercased().contains(kw)
                || song.artists.lowercased().contains(kw)
                || song.album.lowercased().contains(kw)
        }
    }

    private func load() async {
        loading = true
        errorMessage = nil
        do {
            tracks = try await QQMusicAPI.shared.topListSongs(topid: topID)
            loading = false
        } catch {
            errorMessage = error.localizedDescription
            loading = false
        }
    }
}

// MARK: - QQ 歌单内歌曲

struct QQPlaylistSongsSheet: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var theme: ThemeStore

    let playlist: Playlist
    @State private var tracks: [Song] = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var searchText = ""

    var body: some View {
        let _ = theme.accent
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                Group {
                if loading {
                    LoadingStateView()
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) {
                        Task { await load() }
                    }
                } else {
                    List {
                        Section {
                            HStack(spacing: 12) {
                                GlassButton(title: "播放全部", systemName: "play.fill", prominent: true) {
                                    guard !filteredTracks.isEmpty else { return }
                                    BeansHaptics.tap()
                                    player.play(songs: filteredTracks, startAt: 0)
                                }
                                GlassButton(title: "随机播放", systemName: "shuffle") {
                                    guard !filteredTracks.isEmpty else { return }
                                    BeansHaptics.tap()
                                    player.play(songs: filteredTracks, startAt: Int.random(in: 0..<filteredTracks.count))
                                }
                            }
                            .listRowBackground(Color.clear)
                            .padding(.vertical, 8)
                        }
                        Section {
                            ForEach(Array(filteredTracks.enumerated()), id: \.element.identityKey) { index, song in
                                SongCell(song: song, glassRow: true) {
                                    player.play(songs: filteredTracks, startAt: index)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                    }
                    .beansScrollContentBackgroundHidden()
                    .listStyle(.plain)
                }
            }
            }
            .navigationTitle(playlist.name)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索歌单内歌曲")
        }
        .task { await load() }
    }

    private var filteredTracks: [Song] {
        let kw = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !kw.isEmpty else { return tracks }
        return tracks.filter { song in
            song.name.lowercased().contains(kw)
                || song.artists.lowercased().contains(kw)
                || song.album.lowercased().contains(kw)
        }
    }

    private func load() async {
        loading = true
        errorMessage = nil
        do {
            tracks = try await QQMusicAPI.shared.playlistSongs(listID: playlist.id)
            loading = false
        } catch {
            errorMessage = error.localizedDescription
            loading = false
        }
    }
}

// MARK: - 每日推荐全部歌曲

struct DailySongsSheet: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var theme: ThemeStore

    let songs: [Song]
    @State private var searchText = ""

    var body: some View {
        let _ = theme.accent
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                Group {
                if songs.isEmpty {
                    EmptyStateView(icon: "sparkles", text: "今日推荐加载中，下拉刷新试试")
                } else {
                    List {
                    Section {
                        HStack(spacing: 12) {
                            GlassButton(title: "播放全部", systemName: "play.fill", prominent: true) {
                                guard !filteredSongs.isEmpty else { return }
                                BeansHaptics.tap()
                                player.play(songs: filteredSongs, startAt: 0)
                            }
                            GlassButton(title: "随机播放", systemName: "shuffle") {
                                guard !filteredSongs.isEmpty else { return }
                                BeansHaptics.tap()
                                player.play(songs: filteredSongs, startAt: Int.random(in: 0..<filteredSongs.count))
                            }
                        }
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 8)
                    }
                    Section {
                        ForEach(Array(filteredSongs.enumerated()), id: \.element.identityKey) { index, song in
                            SongCell(song: song, glassRow: true) {
                                BeansHaptics.tap()
                                player.play(songs: filteredSongs, startAt: index)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                }
                .beansScrollContentBackgroundHidden()
                .listStyle(.plain)
                }
            }
            }
            .navigationTitle("今日推荐")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索每日推荐")
        }
    }

    private var filteredSongs: [Song] {
        let kw = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !kw.isEmpty else { return songs }
        return songs.filter { song in
            song.name.lowercased().contains(kw)
                || song.artists.lowercased().contains(kw)
                || song.album.lowercased().contains(kw)
        }
    }
}
// MARK: - 排行榜详情

struct TopListDetailView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore

    let topList: TopList
    @State private var tracks: [Song] = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var searchText = ""

    var body: some View {
        let _ = theme.accent
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                Group {
                if loading {
                    LoadingStateView()
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) {
                        Task { await load() }
                    }
                } else {
                    List {
                        header
                        Section {
                            HStack(spacing: 12) {
                                GlassButton(title: "播放全部", systemName: "play.fill", prominent: true) {
                                    guard !filteredTracks.isEmpty else { return }
                                    BeansHaptics.tap()
                                    player.play(songs: filteredTracks, startAt: 0)
                                }
                                GlassButton(title: "随机播放", systemName: "shuffle") {
                                    guard !filteredTracks.isEmpty else { return }
                                    BeansHaptics.tap()
                                    player.play(songs: filteredTracks, startAt: Int.random(in: 0..<filteredTracks.count))
                                }
                            }
                            .listRowBackground(Color.clear)
                            .padding(.vertical, 8)
                        }
                        Section {
                            ForEach(Array(filteredTracks.enumerated()), id: \.element.identityKey) { index, song in
                                SongCell(song: song, glassRow: true) {
                                    player.play(songs: filteredTracks, startAt: index)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                    }
                    .beansScrollContentBackgroundHidden()
                    .listStyle(.plain)
                }
            }
            }
            .navigationTitle(topList.name)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索榜单歌曲")
        }
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            CoverImage(url: topList.coverURL, size: 88, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 6) {
                Text(topList.name)
                    .font(BeansFont.appFont(18, .bold))
                    .foregroundStyle(Color.beansLabel)
                Text(topList.updateFrequency)
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansComment)
                Text("\(tracks.count) 首")
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansComment)
            }
            Spacer()
        }
        .padding(14)
        .background {
            BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .beansCardShadow(radius: 8, y: 3)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var filteredTracks: [Song] {
        let kw = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !kw.isEmpty else { return tracks }
        return tracks.filter { song in
            song.name.lowercased().contains(kw)
                || song.artists.lowercased().contains(kw)
                || song.album.lowercased().contains(kw)
        }
    }

    private func load() async {
        loading = true
        errorMessage = nil
        do {
            tracks = try await NetEaseAPI.shared.playlistTracks(id: topList.id)
            loading = false
        } catch {
            errorMessage = error.localizedDescription
            loading = false
        }
    }
}

// MARK: - 酷狗排行榜详情

struct KugouTopListDetailView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    let topList: KugouTopInfo
    @State private var tracks: [Song] = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var searchText = ""

    var body: some View {
        let _ = theme.accent
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                Group {
                if loading {
                    LoadingStateView()
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) {
                        Task { await load() }
                    }
                } else if tracks.isEmpty {
                    EmptyStateView(icon: "music.note.list", text: "该排行榜暂无歌曲")
                } else {
                    List {
                        header
                        Section {
                            HStack(spacing: 12) {
                                GlassButton(title: "播放全部", systemName: "play.fill", prominent: true) {
                                    guard !filteredTracks.isEmpty else { return }
                                    BeansHaptics.tap()
                                    player.play(songs: filteredTracks, startAt: 0)
                                }
                                GlassButton(title: "随机播放", systemName: "shuffle") {
                                    guard !filteredTracks.isEmpty else { return }
                                    BeansHaptics.tap()
                                    player.play(songs: filteredTracks, startAt: Int.random(in: 0..<filteredTracks.count))
                                }
                            }
                            .listRowBackground(Color.clear)
                            .padding(.vertical, 8)
                        }
                        Section {
                            ForEach(Array(filteredTracks.enumerated()), id: \.element.identityKey) { index, song in
                                SongCell(song: song, glassRow: true) {
                                    player.play(songs: filteredTracks, startAt: index)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                    }
                    .beansScrollContentBackgroundHidden()
                    .listStyle(.plain)
                }
            }
            }
            .navigationTitle(topList.name)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索榜单歌曲")
        }
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            CoverImage(url: topList.coverURL, size: 88, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 6) {
                Text(topList.name)
                    .font(BeansFont.appFont(18, .bold))
                    .foregroundStyle(Color.beansLabel)
                    .lineLimit(2)
                if !topList.updateFrequency.isEmpty {
                    Text(topList.updateFrequency)
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                }
                Text("\(tracks.count) 首")
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansComment)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background {
            BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .beansCardShadow(radius: 8, y: 3)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var filteredTracks: [Song] {
        let kw = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !kw.isEmpty else { return tracks }
        return tracks.filter { song in
            song.name.lowercased().contains(kw)
                || song.artists.lowercased().contains(kw)
                || song.album.lowercased().contains(kw)
        }
    }

    private func load() async {
        loading = true
        errorMessage = nil
        do {
            tracks = try await KugouMusicAPI.shared.rankSongs(rankID: topList.id)
            loading = false
        } catch {
            errorMessage = error.localizedDescription
            loading = false
        }
    }
}

private struct HomeUnifiedSearchSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var platformPrefs = PlatformPreferenceStore.shared

    @State private var keyword = ""
    @State private var results: [Song] = []
    @State private var searching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var debounceTask: Task<Void, Never>?
    @State private var searchController = SearchFieldController()

    private var providers: [SearchProvider] {
        platformPrefs.enabledSearchProviders
    }

    var body: some View {
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                VStack(spacing: 12) {
                    searchField
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    content
                }
            }
            .navigationTitle("全平台搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .onChange(of: keyword) { newValue in
            debounceTask?.cancel()
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                results = []
                errorMessage = nil
                return
            }
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 420_000_000)
                guard !Task.isCancelled else { return }
                await startSearch(trimmed)
            }
        }
        .onDisappear {
            debounceTask?.cancel()
            searchTask?.cancel()
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.beansComment)
            SearchTextField(
                text: $keyword,
                controller: searchController,
                placeholder: "搜索三平台歌曲",
                textColor: UIColor.beansLabel,
                onSubmit: { text in
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    debounceTask?.cancel()
                    Task { await startSearch(trimmed) }
                }
            )
            .frame(height: 34)
            .frame(maxWidth: .infinity)

            if searching {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.beansAmber)
            }

            if !keyword.isEmpty {
                Button {
                    keyword = ""
                    results = []
                    errorMessage = nil
                    debounceTask?.cancel()
                    searchTask?.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.beansComment.opacity(0.85))
                }
                .buttonStyle(.plain)
            }

            Button {
                let text = searchController.commit()
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                debounceTask?.cancel()
                Task { await startSearch(trimmed) }
            } label: {
                Text("搜索")
                    .font(BeansFont.appFont(13, .semibold))
                    .foregroundStyle(Color.beansAmber)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background { BeansGlass(shape: Capsule()) }
            }
            .buttonStyle(GlassPressButtonStyle(scale: 0.9))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background {
            BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .beansCardShadow(radius: 8, y: 3)
    }

    @ViewBuilder
    private var content: some View {
        if keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyStateView(icon: "magnifyingglass", text: "输入歌名后会同时搜索网易云、QQ音乐和酷狗音乐")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, results.isEmpty {
            ErrorStateView(message: errorMessage) {
                Task { await startSearch(keyword) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searching && results.isEmpty {
            LoadingStateView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            EmptyStateView(icon: "music.note", text: "暂未找到相关歌曲")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    HStack {
                        Text("找到 \(results.count) 首 · 全平台")
                            .font(BeansFont.appFont(12))
                            .foregroundStyle(Color.beansComment)
                        Spacer()
                        Button {
                            BeansHaptics.tap()
                            player.play(songs: results, startAt: 0)
                        } label: {
                            Label("播放全部", systemImage: "play.fill")
                                .font(BeansFont.appFont(12, .semibold))
                                .foregroundStyle(Color.beansAmber)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background { BeansGlass(shape: Capsule()) }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 8)

                    ForEach(Array(results.enumerated()), id: \.element.identityKey) { index, song in
                        SongCell(song: song) {
                            BeansHaptics.tap()
                            player.play(songs: results, startAt: index)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            BeansGlass(shape: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
            .beansScrollIndicatorsHidden()
            .beansScrollDismissesKeyboard()
        }
    }

    private func startSearch(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchTask?.cancel()
        searchTask = Task {
            searching = true
            errorMessage = nil
            BeansLogger.shared.log("主页聚合搜索：\(trimmed)", level: .info)
            defer { if !Task.isCancelled { searching = false } }

            let enabledProviders = providers
            async let netease: [Song] = searchSongs(on: .netease, keyword: trimmed, enabledProviders: enabledProviders)
            async let qq: [Song] = searchSongs(on: .qq, keyword: trimmed, enabledProviders: enabledProviders)
            async let kugou: [Song] = searchSongs(on: .kugou, keyword: trimmed, enabledProviders: enabledProviders)

            let merged = await (netease + qq + kugou)
            guard !Task.isCancelled else { return }
            results = deduplicated(merged)
            if results.isEmpty {
                errorMessage = "三个平台都没有返回可展示的歌曲"
            } else {
                BeansHaptics.success()
            }
            BeansLogger.shared.log("主页聚合搜索完成：\(trimmed) 结果=\(results.count)", level: .info)
        }
        await searchTask?.value
    }

    private func searchSongs(on provider: SearchProvider, keyword: String, enabledProviders: [SearchProvider]) async -> [Song] {
        guard enabledProviders.contains(provider) else { return [] }
        switch provider {
        case .netease:
            return (try? await NetEaseAPI.shared.search(keyword: keyword, limit: 30)) ?? []
        case .qq:
            return (try? await QQMusicAPI.shared.searchSongs(keyword: keyword, limit: 30)) ?? []
        case .kugou:
            return (try? await KugouMusicAPI.shared.searchSongs(keyword: keyword, limit: 30)) ?? []
        }
    }

    private func deduplicated(_ songs: [Song]) -> [Song] {
        var seen = Set<String>()
        var output: [Song] = []
        for song in songs {
            let key = "\(song.source.rawValue)-\(song.name.lowercased())-\(song.artists.lowercased())"
            if seen.insert(key).inserted {
                output.append(song)
            }
        }
        return output
    }
}
