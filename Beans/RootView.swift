import SwiftUI
import UIKit
import AVKit

enum RootTab: String, CaseIterable, Identifiable {
    case discover
    case search
    case library
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: return "主页"
        case .search: return "搜索"
        case .library: return "音乐库"
        case .profile: return "我的"
        }
    }

    var icon: String {
        switch self {
        case .discover: return "house.fill"
        case .search: return "magnifyingglass"
        case .library: return "music.note.list"
        case .profile: return "person.crop.circle"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var favorites: FavoritesStore
    @ObservedObject private var platformPrefs = PlatformPreferenceStore.shared
    @AppStorage("beans.themeMode") private var themeModeRaw = BeansThemeMode.system.rawValue

    @State private var selection: RootTab = .discover
    @State private var showPlayer = false
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

    private var miniPlayerBottomPadding: CGFloat {
        return usesSystemFloatingTabBar ? 62 : 80
    }

    private var legacyTabResolvedCornerRadius: CGFloat {
        CGFloat(legacyTabCornerRadius)
    }

    private var legacyTabResolvedWidth: CGFloat {
        min(CGFloat(legacyTabWidth), max(300, UIScreen.main.bounds.width - 28))
    }

    private var isNativeClean: Bool {
        BeansUIStyle(rawValue: uiStyleRaw) == .nativeClean
    }

    var body: some View {
        let _ = theme.accent
        ZStack {
            // 系统原生 TabView：iOS 26 上 UITabBar 自动使用原生液态玻璃，
            // 按压折射反馈、拖动效果、高光均由系统渲染（与应用商店等系统 App 一致）。
            // 背景（壁纸/背景色）由每个 tab 页面内部的 GlassBackdrop 渲染，
            // 因为系统 TabView 的内容层会盖住 RootView 底层的 ZStack 背景。
            TabView(selection: $selection) {
                DiscoverView()
                    .tabItem { Label(tabLabelsVisible ? "主页" : "", systemImage: "house.fill") }
                    .tag(RootTab.discover)
                SearchView()
                    .tabItem { Label(tabLabelsVisible ? "搜索" : "", systemImage: "magnifyingglass") }
                    .tag(RootTab.search)
                LibraryView()
                    .tabItem { Label(tabLabelsVisible ? "音乐库" : "", systemImage: "music.note.list") }
                    .tag(RootTab.library)
                ProfileView()
                    .tabItem { Label(tabLabelsVisible ? "我的" : "", systemImage: "person.crop.circle") }
                    .tag(RootTab.profile)
            }
            .tint(Color.beansAmber)
            .background {
                TabBarAppearanceConfigurator(
                    hidesSystemTabBarOnLegacy: !usesSystemFloatingTabBar,
                    onHomeLongPress: { showHomePlatformMenu = true }
                )
            }

            if !usesSystemFloatingTabBar {
                legacyFloatingTabBar
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(8)
            }

            // 迷你播放器：悬浮在系统 TabBar 上方
            VStack(spacing: 0) {
                Spacer()
                if player.currentSong != nil {
                    MiniPlayerView(showPlayer: $showPlayer)
                        .environmentObject(player.clock)
                        .padding(.horizontal, 12)
                        .padding(.bottom, miniPlayerBottomPadding)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
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
            PlayerView(isPresented: $showPlayer)
                .environmentObject(favorites)
                .environmentObject(player)
                .environmentObject(player.clock)
                .environmentObject(auth)
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
        legacyTabItemsBar
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(width: legacyTabResolvedWidth)
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
            .offset(x: CGFloat(legacyTabOffsetX), y: CGFloat(legacyTabOffsetY))
    }

    private var legacyTabItemsBar: some View {
        HStack(spacing: 4) {
            ForEach(RootTab.allCases) { tab in
                Button {
                    guard selection != tab else { return }
                    BeansHaptics.select()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        selection = tab
                    }
                } label: {
                    let selected = selection == tab
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 17, weight: selected ? .semibold : .medium))
                            .symbolRenderingMode(.hierarchical)
                        if tabLabelsVisible {
                            Text(tab.title)
                                .font(BeansFont.appFont(10, selected ? .semibold : .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }
                    }
                    .foregroundStyle(selected ? (isNativeClean ? Color.red : Color.beansAmber) : Color.beansLabel.opacity(isNativeClean ? 0.92 : 0.70))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .fill(isNativeClean ? Color.primary.opacity(0.055) : Color.beansAmber.opacity(0.12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                                        .strokeBorder((isNativeClean ? Color.primary : Color.beansAmber).opacity(0.12), lineWidth: 0.7)
                                }
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
                .buttonStyle(GlassPressButtonStyle(scale: 0.94))
                .contextMenu {
                    if tab == .discover {
                        platformSelectionMenu
                    }
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: legacyTabResolvedCornerRadius, style: .continuous)
                .fill(isNativeClean ? Color(UIColor.systemBackground).opacity(0.96) : Color.clear)
                .background {
                    if !isNativeClean {
                        VisualEffectBlur(style: .systemUltraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: legacyTabResolvedCornerRadius, style: .continuous))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: legacyTabResolvedCornerRadius, style: .continuous)
                        .strokeBorder(isNativeClean ? Color.primary.opacity(0.08) : .white.opacity(0.20), lineWidth: 0.7)
                }
                .overlay {
                    if !isNativeClean {
                        RoundedRectangle(cornerRadius: legacyTabResolvedCornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.18), .white.opacity(0.04), .black.opacity(0.03)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: legacyTabResolvedCornerRadius, style: .continuous))
                    }
                }
                .shadow(color: .black.opacity(isNativeClean ? 0.10 : 0.16), radius: isNativeClean ? 12 : 18, y: isNativeClean ? 4 : 7)
        }
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
