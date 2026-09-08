import SwiftUI
import UIKit
import AVKit

enum RootTab: String, CaseIterable, Identifiable {
    case discover
    case playlists
    case library
    case profile
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: return "主页"
        case .playlists: return "精选"
        case .library: return "音乐库"
        case .profile: return "我的"
        case .search: return "搜索"
        }
    }

    var icon: String {
        switch self {
        case .discover: return "house.fill"
        case .playlists: return "square.grid.2x2.fill"
        case .library: return "music.note.list"
        case .profile: return "person.crop.circle"
        case .search: return "magnifyingglass"
        }
    }

    /// 底部栏只保留主要内容入口；“我的”从主页右上角头像进入。
    static let bottomTabs: [RootTab] = [.discover, .playlists, .library, .search]
}

struct RootView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var favorites: FavoritesStore
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var platformPrefs = PlatformPreferenceStore.shared
    @AppStorage("beans.themeMode") private var themeModeRaw = BeansThemeMode.system.rawValue

    @State private var selection: RootTab = .discover
    @State private var showPlayer = false
    @Namespace private var nowPlayingTransition
    @AppStorage("beans.disclaimerAccepted") private var disclaimerAccepted = false
    /// 底栏是否显示文字（关闭后只显示图标）
    @AppStorage("beans.tabLabelsVisible") private var tabLabelsVisible = true
    @AppStorage("beans.homeSource") private var homeSourceRaw = SearchProvider.netease.rawValue
    /// 强制高刷新率：用于修复部分页面被系统稳定在 60Hz 的问题。
    @AppStorage("beans.enableHighRefresh") private var enableHighRefresh = true
    @AppStorage("beans.legacyTabCornerRadius") private var legacyTabCornerRadius = 32.0
    @AppStorage("beans.legacyTabWidth") private var legacyTabWidth = 356.0
    @AppStorage("beans.legacyTabOffsetX") private var legacyTabOffsetX = 0.0
    @AppStorage("beans.legacyTabOffsetY") private var legacyTabOffsetY = 0.0
    @AppStorage("beans.uiStyle") private var uiStyleRaw = BeansUIStyle.liquid.rawValue
    @AppStorage("beans.remoteAnnouncement.enabled") private var remoteAnnouncementEnabled = false
    @AppStorage("beans.remoteAnnouncement.text") private var remoteAnnouncementText = ""
    @AppStorage("beans.remoteAnnouncement.imageURL") private var remoteAnnouncementImageURL = ""
    @AppStorage("beans.remoteAnnouncement.mediaURL") private var remoteAnnouncementMediaURL = ""
    @AppStorage("beans.remoteAnnouncement.mediaType") private var remoteAnnouncementMediaType = ""
    @AppStorage("beans.remoteAnnouncement.textColor") private var remoteAnnouncementTextColor = ""
    @AppStorage("beans.remoteAnnouncement.updatedAt") private var remoteAnnouncementUpdatedAt = ""
    @AppStorage("beans.remoteAnnouncement.seenKey") private var remoteAnnouncementSeenKey = ""
    @State private var showWhatsNew = false
    @State private var updateInfo: UpdateChecker.ReleaseInfo?
    @State private var showUpdateAlert = false
    @ObservedObject private var ipaDownloader = IPADownloader.shared
    @State private var showUpdateDownloadOverlay = false
    @State private var updateShareFile: ShareFileItem?
    @State private var updateShareFileURL: URL?
    @State private var updateDownloadError = ""
    @State private var showUpdateDownloadError = false
    @State private var showRemoteAnnouncement = false
    @State private var showHomePlatformMenu = false
    private var themeMode: BeansThemeMode {
        BeansThemeMode(rawValue: themeModeRaw) ?? .system
    }

    private var usesSystemFloatingTabBar: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }

    private var legacyTabResolvedWidth: CGFloat {
        min(CGFloat(legacyTabWidth), max(300, UIScreen.main.bounds.width - 28))
    }

    /// Full-width by default; retain the existing width adjustment when it was
    /// explicitly changed in settings.
    private var legacyTabCustomWidth: CGFloat? {
        abs(legacyTabWidth - 356) > 0.5 ? legacyTabResolvedWidth : nil
    }

    private var isNativeClean: Bool {
        BeansUIStyle(rawValue: uiStyleRaw) == .nativeClean
    }

    private var usesSystemPlayerDismissal: Bool {
        // iOS 26+ 使用 1.6.5.1 的系统播放器下拉交互；旧系统使用兼容性手势。
        if #available(iOS 26.0, *) { return true }
        return false
    }

    var body: some View {
        let _ = theme.accent
        ZStack {

            // iOS 26 使用系统底栏和下滑收缩行为，旧系统使用兼容底栏。
            if #available(iOS 26.0, *) {
                nativeTabs
                    .modifier(
                        MiniPlayerAccessoryModifier(
                            isActive: player.currentSong != nil,
                            showPlayer: $showPlayer,
                            clock: player.clock,
                            colorScheme: colorScheme,
                            transitionNamespace: nowPlayingTransition
                        )
                    )
            } else {
                legacyRootTabs
            }
        }
        .background {
            TabBarAppearanceConfigurator(
                hidesSystemTabBarOnLegacy: !usesSystemFloatingTabBar,
                onHomeLongPress: { showHomePlatformMenu = true }
            )
        }
        .background {
            HighRefreshConfigurator()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
        .preferredColorScheme(themeMode.colorScheme)
        .confirmationDialog("主页平台", isPresented: $showHomePlatformMenu, titleVisibility: .visible) {
            platformSelectionMenu
        }
        .fullScreenCover(isPresented: $showPlayer) {
            if #available(iOS 18.0, *) {
                playerPresentation
                    .navigationTransition(
                        .zoom(
                            sourceID: BeansNowPlayingTransitionID.surface,
                            in: nowPlayingTransition
                        )
                    )
            } else if #available(iOS 16.4, *) {
                playerPresentation
            } else {
                playerPresentation
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: player.currentSong?.id)
        .animation(.easeInOut(duration: 0.22), value: selection)
        .overlay(alignment: .bottom) {
            ToastView(center: ToastCenter.shared)
        }
        .onAppear {
            // 启动已完成：标记本次启动正常（供下次启动检测闪退）
            CrashReporter.shared.markLaunchCompleted()
            if disclaimerAccepted, ChangelogStore.shouldShowWhatsNew {
                showWhatsNew = true
            }
            enableHighRefresh = true
            HighRefreshKeeper.shared.configure(enabled: true)
        }
        .onChange(of: enableHighRefresh) { _ in
            if !enableHighRefresh {
                enableHighRefresh = true
            }
            HighRefreshKeeper.shared.configure(enabled: true)
        }
        .onChange(of: disclaimerAccepted) { accepted in
            if accepted, ChangelogStore.shouldShowWhatsNew {
                showWhatsNew = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .beansSearchBackRequested)) { _ in
            withAnimation(.easeInOut(duration: 0.22)) {
                selection = .discover
            }
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewSheet()
        }
        .task(id: disclaimerAccepted) {
            guard disclaimerAccepted else { return }
            if let info = await UpdateChecker.checkIfNeeded() {
                updateInfo = info
                showUpdateAlert = true
            }
            await RemoteControlStore.shared.refreshIfNeeded(force: true)
            presentRemoteAnnouncementIfNeeded()
        }
        .overlay {
            if showUpdateAlert, let info = updateInfo {
                UpdatePromptOverlay(
                    info: info,
                    onOpen: {
                        showUpdateAlert = false
                        if let assetURL = info.assetURL {
                            startUpdateDownload(info: info, assetURL: assetURL)
                        } else {
                            UIApplication.shared.open(info.htmlURL)
                        }
                    },
                    onRemindLater: {
                        UpdateChecker.suppress(version: info.version)
                        showUpdateAlert = false
                    },
                    onDismiss: {
                        showUpdateAlert = false
                    }
                )
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .overlay {
            if showUpdateDownloadOverlay {
                updateDownloadProgressOverlay
                    .zIndex(21)
            }
        }
        .sheet(item: $updateShareFile, onDismiss: cleanupUpdateShareFile) { item in
            ShareSheet(items: [item.url])
        }
        .alert("更新下载失败", isPresented: $showUpdateDownloadError) {
            Button("好", role: .cancel) {}
            Button("打开 GitHub") {
                UIApplication.shared.open(UpdateChecker.releasePageURL)
            }
        } message: {
            Text(updateDownloadError)
        }
        .overlay {
            if showRemoteAnnouncement {
                RemoteAnnouncementOverlay(
                    text: remoteAnnouncementText,
                    mediaURL: remoteAnnouncementMediaURL.isEmpty ? remoteAnnouncementImageURL : remoteAnnouncementMediaURL,
                    mediaType: remoteAnnouncementMediaType,
                    textColor: remoteAnnouncementColor,
                    onDismiss: {
                        remoteAnnouncementSeenKey = remoteAnnouncementKey
                        showRemoteAnnouncement = false
                    }
                )
                .zIndex(22)
            }
        }
    }

    private var remoteAnnouncementColor: Color {
        Color(hex: remoteAnnouncementTextColor) ?? Color.beansLabel
    }

    private var remoteAnnouncementKey: String {
        "\(remoteAnnouncementUpdatedAt)|\(remoteAnnouncementText)|\(remoteAnnouncementMediaURL)|\(remoteAnnouncementMediaType)"
    }

    private func presentRemoteAnnouncementIfNeeded() {
        guard remoteAnnouncementEnabled,
              !remoteAnnouncementText.isEmpty || !remoteAnnouncementMediaURL.isEmpty || !remoteAnnouncementImageURL.isEmpty else { return }
        guard remoteAnnouncementSeenKey != remoteAnnouncementKey else { return }
        showRemoteAnnouncement = true
    }

    private func startUpdateDownload(info: UpdateChecker.ReleaseInfo, assetURL: URL) {
        showUpdateDownloadOverlay = true
        Task {
            do {
                let url = try await ipaDownloader.download(assetURL: assetURL, version: info.version)
                await MainActor.run {
                    showUpdateDownloadOverlay = false
                    updateShareFileURL = url
                    updateShareFile = ShareFileItem(url: url)
                }
            } catch {
                await MainActor.run {
                    showUpdateDownloadOverlay = false
                    updateDownloadError = error.localizedDescription
                    showUpdateDownloadError = true
                }
            }
        }
    }

    private func cleanupUpdateShareFile() {
        guard let url = updateShareFileURL else { return }
        try? FileManager.default.removeItem(at: url)
        updateShareFile = nil
        updateShareFileURL = nil
    }

    private var updateDownloadProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.beansHighlight)
                    Text("正在下载最新版 IPA")
                        .font(BeansFont.appFont(15, .semibold))
                        .foregroundStyle(Color.beansLabel)
                }
                if ipaDownloader.progress >= 0 {
                    ProgressView(value: ipaDownloader.progress)
                        .progressViewStyle(.linear)
                        .tint(Color.beansAmber)
                    Text("\(Int(ipaDownloader.progress * 100))%")
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                } else {
                    ProgressView()
                        .tint(Color.beansAmber)
                    Text("正在连接下载服务器…")
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                }
            }
            .padding(22)
            .frame(maxWidth: 300)
            .background {
                BeansGlass(shape: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .beansCardShadow(radius: 12, y: 6)
            .padding(32)
        }
    }

    private var legacyFloatingTabBar: some View {
        VStack(spacing: 8) {
            if player.currentSong != nil {
                MiniPlayerView(
                    showPlayer: $showPlayer,
                    presentation: .dock,
                    transitionNamespace: nowPlayingTransition
                )
                    .environmentObject(player.clock)
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Group {
                GlassTabBar(
                    items: RootTab.bottomTabs.map {
                        GlassTabBar.Item(tab: $0, title: LocalizedStringKey($0.title), icon: $0.icon)
                    },
                    selection: $selection,
                    labelsVisible: tabLabelsVisible,
                    accentIsNativeClean: isNativeClean,
                    onHomeLongPress: { showHomePlatformMenu = true }
                ) { tab in
                    guard selection != tab else { return }
                    BeansHaptics.select()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        selection = tab
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(width: legacyTabCustomWidth)
        }
        .padding(.bottom, 6)
        .offset(x: CGFloat(legacyTabOffsetX), y: CGFloat(legacyTabOffsetY))
    }

    @ViewBuilder
    private var platformSelectionMenu: some View {
        let current = SearchProvider(rawValue: homeSourceRaw) ?? platformPrefs.enabledSearchProviders.first ?? .netease
        Text("主页平台")
        ForEach(platformPrefs.enabledSearchProviders) { provider in
            Button {
                BeansHaptics.select()
                homeSourceRaw = provider.rawValue
            } label: {
                Label(LocalizedStringKey(provider.rawValue), systemImage: provider == current ? "checkmark" : provider.icon)
            }
        }
    }

    @ViewBuilder
    private var playerPresentation: some View {
        BeansNowPlayingPresentation(
            isPresented: $showPlayer,
            usesSystemInteractiveDismissal: usesSystemPlayerDismissal
        ) {
            PlayerView(isPresented: $showPlayer)
                .environmentObject(favorites)
                .environmentObject(player)
                .environmentObject(player.clock)
                .environmentObject(auth)
        }
    }

    /// iOS 26 的系统 Tab 容器，提供原生底栏、搜索槽位和收缩行为。
    @available(iOS 26.0, *)
    private var nativeTabs: some View {
        TabView(selection: $selection) {
            Tab(nativeTabTitle(.discover), systemImage: "house", value: .discover) {
                DiscoverView()
            }

            Tab(nativeTabTitle(.playlists), systemImage: "square.grid.2x2", value: .playlists) {
                PlaylistSquareView()
            }

            Tab(nativeTabTitle(.library), systemImage: "music.note.list", value: .library) {
                LibraryView()
            }

            Tab(nativeTabTitle(.search), systemImage: "magnifyingglass", value: .search) {
                SearchView()
            }
        }
        .tint(Color.beansAmber)
        .tabBarMinimizeBehavior(player.currentSong == nil ? .never : .onScrollDown)
    }

    private func nativeTabTitle(_ tab: RootTab) -> LocalizedStringKey {
        tabLabelsVisible ? LocalizedStringKey(tab.title) : LocalizedStringKey("")
    }

    /// 旧系统将页面、底部播放器和胶囊底栏放在同一个 ZStack 中，
    /// 让收缩、上划展开和页面切换共享同一套手势层级。
    private var legacyRootTabs: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                legacyPage(.discover) { DiscoverView() }
                legacyPage(.playlists) { PlaylistSquareView() }
                legacyPage(.search) { SearchView() }
                legacyPage(.library) { LibraryView() }
                legacyPage(.profile) { ProfileView() }
            }

            legacyFloatingTabBar
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.easeInOut(duration: 0.25), value: selection)
        .animation(.easeInOut(duration: 0.25), value: player.currentSong?.identityKey)
    }

    @ViewBuilder
    private func legacyPage<Content: View>(
        _ tab: RootTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .opacity(selection == tab ? 1 : 0)
            .allowsHitTesting(selection == tab)
            .zIndex(selection == tab ? 1 : 0)
    }
}

private enum BeansNowPlayingPresentationMetrics {
    static let indicatorTopSpacing: CGFloat = 6
    static let indicatorWidth: CGFloat = 52
    static let indicatorHeight: CGFloat = 5
    static let indicatorHitWidth: CGFloat = 180
    static let indicatorHitHeight: CGFloat = 82
    static let dismissDistance: CGFloat = 110
    static let dismissPrediction: CGFloat = 190
    /// 旧系统的整屏手势仍然覆盖播放器，但只有从顶部区域开始的纵向拖动才关闭，
    /// 避免歌词滚动被误判为返回。
    static let verticalStartZone: CGFloat = 220
    static let dismissAnimation = Animation.spring(
        response: 0.52,
        dampingFraction: 0.90,
        blendDuration: 0.10
    )
}

struct BeansNowPlayingPresentation<Content: View>: View {
    @Binding var isPresented: Bool
    let usesSystemInteractiveDismissal: Bool
    let content: Content
    @ObservedObject private var appleLayout = AppleMusicLayoutStore.shared
    @State private var dragOffset: CGFloat = 0

    init(
        isPresented: Binding<Bool>,
        usesSystemInteractiveDismissal: Bool,
        @ViewBuilder content: () -> Content
    ) {
        _isPresented = isPresented
        self.usesSystemInteractiveDismissal = usesSystemInteractiveDismissal
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let isPhone = proxy.size.width < 720
            let playerSurface = ZStack(alignment: .top) {
                content

                if isPhone {
                    dragIndicator(safeAreaTop: proxy.safeAreaInsets.top)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .offset(y: usesSystemInteractiveDismissal ? 0 : dragOffset)
            .contentShape(Rectangle())

            // iOS 26 以下的 fullScreenCover 不稳定提供完整的下拉返回区域，
            // 用新的兼容性手势覆盖播放器表面；iOS 26+ 保留 1.6.5.1 的系统交互。
            if !usesSystemInteractiveDismissal {
                playerSurface.simultaneousGesture(dismissGesture)
            } else {
                playerSurface
            }
        }
        .onAppear { dragOffset = 0 }
    }

    @ViewBuilder
    private func dragIndicator(safeAreaTop: CGFloat) -> some View {
        let surface = ZStack(alignment: .top) {
            Color.clear
            Capsule()
                // Keep the indicator's hit area and gesture, but hide the visual
                // handle so the player uses a clean full-screen surface.
                .fill(.clear)
                .frame(
                    width: BeansNowPlayingPresentationMetrics.indicatorWidth,
                    height: BeansNowPlayingPresentationMetrics.indicatorHeight
                )
                .padding(.top, BeansNowPlayingPresentationMetrics.indicatorTopSpacing)
        }
        .frame(
            width: BeansNowPlayingPresentationMetrics.indicatorHitWidth,
            height: BeansNowPlayingPresentationMetrics.indicatorHitHeight
        )
        .modifier(AppleMusicLayoutTransform(entry: appleLayout.entry(for: .top)))
        .contentShape(Rectangle())
        .accessibilityLabel("下拉关闭播放页")

        if usesSystemInteractiveDismissal {
            surface
                .padding(.top, safeAreaTop)
        } else {
            surface
                .padding(.top, safeAreaTop)
                .allowsHitTesting(false)
        }
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                let vertical = value.translation.height
                let horizontal = value.translation.width
                let isDownwardSwipe = vertical > 0 && vertical > abs(horizontal) * 1.25
                // 旧系统只响应顶部开始的明确下拉。播放器内禁用左侧右滑返回，
                // 避免进度条及其他横向控件触发播放器关闭。
                if value.startLocation.y <= BeansNowPlayingPresentationMetrics.verticalStartZone,
                   isDownwardSwipe {
                    dragOffset = max(vertical, 0)
                } else {
                    dragOffset = 0
                }
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                let isTopSwipe = value.startLocation.y <= BeansNowPlayingPresentationMetrics.verticalStartZone
                    && vertical > 0
                    && vertical > abs(horizontal) * 1.25
                let translation = isTopSwipe ? max(vertical, 0) : 0
                let predictedVertical = value.predictedEndTranslation.height
                let prediction = isTopSwipe ? max(predictedVertical, 0) : 0
                if translation > BeansNowPlayingPresentationMetrics.dismissDistance
                    || prediction > BeansNowPlayingPresentationMetrics.dismissPrediction {
                    BeansHaptics.medium()
                    withAnimation(BeansNowPlayingPresentationMetrics.dismissAnimation) {
                        isPresented = false
                    }
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        dragOffset = 0
                    }
                }
            }
    }
}

struct PlatformPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let current: SearchProvider
    let providers: [SearchProvider]
    let onSelect: (SearchProvider) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("选择主页平台")
                .font(BeansFont.appFont(19, .bold))
                .foregroundStyle(Color.beansLabel)
            ForEach(providers) { provider in
                Button {
                    onSelect(provider)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: provider == current ? "checkmark.circle.fill" : provider.icon)
                            .foregroundStyle(provider == current ? Color.beansAmber : Color.beansComment)
                        Text(LocalizedStringKey(provider.rawValue))
                            .font(BeansFont.appFont(15, .medium))
                            .foregroundStyle(Color.beansLabel)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background { BeansGlass(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)) }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(Color.clear)
        .modifier(PlatformPickerPresentation(providersCount: providers.count))
    }
}

private struct ClearSheetBackground: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationBackground(.clear)
        } else {
            content
        }
    }
}

@available(iOS 26.0, *)
private struct MiniPlayerAccessoryModifier: ViewModifier {
    let isActive: Bool
    @Binding var showPlayer: Bool
    let clock: PlaybackClock
    let colorScheme: ColorScheme
    let transitionNamespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content.tabViewBottomAccessory {
                RootMiniPlayerAccessory(
                    showPlayer: $showPlayer,
                    clock: clock,
                    transitionNamespace: transitionNamespace
                )
                    .environment(\.colorScheme, colorScheme)
            }
        } else {
            content
        }
    }

}

/// 根据系统 accessory 位置在展开和紧凑布局之间切换。
@available(iOS 26.0, *)
private struct RootMiniPlayerAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Binding var showPlayer: Bool
    let clock: PlaybackClock
    let transitionNamespace: Namespace.ID

    var body: some View {
        MiniPlayerView(
            showPlayer: $showPlayer,
            presentation: presentation,
            transitionNamespace: transitionNamespace
        )
        .environmentObject(clock)
    }

    private var presentation: MiniPlayerView.Presentation {
        placement.map { $0 == .inline } == true ? .inlineAccessory : .accessory
    }
}

private struct GlassTabBar: View {
    struct Item: Identifiable {
        let tab: RootTab
        let title: LocalizedStringKey
        let icon: String
        var id: RootTab { tab }
    }

    let items: [Item]
    @Binding var selection: RootTab
    var labelsVisible: Bool
    var accentIsNativeClean: Bool
    var onHomeLongPress: (() -> Void)?
    var onSelect: (RootTab) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var dragX: CGFloat?
    @State private var isDragging = false

    private let innerInset: CGFloat = 4
    private let contentHeight: CGFloat = 56
    private let settle = Animation.spring(response: 0.35, dampingFraction: 0.82)

    var body: some View {
        GeometryReader { geo in
            let count = max(items.count, 1)
            let cellW = geo.size.width / CGFloat(count)
            let selectedIndex = items.firstIndex(where: { $0.tab == selection }) ?? 0
            let restX = cellW * (CGFloat(selectedIndex) + 0.5)
            let pillX = isDragging
                ? min(max(dragX ?? restX, cellW / 2), geo.size.width - cellW / 2)
                : restX

            ZStack(alignment: .leading) {
                selectionPill
                    .frame(width: cellW - 8, height: contentHeight)
                    .position(x: pillX, y: geo.size.height / 2)

                HStack(spacing: 0) {
                    ForEach(items) { item in
                        itemLabel(item)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(cellW: cellW, count: count))
        }
        .frame(height: contentHeight)
        .padding(innerInset)
        .background { Capsule().fill(.regularMaterial) }
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.08 : 0.22), lineWidth: 0.5)
        }
        .clipShape(Capsule())
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.10), radius: 12, y: 4)
        .padding(.horizontal, 12)
    }

    private func itemLabel(_ item: Item) -> some View {
        let isSelected = selection == item.tab
        return VStack(spacing: 3) {
            Image(systemName: item.icon)
                .font(.system(size: 23, weight: .semibold))
                .symbolVariant(.fill)
            if labelsVisible {
                Text(item.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(isSelected
                         ? AnyShapeStyle(accentIsNativeClean ? Color.red : Color.beansAmber)
                         : AnyShapeStyle(Color.primary.opacity(0.8)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
            guard item.tab == .discover else { return }
            BeansHaptics.select()
            onHomeLongPress?()
        })
    }

    private var selectionPill: some View {
        Capsule(style: .continuous)
            .fill(colorScheme == .dark
                  ? Color.white.opacity(0.10)
                  : Color.black.opacity(0.075))
    }

    private func index(for x: CGFloat, cellW: CGFloat, count: Int) -> Int {
        min(max(Int(x / cellW), 0), count - 1)
    }

    private func dragGesture(cellW: CGFloat, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging && abs(value.translation.width) < 8 { return }
                isDragging = true
                dragX = value.location.x
                let tab = items[index(for: value.location.x, cellW: cellW, count: count)].tab
                if tab != selection {
                    selection = tab
                    onSelect(tab)
                }
            }
            .onEnded { value in
                let tab = items[index(for: value.location.x, cellW: cellW, count: count)].tab
                withAnimation(settle) {
                    selection = tab
                    onSelect(tab)
                    dragX = nil
                }
                isDragging = false
            }
    }
}

private struct PlatformPickerPresentation: ViewModifier {
    let providersCount: Int

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .modifier(ClearSheetBackground())
                .presentationDetents([.height(CGFloat(116 + providersCount * 60))])
                .presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}

private struct VisualEffectBlur: UIViewRepresentable {
    var style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

private struct UpdatePromptOverlay: View {
    let info: UpdateChecker.ReleaseInfo
    let onOpen: () -> Void
    let onRemindLater: () -> Void
    let onDismiss: () -> Void

    private var details: String {
        let body = info.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? "本次更新暂无详细说明。" : body
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("发现新版本")
                            .font(BeansFont.appFont(20, .bold))
                            .foregroundStyle(Color.beansLabel)
                        Text("Beans Music \(info.version)")
                            .font(BeansFont.appFont(13, .semibold))
                            .foregroundStyle(Color.beansAmber)
                    }
                    Spacer(minLength: 8)
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.beansComment)
                            .frame(width: 30, height: 30)
                            .background(Color.beansGlassFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭")
                }

                Divider()
                    .overlay(Color.beansComment.opacity(0.16))
                    .padding(.vertical, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("更新内容")
                            .font(BeansFont.appFont(14, .semibold))
                            .foregroundStyle(Color.beansLabel)
                        Text(details)
                            .font(BeansFont.appFont(13))
                            .foregroundStyle(Color.beansComment)
                            .fixedSize(horizontal: false, vertical: true)
                        if let imageURL = info.notesImageURL {
                            AsyncImage(url: imageURL) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFit()
                                } else if phase.error == nil {
                                    ProgressView().frame(maxWidth: .infinity, minHeight: 70)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)

                VStack(spacing: 10) {
                    Button(action: onOpen) {
                        Text("立即更新")
                            .font(BeansFont.appFont(14, .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Color.beansAmber))
                    }
                    .buttonStyle(.plain)

                    Button("以后再说", action: onRemindLater)
                        .font(BeansFont.appFont(13, .semibold))
                        .foregroundStyle(Color.beansComment)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .buttonStyle(.plain)
                }
                .padding(.top, 18)
            }
            .padding(20)
            .frame(maxWidth: 360)
            .background {
                BeansGlass(shape: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .beansCardShadow(radius: 16, y: 8)
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - 系统 TabBar 清透风格（实例级配置）
// 系统 TabView 创建之后，`UITabBar.appearance()` 全局代理对已存在的实例不再生效，
// 所以每个 tab 页面内放一个 TabBarAppearanceConfigurator，通过 tabBarController
// 拿到当前 UITabBar 实例，直接设置固定清透外观（全透明、无阴影）。

struct TabBarAppearanceConfigurator: UIViewControllerRepresentable {
    var hidesSystemTabBarOnLegacy = true
    var onHomeLongPress: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onHomeLongPress: onHomeLongPress)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        // 纯外观配置视图：禁止拦截触摸，避免透明全屏视图吃掉页面按钮点击
        controller.view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            Self.apply(
                from: controller,
                hidesSystemTabBarOnLegacy: hidesSystemTabBarOnLegacy,
                coordinator: context.coordinator
            )
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.onHomeLongPress = onHomeLongPress
        DispatchQueue.main.async {
            Self.apply(
                from: uiViewController,
                hidesSystemTabBarOnLegacy: hidesSystemTabBarOnLegacy,
                coordinator: context.coordinator
            )
        }
    }

    /// 固定清透风格：全透明背景、无阴影；选中态用主题色，
    /// 材质与模糊完全交给系统对底层页面内容的渲染，不再支持手动调节透明度
    private static func apply(
        from controller: UIViewController,
        hidesSystemTabBarOnLegacy: Bool,
        coordinator: Coordinator
    ) {
        guard let tabBar = controller.tabBarController?.tabBar else { return }
        installHomeLongPress(on: tabBar, coordinator: coordinator)
        if #available(iOS 26, *) {
            tabBar.isHidden = false
            return
        } else if hidesSystemTabBarOnLegacy {
            tabBar.isHidden = true
            tabBar.isTranslucent = true
            return
        } else {
            tabBar.isHidden = false
        }
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        // 超薄材质模糊：与迷你播放器一致的清透玻璃透明度
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = UIColor.beansAmber
        tabBar.isTranslucent = true
    }

    private static func installHomeLongPress(on tabBar: UITabBar, coordinator: Coordinator) {
        let controls = tabBar.subviews
            .flatMap { descendants(of: $0) }
            .compactMap { $0 as? UIControl }
            .filter { !$0.isHidden && $0.alpha > 0 && $0.bounds.width > 0 }
            .sorted { $0.frame.minX < $1.frame.minX }
        guard let homeButton = controls.first else { return }
        guard homeButton.gestureRecognizers?.contains(where: { $0.name == Coordinator.gestureName }) != true else { return }

        let gesture = UILongPressGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleHomeLongPress(_:)))
        gesture.name = Coordinator.gestureName
        gesture.minimumPressDuration = 0.45
        gesture.cancelsTouchesInView = true
        homeButton.addGestureRecognizer(gesture)
    }

    private static func descendants(of view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }

    final class Coordinator: NSObject {
        static let gestureName = "beans.homePlatformLongPress"
        var onHomeLongPress: (() -> Void)?

        init(onHomeLongPress: (() -> Void)?) {
            self.onHomeLongPress = onHomeLongPress
        }

        @objc func handleHomeLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            BeansHaptics.select()
            onHomeLongPress?()
        }
    }
}

private struct RemoteAnnouncementOverlay: View {
    let text: String
    let mediaURL: String
    let mediaType: String
    let textColor: Color
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "megaphone.fill")
                        .foregroundStyle(Color.beansAmber)
                    Text("Beans Music 公告")
                        .font(BeansFont.appFont(19, .bold))
                        .foregroundStyle(Color.beansLabel)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.beansComment)
                            .frame(width: 30, height: 30)
                            .background(Color.beansGlassFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                if let url = URL(string: mediaURL), !mediaURL.isEmpty {
                    if mediaType.lowercased() == "video" {
                        AnnouncementVideoView(url: url)
                            .frame(maxWidth: .infinity)
                            .frame(height: 190)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFit()
                            } else if phase.error == nil {
                                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                Text(text)
                    .font(BeansFont.appFont(14, .medium))
                    .foregroundStyle(textColor)
                    .fixedSize(horizontal: false, vertical: true)

                Button("知道了", action: onDismiss)
                    .font(BeansFont.appFont(14, .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Color.beansAmber))
                    .buttonStyle(.plain)
            }
            .padding(20)
            .frame(maxWidth: 370)
            .background { BeansGlass(shape: RoundedRectangle(cornerRadius: 24, style: .continuous)) }
            .beansCardShadow(radius: 16, y: 8)
            .padding(.horizontal, 22)
        }
    }
}

struct AnnouncementVideoView: View {
    let url: URL
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .onAppear { player.play() }
            .onDisappear { player.pause() }
    }
}
