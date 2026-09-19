import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

/// 自动下载新版 IPA 的结果
enum DownloadOutcome {
    case success(fileName: String)
    case failure(message: String)
}

struct ProfileView: View {
    /// 由主页头像以 sheet 打开时，使用主页同一套壁纸背景。
    var forceHomeBackdrop = false
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.beansUsesSharedRootBackdrop) private var usesSharedRootBackdrop
    @AppStorage("beans.themeMode") private var themeModeRaw = BeansThemeMode.system.rawValue
    @AppStorage("beans.uiStyle") private var uiStyleRaw = BeansUIStyle.liquid.rawValue
    @AppStorage("beans.homeHeaderHideSort") private var homeHeaderHideSort = false
    @AppStorage("beans.pauseHomeRendering") private var homeRenderingPaused = false

    @State private var showHistory = false

    /// 统一账号登录面板（网易云 + QQ 音乐整合）
    @State private var showAccountHub = false
    /// 设置页（外观 + 歌词翻译等）
    @State private var showSettings = false
    /// 手动检查更新
    @State private var checkingUpdate = false
    @State private var updateResult: UpdateChecker.CheckResult?
    @State private var showUpdateResult = false
    /// 自动下载新版 IPA
    @ObservedObject private var ipaDownloader = IPADownloader.shared
    @State private var showDownloadOverlay = false
    @State private var downloadOutcome: DownloadOutcome?
    @State private var showDownloadOutcome = false
    @State private var pendingUpdateInfo: UpdateChecker.ReleaseInfo?
    @State private var updateShareFile: ShareFileItem?
    @State private var updateShareFileURL: URL?
    @State private var didRefreshProfileAccount = false
    @State private var donationExpanded = false
    @State private var remoteDonors: [Donor] = []
    @State private var loadingRemoteDonors = false
    @State private var showWeChatOpenError = false
    @State private var showFeedback = false
    @State private var showAvatarPicker = false
    @State private var easterEggStep = 0
    @State private var easterEggPrompt = "点我有惊喜"
    @AppStorage("beans.profile.customNickname") private var customNickname = ""
    @ObservedObject private var feedbackHistory = FeedbackHistoryStore.shared
    @ObservedObject private var avatarStore = BeansAvatarStore.shared
    @ObservedObject private var qqAuth = QQMusicAuth.shared
    @ObservedObject private var kugouAuth = KugouMusicAuth.shared
    @ObservedObject private var platformPrefs = PlatformPreferenceStore.shared
    @AppStorage("beans.language") private var languageRaw = AppLanguage.chinese.rawValue
    @AppStorage("beans.globalFloatingEffect") private var globalFloatingEffectRaw = BeansGlobalFloatingEffect.off.rawValue
    @AppStorage("beans.globalFloatingDensity") private var globalFloatingDensity = 1.0
    @AppStorage("beans.globalFloatingSize") private var globalFloatingSize = 1.0
    @AppStorage("beans.globalFloatingSpeed") private var globalFloatingSpeed = 1.0
    @AppStorage("beans.globalFloatingText") private var globalFloatingText = "❄️"
    @AppStorage("beans.globalFloatingRotation") private var globalFloatingRotation = 0.0
    @AppStorage("beans.globalFloatingSkew") private var globalFloatingSkew = 0.0

    private var themeMode: BeansThemeMode {
        BeansThemeMode(rawValue: themeModeRaw) ?? .system
    }

    private var isNativeClean: Bool {
        BeansUIStyle(rawValue: uiStyleRaw) == .nativeClean
    }

    private var isEnglish: Bool { languageRaw == AppLanguage.english.rawValue }

    private var displayPlatformSummary: String {
        if !isEnglish { return platformPrefs.summaryText }
        return platformPrefs.enabledSearchProviders.map { provider in
            switch provider {
            case .netease: return "NetEase Cloud Music"
            case .qq: return "QQ Music"
            case .kugou: return "Kugou Music"
            }
        }.joined(separator: " / ")
    }

    private var appVersionText: String {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2"
        return "Beans Music · \(ver)"
    }

    /// 登录状态的合并提示（展示各平台真实昵称）
    private var accountStatusLine: String {
        var parts: [String] = []
        if platformPrefs.isEnabled(SearchProvider.netease), auth.isLoggedIn {
            if let nick = auth.user?.nickname, !nick.isEmpty {
                parts.append("网易云音乐 \(nick)")
            } else {
                parts.append("网易云音乐 UID \(auth.user?.uid ?? 0)")
            }
        }
        if platformPrefs.isEnabled(SearchProvider.qq), qqAuth.isLoggedIn {
                parts.append(qqAuth.nickname.isEmpty ? (isEnglish ? "QQ Music Logged In" : "QQ 已登录") : qqAuth.nickname)
        }
        if platformPrefs.isEnabled(SearchProvider.kugou), kugouAuth.isLoggedIn {
                parts.append(kugouAuth.nickname.isEmpty ? (isEnglish ? "Kugou Music Logged In" : "酷狗已登录") : kugouAuth.nickname)
        }
        if parts.isEmpty {
            return isEnglish ? "Sign in to sync \(displayPlatformSummary) playlists" : "登录后可同步 \(platformPrefs.summaryText) 歌单"
        }
        return parts.joined(separator: " · ")
    }

    private var hasVisibleAccountLogin: Bool {
        (platformPrefs.isEnabled(SearchProvider.netease) && auth.isLoggedIn)
            || (platformPrefs.isEnabled(SearchProvider.qq) && qqAuth.isLoggedIn)
            || (platformPrefs.isEnabled(SearchProvider.kugou) && kugouAuth.isLoggedIn)
    }

    /// Delay presentation by one main-queue turn so the active profile tab
    /// finishes its update before the settings controller is created.
    private func openSettings() {
        guard !showSettings else { return }
        BeansHaptics.tap()
        CrashReporter.shared.recordEvent("点击设置入口")
        homeRenderingPaused = true
        DispatchQueue.main.async {
            CrashReporter.shared.beginContext("settings")
            CrashReporter.shared.recordEvent("使用全屏设置容器")
            showSettings = true
        }
    }

    private func settingsScreen(_ screen: SettingsView) -> some View {
        screen
            .environmentObject(theme)
            .environmentObject(player)
            .environmentObject(auth)
            .onDisappear {
                CrashReporter.shared.endContext("settings")
            }
    }

    /// 顶部标题 + 右上角设置齿轮
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("我的")
                    .font(BeansFont.appFont(30, .bold))
                    .foregroundStyle(Color.beansLabel)
            }
            Spacer()
            HStack(spacing: 10) {
                GlassIconButton(systemName: "gearshape.fill", forceLiquid: true) {
                    openSettings()
                }
            }
        }
        .padding(.top, 8)
    }

    private var appleHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center) {
                Text("我的")
                    .font(BeansFont.appFont(38, .bold))
                    .foregroundStyle(Color.beansLabel)
                Spacer(minLength: 12)
                GlassIconButton(systemName: "gearshape", forceLiquid: true) {
                    openSettings()
                }
            }
            Rectangle()
                .fill(Color.beansLabel.opacity(0.10))
                .frame(height: 1)
        }
        .padding(.top, 4)
    }

    var body: some View {
        let _ = theme.accent
        ZStack {
            if forceHomeBackdrop || !usesSharedRootBackdrop {
                // 头像入口作为主页延伸时始终沿用主页壁纸；常规“我的”页继续遵循同步开关。
                GlassBackdrop(
                    customColor: forceHomeBackdrop ? theme.customBackground : (theme.backgroundSyncAll ? theme.customBackground : nil),
                    homeMode: forceHomeBackdrop
                )
            }
            // 实例级 UITabBar 清透风格（固定全透明，无需调节）
            TabBarAppearanceConfigurator()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: isNativeClean ? 26 : 22) {
                    if isNativeClean {
                        appleHeader
                    } else {
                        header
                    }
                    customAvatarCard
                    communityCard
                    donationCard
                    easterEggCard
                    profileVersionFooter
                }
                .padding(.horizontal, isNativeClean ? 24 : 16)
                .padding(.top, isNativeClean ? 14 : 8)
                .padding(.bottom, 190)
                .beansAdaptiveContentWidth()
            }
            .beansScrollIndicatorsHidden()
        }
        .task {
            guard !didRefreshProfileAccount else { return }
            didRefreshProfileAccount = true
            await auth.refreshAccount()
            if qqAuth.isLoggedIn {
                await qqAuth.fetchVIPStatus()
            }
        }
        .background {
            HighRefreshConfigurator()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
        .alert("无法打开微信", isPresented: $showWeChatOpenError) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("请使用微信扫描上方二维码完成赞助。")
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .environmentObject(player)
                .environmentObject(auth)
                .environmentObject(theme)
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackSheet()
                .environmentObject(theme)
        }
        .sheet(isPresented: $showAvatarPicker) {
            WallpaperPhotoPicker(allowsMultiple: false) { data in
                avatarStore.save(data: data)
            }
        }
        .fullScreenCover(isPresented: $showSettings) {
            settingsScreen(SettingsView(onClose: { showSettings = false }))
        }
        .sheet(item: $updateShareFile, onDismiss: cleanupUpdateShareFile) { item in
            ShareSheet(items: [item.url])
        }
        .alert("检查更新", isPresented: $showUpdateResult, presenting: updateResult) { result in
            switch result {
            case .update(let info):
                Button("立即更新") { UIApplication.shared.open(info.htmlURL) }
                Button("取消", role: .cancel) {}
            case .upToDate:
                Button("好", role: .cancel) {}
            case .failed:
                Button("好", role: .cancel) {}
            }
        } message: { result in
            switch result {
            case .update(let info):
                Text("发现新版本 \(info.version)，是否前往 GitHub 下载更新？")
            case .upToDate:
                Text("当前已是最新版本 \(UpdateChecker.currentVersion)")
            case .failed:
                Text("检查失败，请检查网络后重试")
            }
        }
        .overlay {
            if showDownloadOverlay { downloadProgressOverlay }
        }
        .alert("下载新版", isPresented: $showDownloadOutcome, presenting: downloadOutcome) { outcome in
            switch outcome {
            case .success:
                Button("好", role: .cancel) {}
            case .failure:
                Button("好", role: .cancel) {}
                Button("前往更新页") {
                    if let info = pendingUpdateInfo {
                        UIApplication.shared.open(info.htmlURL)
                    }
                }
            }
        } message: { outcome in
            switch outcome {
            case .success(let fileName):
                Text("新版 IPA 已下载完成，但未能打开分享面板。\n文件名：\(fileName)")
            case .failure(let message):
                Text("下载失败：\(message)")
            }
        }
    }

    /// 下载进度浮层（居中卡片，兼容所有系统版本）
    private var downloadProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.beansHighlight)
                    Text("正在下载新版 IPA")
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
                EmptyView()
            }
            .padding(22)
            .frame(maxWidth: 300)
            .background {
                BeansGlass(shape: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .beansCardShadow(radius: 12, y: 6)
            .padding(32)
        }
        .transition(.opacity)
    }

    private var totalPlayCount: Int {
        player.playCounts.values.reduce(0, +)
    }

    private var customAvatarCard: some View {
        VStack(spacing: 15) {
            HStack(spacing: 13) {
                Button {
                    BeansHaptics.tap()
                    showAvatarPicker = true
                } label: {
                    BeansAvatarView(remoteURL: nil, size: 58, useCustom: true)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(width: 20, height: 20)
                                .background(Color.beansAmber, in: Circle())
                                .overlay(Circle().stroke(Color.beansBackground, lineWidth: 2))
                        }
                }
                .buttonStyle(GlassPressButtonStyle(scale: 0.94))

                VStack(alignment: .leading, spacing: 5) {
                    TextField(isEnglish ? "Nickname" : "自定义昵称", text: $customNickname)
                        .font(BeansFont.appFont(17, .semibold))
                        .foregroundStyle(Color.beansLabel)
                        .textFieldStyle(.plain)
                        .lineLimit(1)
                    Text(isEnglish ? "Your Beans listening record" : "Beans 本机听歌记录")
                        .font(BeansFont.appFont(12, .medium))
                        .foregroundStyle(Color.beansSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "waveform")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.beansAmber)
            }

            Rectangle()
                .fill(Color.beansLabel.opacity(0.10))
                .frame(height: 1)

            HStack(spacing: 0) {
                profileStat(
                    title: isEnglish ? "Listening time" : "听歌时长",
                    value: player.formattedListeningDuration,
                    icon: "clock"
                )
                Rectangle()
                    .fill(Color.beansLabel.opacity(0.10))
                    .frame(width: 1, height: 31)
                profileStat(
                    title: isEnglish ? "Play count" : "播放次数",
                    value: "\(totalPlayCount) \(isEnglish ? "plays" : "次")",
                    icon: "music.note"
                )
            }
        }
        .padding(16)
        .background { BeansGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)) }
        .beansCardShadow(radius: 8, y: 3)
    }

    private func profileStat(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.beansAmber)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BeansFont.appFont(11, .medium))
                    .foregroundStyle(Color.beansSecondary)
                Text(value)
                    .font(BeansFont.appFont(15, .semibold))
                    .foregroundStyle(Color.beansLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var easterEggCard: some View {
        Button {
            BeansHaptics.tap()
            switch easterEggStep {
            case 0:
                easterEggStep = 1
                easterEggPrompt = ["再点一下", "求你了，再点一下", "哥哥我要来了"].randomElement() ?? "再点一下"
            case 1:
                easterEggStep = 2
                easterEggPrompt = ["最后一下！！", "马上出来了！！", "啊啊我要来了"].randomElement() ?? "最后一下！！"
            default:
                NotificationCenter.default.post(name: .beansEasterEggRequested, object: nil)
                easterEggStep = 0
                easterEggPrompt = "点我有惊喜"
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.beansAmber)
                    .frame(width: 28)
                Text(easterEggPrompt)
                    .font(BeansFont.appFont(14, .semibold))
                    .foregroundStyle(Color.beansLabel)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.beansComment.opacity(0.65))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background {
                BeansGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.98))
    }

    private var userCard: some View {
        VStack(spacing: 16) {
            Button {
                BeansHaptics.tap()
                // 统一账号面板：网易云 + QQ 音乐登录整合在一起
                showAccountHub = true
            } label: {
                HStack(spacing: 14) {
                    // 头像：主题渐变描边环
                    BeansAvatarView(remoteURL: auth.user?.avatarURL, size: 64, useCustom: true)
                    .background(Color.beansGlassFill, in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(auth.user?.nickname ?? (auth.isLoggedIn ? (isEnglish ? "NetEase Cloud Music Logged In" : "网易云音乐已登录") : (isEnglish ? "Guest · Tap to Sign In" : "免登录 · 点击登录")))
                                .font(BeansFont.appFont(20, .bold))
                                .foregroundStyle(Color.beansLabel)
                                .lineLimit(1)
                            if auth.isLoggedIn, let badge = auth.user?.vipBadge {
                                VIPBadgeView(text: badge)
                            }
                        }
                        Text(accountStatusLine)
                            .font(BeansFont.appFont(12, .regular, .monospaced))
                            .foregroundStyle(Color.beansComment)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.beansComment.opacity(0.7))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if (platformPrefs.isEnabled(SearchProvider.netease) && auth.isLoggedIn)
                || (platformPrefs.isEnabled(SearchProvider.qq) && qqAuth.isLoggedIn)
                || (platformPrefs.isEnabled(SearchProvider.kugou) && kugouAuth.isLoggedIn) {
                platformStatusRow
            }
        }
        .padding(16)
        .background {
                        BeansGlass(shape: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .beansCardShadow(radius: 10, y: 4)
    }

    /// 每个登录平台单独展示登录成功状态（网易云 / QQ 音乐）
    private var platformStatusRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if platformPrefs.isEnabled(SearchProvider.netease), auth.isLoggedIn {
                platformChip(imageName: "BrandNetease", name: "网易云音乐", status: auth.user?.nickname ?? "已登录", badge: auth.user?.vipBadge)
            }
            if platformPrefs.isEnabled(SearchProvider.qq), qqAuth.isLoggedIn {
                platformChip(imageName: "BrandQQ", name: "QQ 音乐", status: qqAuth.nickname.isEmpty ? "已登录" : qqAuth.nickname, badge: qqAuth.vipBadge)
            }
            if platformPrefs.isEnabled(SearchProvider.kugou), kugouAuth.isLoggedIn {
                platformChip(imageName: "BrandKugou", name: "酷狗音乐", status: kugouAuth.nickname.isEmpty ? "已登录" : kugouAuth.nickname, badge: kugouAuth.vipBadge)
            }
        }
        .padding(.top, 2)
    }

    private func platformChip(imageName: String, name: String, status: String, badge: String?) -> some View {
        HStack(spacing: 6) {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
            Text(name)
                .font(BeansFont.appFont(12, .semibold))
                .foregroundStyle(Color.beansLabel)
            Text(status)
                .font(BeansFont.appFont(11))
                .foregroundStyle(Color.beansComment)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let badge {
                VIPBadgeView(text: badge)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background { BeansSurface(shape: Capsule()) }
    }



    /// 壁纸格子：点击应用为当前背景；使用中的壁纸显示主题色边框+勾选；右上角删除
    private func wallpaperCell(path: String) -> some View {
        let isActive = path == theme.backgroundImagePath
        return ZStack(alignment: .topTrailing) {
            Button {
                BeansHaptics.tap()
                theme.applyWallpaper(at: path)
            } label: {
                Group {
                    if let img = BeansImageFileCache.image(at: path) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.beansGlassFill
                    }
                }
                .frame(height: 108)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.beansAmber)
                            .background { BeansSurface(shape: Circle()) }
                            .padding(5)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                BeansHaptics.medium()
                theme.deleteWallpaper(at: path)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.beansComment)
                    .frame(width: 28, height: 28)
                    .background { BeansSurface(shape: Circle()) }
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .padding(6)
            }
            .buttonStyle(.plain)
            .zIndex(2)
        }
    }

    /// 功能宫格：常用功能统一整合排版
    private var featuresGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "我的功能")
            VStack(spacing: 12) {
                featureCell(icon: "clock.arrow.circlepath", title: "播放历史", subtitle: String(format: NSLocalizedString("最近播放 %d 首", comment: ""), player.history.count)) {
                    showHistory = true
                }
                featureCell(icon: hasVisibleAccountLogin ? "checkmark.seal.fill" : "globe", title: isEnglish ? "Accounts and Sign-in" : "账号与登录", subtitle: hasVisibleAccountLogin ? accountStatusLine : (isEnglish ? "Sign in to \(displayPlatformSummary)" : "登录 \(platformPrefs.summaryText)")) {
                    BeansHaptics.tap()
                    showAccountHub = true
                }
            }
        }
    }

    private func featureCell(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button {
            BeansHaptics.tap()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.beansAmber)
                    .frame(width: 34, height: 34)
                    .background(Color.beansGlassFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(title))
                        .font(BeansFont.appFont(14, .semibold))
                        .foregroundStyle(Color.beansLabel)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                    Text(subtitle)
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(Color.beansComment)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background {
                                BeansGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
    }

    private func startAutoDownload(info: UpdateChecker.ReleaseInfo, assetURL: URL) {
        showDownloadOverlay = true
        Task {
            do {
                let url = try await ipaDownloader.download(assetURL: assetURL, version: info.version)
                await MainActor.run {
                    showDownloadOverlay = false
                    updateShareFileURL = url
                    updateShareFile = ShareFileItem(url: url)
                }
            } catch {
                await MainActor.run {
                    showDownloadOverlay = false
                    downloadOutcome = .failure(message: error.localizedDescription)
                    showDownloadOutcome = true
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

    /// 检查更新
    private var updateLinkCard: some View {
        VStack(spacing: 0) {
            Button {
                BeansHaptics.tap()
                guard !checkingUpdate else { return }
                checkingUpdate = true
                Task {
                    let result = await UpdateChecker.checkNow()
                    await MainActor.run {
                        checkingUpdate = false
                        updateResult = result
                        if case .update(let info) = result {
                            pendingUpdateInfo = info
                            if let assetURL = info.assetURL {
                                startAutoDownload(info: info, assetURL: assetURL)
                            } else {
                                showUpdateResult = true
                            }
                        } else {
                            showUpdateResult = true
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: checkingUpdate ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.beansHighlight)
                        .frame(width: 26)
                        .rotationEffect(.degrees(checkingUpdate ? 360 : 0))
                        .animation(checkingUpdate ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: checkingUpdate)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(checkingUpdate ? "正在检查…" : "检查更新")
                            .font(BeansFont.appFont(14, .semibold))
                            .foregroundStyle(Color.beansLabel)
                    }
                    Spacer()
                }
                .padding(16)
            }
            .buttonStyle(.plain)
            .disabled(checkingUpdate)
        }
        .background {
            BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .beansCardShadow(radius: 9, y: 3)
    }

    /// 我的页底部交流群入口
    private var communityCard: some View {
        Button {
            BeansHaptics.tap()
            if let url = URL(string: "https://t.me/+k8oYhsIU4sgzOTM1") {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.beansHighlight)
                    .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("交流群")
                            .font(BeansFont.appFont(14, .semibold))
                            .foregroundStyle(Color.beansLabel)
                    }
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.beansComment)
            }
            .padding(16)
            .background {
                BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.98))
        .beansCardShadow(radius: 9, y: 3)
    }

    private var profileVersionFooter: some View {
        Text(appVersionText)
            .font(BeansFont.appFont(11))
            .foregroundStyle(Color.beansComment.opacity(0.7))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }

    private var feedbackCard: some View {
        Button {
            BeansHaptics.tap()
            showFeedback = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.exclamationmark.bubble.right.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.beansHighlight)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(beansLocalized("问题反馈", "Feedback"))
                        .font(BeansFont.appFont(14, .semibold))
                        .foregroundStyle(Color.beansLabel)
                    if feedbackHistory.unreadReplyCount > 0 {
                        Text(beansLocalized(
                            "有 \(feedbackHistory.unreadReplyCount) 条新回复",
                            "\(feedbackHistory.unreadReplyCount) new repl\(feedbackHistory.unreadReplyCount == 1 ? "y" : "ies")"
                        ))
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(Color.beansAmber)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.beansComment)
            }
            .padding(16)
            .background {
                BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.98))
        .beansCardShadow(radius: 9, y: 3)
    }

    /// 我的页底部赞助入口与赞助排行榜
    private var donationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    donationExpanded.toggle()
                }
                if donationExpanded {
                    Task { await refreshRemoteDonorsIfNeeded() }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.beansAmber)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("自愿赞助")
                            .font(BeansFont.appFont(16, .bold))
                            .foregroundStyle(Color.beansLabel)
                    }
                    Spacer()
                    Image(systemName: donationExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.beansComment)
                }
            }
            .buttonStyle(.plain)

            if donationExpanded {
                Image("DonationQR")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 190)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.beansComment.opacity(0.14), lineWidth: 0.8)
                }

                Button {
                    openWeChatPayment()
                } label: {
                    Label("打开微信", systemImage: "arrow.up.forward.app")
                        .font(BeansFont.appFont(13, .semibold))
                        .foregroundStyle(Color.beansAmber)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.beansAmber.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(GlassPressButtonStyle(scale: 0.98))

                VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("赞助人员")
                        .font(BeansFont.appFont(15, .semibold))
                        .foregroundStyle(Color.beansLabel)
                    Spacer()
                    Text(loadingRemoteDonors ? "同步中" : "按金额排序")
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(Color.beansComment)
                }

                ForEach(displayedDonors.indices, id: \.self) { index in
                    let donor = displayedDonors[index]
                    HStack(spacing: 10) {
                        Text(index < 3 ? ["1", "2", "3"][index] : "\(index + 1)")
                            .font(BeansFont.appFont(index < 3 ? 14 : 13, .bold))
                            .foregroundStyle(sponsorRankColor(for: index))
                            .frame(width: 28, height: 28)
                            .background {
                                Circle()
                                    .fill(sponsorRankColor(for: index).opacity(index < 3 ? 0.18 : 0.08))
                                if index == 0 {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(Color.beansAmber.opacity(0.82))
                                        .offset(y: -16)
                                }
                            }
                        Text(donor.name)
                            .font(BeansFont.appFont(13, .medium))
                            .foregroundStyle(Color.beansLabel)
                        Spacer()
                        Text(String(format: "¥ %.2f", donor.amount))
                            .font(BeansFont.appFont(13, .semibold))
                            .foregroundStyle(index < 3 ? sponsorRankColor(for: index) : Color.beansLabel)
                    }
                    .padding(.horizontal, index < 3 ? 11 : 8)
                    .padding(.vertical, index < 3 ? 9 : 6)
                    .background {
                        if index < 3 {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            sponsorRankColor(for: index).opacity(0.16),
                                            sponsorRankColor(for: index).opacity(0.035)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(sponsorRankColor(for: index).opacity(0.28), lineWidth: 0.8)
                                }
                                .shadow(color: sponsorRankColor(for: index).opacity(0.22), radius: 12, y: 4)
                        }
                    }
                    .overlay {
                        if index < 3 {
                            SponsorRankHighlight(color: sponsorRankColor(for: index), rank: index)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    if index < displayedDonors.count - 1 {
                        Divider().overlay(Color.beansComment.opacity(0.12))
                    }
                }
                }
            }
        }
        .padding(16)
        .background {
            ZStack {
                if donationExpanded {
                    SponsorRankAtmosphere()
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .opacity(0.9)
                }
                BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .beansCardShadow(radius: 9, y: 3)
    }

    private func sponsorRankColor(for index: Int) -> Color {
        switch index {
        case 0: return Color(red: 1.0, green: 0.72, blue: 0.22)
        case 1: return Color(red: 0.72, green: 0.82, blue: 0.94)
        case 2: return Color(red: 0.84, green: 0.50, blue: 0.30)
        default: return Color.beansComment
        }
    }

    private func openWeChatPayment() {
        guard let paymentURL = URL(string: "wxp://f2f03Cvy7dWnLLRbIhQJqY-MxVACiIS4JBNSui8VmUk3_Qg") else {
            showWeChatOpenError = true
            return
        }

        UIApplication.shared.open(paymentURL, options: [:]) { opened in
            guard !opened, let weChatURL = URL(string: "weixin://") else { return }
            UIApplication.shared.open(weChatURL, options: [:]) { openedWeChat in
                if !openedWeChat {
                    showWeChatOpenError = true
                }
            }
        }
    }

    private var displayedDonors: [Donor] {
        remoteDonors.isEmpty ? Self.donors : remoteDonors
    }

    @MainActor
    private func refreshRemoteDonorsIfNeeded() async {
        guard !loadingRemoteDonors else { return }
        loadingRemoteDonors = true
        defer { loadingRemoteDonors = false }
        guard let url = URL(string: "http://189.24.78.193/beans/sponsors.json") else { return }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue("Beans-Music/\(UpdateChecker.currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let payload = try JSONDecoder().decode(RemoteSponsorPayload.self, from: data)
            guard payload.enabled else {
                remoteDonors = []
                return
            }
            let donors = payload.items
                .filter { $0.visible != false && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .sorted { lhs, rhs in
                    if lhs.sort != rhs.sort { return lhs.sort < rhs.sort }
                    return lhs.amount > rhs.amount
                }
                .map { Donor(name: $0.name, amount: $0.amount) }
            if !donors.isEmpty {
                remoteDonors = donors
            }
        } catch {
            // 网络失败时继续显示内置赞助名单，不打断用户浏览。
        }
    }

    private struct Donor {
        let name: String
        let amount: Double
    }

    private struct RemoteSponsorPayload: Decodable {
        let enabled: Bool
        let items: [RemoteSponsorItem]
    }

    private struct RemoteSponsorItem: Decodable {
        let name: String
        let amount: Double
        let sort: Int
        let visible: Bool?
    }

    private static let donors: [Donor] = [
        Donor(name: "WeChat", amount: 26.66),
        Donor(name: "Aert", amount: 8.88),
        Donor(name: "wxx", amount: 5),
        Donor(name: "！", amount: 3),
    ]
}

// MARK: - 交流群二维码

struct CommunityQRSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                VStack(spacing: 18) {
                    Image("CommunityQR")
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding(12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Color.beansComment.opacity(0.16), lineWidth: 0.8)
                        }
                        .padding(.horizontal, 24)
                    Text("扫码加入交流群")
                        .font(BeansFont.appFont(15, .semibold))
                        .foregroundStyle(Color.beansLabel)
                    Text("如二维码过期，可在 GitHub 或更新说明中获取最新入口")
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(Color.beansComment)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                .padding(.vertical, 22)
            }
            .navigationTitle("交流群")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .modifier(BeansSheetModifier(detents: [.medium, .large]))
    }
}

// MARK: - 统一账号登录面板（网易云 + QQ 音乐整合）

struct AccountHubSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var qqAuth = QQMusicAuth.shared
    @ObservedObject private var kugouAuth = KugouMusicAuth.shared
    @ObservedObject private var platformPrefs = PlatformPreferenceStore.shared
    @AppStorage("beans.language") private var languageRaw = AppLanguage.chinese.rawValue
    @Environment(\.dismiss) private var dismiss

    @State private var showNeteaseLogin = false
    @State private var showQQLogin = false
    @State private var showKugouLogin = false
    @State private var confirmNeteaseLogout = false
    @State private var confirmQQLogout = false
    @State private var confirmKugouLogout = false

    private var isEnglish: Bool { languageRaw == AppLanguage.english.rawValue }
    private var displayPlatformSummary: String {
        if !isEnglish { return platformPrefs.summaryText }
        return platformPrefs.enabledSearchProviders.map { provider in
            switch provider {
            case .netease: return "NetEase Cloud Music"
            case .qq: return "QQ Music"
            case .kugou: return "Kugou Music"
            }
        }.joined(separator: " / ")
    }

    var body: some View {
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "账号")
                        if platformPrefs.isEnabled(SearchProvider.netease) { neteaseCard }
                        if platformPrefs.isEnabled(SearchProvider.qq) { qqCard }
                        if platformPrefs.isEnabled(SearchProvider.kugou) { kugouCard }
                    }
                    .padding(16)
                }
                .beansScrollIndicatorsHidden()
            }
            .navigationTitle("账号登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showNeteaseLogin) {
            LoginView()
                .environmentObject(auth)
                .environmentObject(theme)
        }
        .sheet(isPresented: $showQQLogin) {
            QQLoginSheet()
                .environmentObject(theme)
        }
        .sheet(isPresented: $showKugouLogin) {
            KugouLoginSheet()
                .environmentObject(theme)
        }
        .confirmationDialog("退出网易云登录？", isPresented: $confirmNeteaseLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                auth.logout()
                WebLoginDataCleaner.clearNetEase()
                ToastCenter.shared.show("已退出网易云账号")
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("退出 QQ 音乐？", isPresented: $confirmQQLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                qqAuth.logout()
                WebLoginDataCleaner.clearQQMusic()
                ToastCenter.shared.show("已退出 QQ 音乐")
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("退出酷狗音乐？", isPresented: $confirmKugouLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                kugouAuth.logout()
                WebLoginDataCleaner.clearKugou()
                ToastCenter.shared.show("已退出酷狗音乐")
            }
            Button("取消", role: .cancel) {}
        }
    }

    /// 网易云账号卡片
    private var neteaseCard: some View {
        Button {
            BeansHaptics.tap()
            if auth.isLoggedIn { confirmNeteaseLogout = true } else { showNeteaseLogin = true }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.06))
                        .frame(width: 48, height: 48)
                    Image("BrandNetease")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("网易云音乐")
                        .font(BeansFont.appFont(15, .semibold))
                        .foregroundStyle(Color.beansLabel)
                    HStack(spacing: 6) {
                        Group {
                            if auth.isLoggedIn {
                                Text(auth.user?.nickname ?? NSLocalizedString("已登录", comment: ""))
                            } else {
                                Text(LocalizedStringKey("未登录 · 扫码登录同步歌单"))
                            }
                        }
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        if auth.isLoggedIn, let badge = auth.user?.vipBadge {
                            VIPBadgeView(text: badge)
                        }
                    }
                }
                Spacer()
                Text(auth.isLoggedIn ? "退出" : "登录")
                    .font(BeansFont.appFont(13, .medium))
                    .foregroundStyle(auth.isLoggedIn ? Color.red : Color.beansAmber)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background { BeansSurface(shape: Capsule()) }
            }
            .padding(14)
            .background {
                                BeansGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
    }

    /// QQ 音乐账号卡片
    private var qqCard: some View {
        Button {
            BeansHaptics.tap()
            if qqAuth.isLoggedIn { confirmQQLogout = true } else { showQQLogin = true }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.06))
                        .frame(width: 48, height: 48)
                    Image("BrandQQ")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("QQ 音乐")
                        .font(BeansFont.appFont(15, .semibold))
                        .foregroundStyle(Color.beansLabel)
                    HStack(spacing: 6) {
                        Group {
                            if qqAuth.isLoggedIn {
                                Text(qqAuth.nickname.isEmpty ? NSLocalizedString("已登录", comment: "") : qqAuth.nickname)
                            } else {
                                Text(LocalizedStringKey("未登录 · 网页 / 扫码 / Cookie 登录"))
                            }
                        }
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        if qqAuth.isLoggedIn, let badge = qqAuth.vipBadge {
                            VIPBadgeView(text: badge)
                        }
                    }
                }
                Spacer()
                Text(qqAuth.isLoggedIn ? "退出" : "登录")
                    .font(BeansFont.appFont(13, .medium))
                    .foregroundStyle(qqAuth.isLoggedIn ? Color.red : Color.beansAmber)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background { BeansSurface(shape: Capsule()) }
            }
            .padding(14)
            .background {
                                BeansGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
    }

    private var kugouCard: some View {
        Button {
            BeansHaptics.tap()
            if kugouAuth.isLoggedIn { confirmKugouLogout = true } else { showKugouLogin = true }
        } label: {
            HStack(spacing: 14) {
                Image("BrandKugou")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Color(red: 0.08, green: 0.43, blue: 1.0).opacity(0.22), radius: 10, y: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text("酷狗音乐")
                        .font(BeansFont.appFont(15, .semibold))
                        .foregroundStyle(Color.beansLabel)
                    HStack(spacing: 6) {
                        Group {
                            if kugouAuth.isLoggedIn {
                                Text(kugouAuth.nickname.isEmpty ? NSLocalizedString("已登录", comment: "") : kugouAuth.nickname)
                            } else {
                                Text(LocalizedStringKey("未登录 · App 扫码同步歌单"))
                            }
                        }
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        if kugouAuth.isLoggedIn, let badge = kugouAuth.vipBadge {
                            VIPBadgeView(text: badge)
                        }
                    }
                }
                Spacer()
                Text(kugouAuth.isLoggedIn ? "退出" : "登录")
                    .font(BeansFont.appFont(13, .medium))
                    .foregroundStyle(kugouAuth.isLoggedIn ? Color.red : Color.beansAmber)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background { BeansSurface(shape: Capsule()) }
            }
            .padding(14)
            .background {
                BeansGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
    }

}

// MARK: - 设置页（外观 + 歌词翻译，从「我的」右上角齿轮进入）

struct SettingsView: View {
    var onClose: (() -> Void)? = nil
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("beans.themeMode") private var themeModeRaw = BeansThemeMode.system.rawValue
    @AppStorage("beans.uiStyle") private var uiStyleRaw = BeansUIStyle.liquid.rawValue
    @AppStorage("beans.disableLiquidGlass") private var disableLiquidGlass = false
    @AppStorage("beans.language") private var languageRaw = AppLanguage.chinese.rawValue
    @AppStorage("beans.globalFloatingEffect") private var globalFloatingEffectRaw = BeansGlobalFloatingEffect.off.rawValue
    @AppStorage("beans.globalFloatingDensity") private var globalFloatingDensity = 1.0
    @AppStorage("beans.globalFloatingSize") private var globalFloatingSize = 1.0
    @AppStorage("beans.globalFloatingSpeed") private var globalFloatingSpeed = 1.0
    @AppStorage("beans.globalFloatingText") private var globalFloatingText = "❄️"
    @AppStorage("beans.globalFloatingRotation") private var globalFloatingRotation = 0.0
    @AppStorage("beans.globalFloatingSkew") private var globalFloatingSkew = 0.0
    @AppStorage("beans.globalFloatingImageData") private var globalFloatingImageData = ""
    @AppStorage("beans.homeWallpaperBlur") private var homeWallpaperBlur = 0.0
    /// 底栏是否显示文字（关闭后只显示图标）
    @AppStorage("beans.tabLabelsVisible") private var tabLabelsVisible = true
    @AppStorage("beans.tabIconStyle") private var tabIconStyleRaw = BeansTabIconStyle.sfSymbols.rawValue
    @AppStorage("beans.legacyTabCornerRadius") private var legacyTabCornerRadius = 32.0
    @AppStorage("beans.legacyTabWidth") private var legacyTabWidth = 356.0
    @AppStorage("beans.legacyTabOffsetX") private var legacyTabOffsetX = 0.0
    @AppStorage("beans.legacyTabOffsetY") private var legacyTabOffsetY = 0.0
    /// 第三方音源播放会员歌成功时提醒，默认开启
    @AppStorage("beans.showThirdPartyVIPNotice") private var showThirdPartyVIPNotice = true
    @AppStorage("beans.showSongVIPBadge") private var showSongVIPBadge = true
    /// 高刷新率请求，默认开启
    @AppStorage("beans.enableHighRefresh") private var enableHighRefresh = true
    @AppStorage("beans.audio.mixothers.v1") private var mixesWithOthers = false
    @AppStorage("beans.nowPlaying.enabled.v1") private var nowPlayingEnabled = true
    @AppStorage("beans.audioQuality") private var playbackAudioQualityRaw = BeansAudioQuality.hires.rawValue
    @AppStorage(PlayerManager.autoCrossPlatformFallbackKey) private var autoCrossPlatformFallback = true
    @AppStorage(PlayerManager.playbackSourcePreferenceKey) private var playbackSourcePreferenceRaw = PlaybackSourcePreference.automatic.rawValue
    @AppStorage(NetworkAudioQuality.connectionAwareKey) private var connectionAwareQuality = false
    @AppStorage(NetworkAudioQuality.wifiOfficialKey) private var wifiPlaybackAudioQualityRaw = BeansAudioQuality.hires.rawValue
    @AppStorage(NetworkAudioQuality.cellularOfficialKey) private var cellularPlaybackAudioQualityRaw = BeansAudioQuality.higher.rawValue
    @AppStorage("beans.favoriteDestination") private var favoriteDestinationRaw = FavoriteDestination.local.rawValue
    @AppStorage(BeansHaptics.enabledKey) private var hapticsEnabled = true
    @AppStorage("beans.playback.autoResumeLast") private var autoResumeLastPlayback = false
    @AppStorage("beans.labelColorHex") private var labelColorHex = ""
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
    @AppStorage("beans.pauseHomeRendering") private var homeRenderingPaused = false
    @AppStorage("beans.homeHideUsername") private var homeHideUsername = false
    @AppStorage("beans.homeHeaderHideSort") private var homeHeaderHideSort = false
    @AppStorage("beans.homeHeaderHideRefresh") private var homeHeaderHideRefresh = true
    @AppStorage(PlatformPreferenceStore.hidePickerKey) private var hidePlatformPicker = false
    @AppStorage("beans.home.dailySongsListStyle") private var dailySongsListStyle = false
    @ObservedObject private var sourceStore = UnblockSourceStore.shared
    @ObservedObject private var equalizer = BeansEqualizer.shared
    @AppStorage(ThirdPartyAudioQuality.storageKey) private var thirdPartyAudioQualityRaw = ThirdPartyAudioQuality.kb320.rawValue
    @AppStorage(NetworkAudioQuality.wifiThirdPartyKey) private var wifiThirdPartyAudioQualityRaw = ThirdPartyAudioQuality.flac.rawValue
    @AppStorage(NetworkAudioQuality.cellularThirdPartyKey) private var cellularThirdPartyAudioQualityRaw = ThirdPartyAudioQuality.kb320.rawValue
    @ObservedObject private var platformPrefs = PlatformPreferenceStore.shared
    @ObservedObject private var qqAuth = QQMusicAuth.shared
    @ObservedObject private var kugouAuth = KugouMusicAuth.shared

    @State private var appearanceExpanded = false
    @State private var appearanceDetailsExpanded = false
    @State private var platformExpanded = false
    @State private var playbackExpanded = false
    @State private var audioQualityExpanded = false
    @State private var showWallpaperPicker = false
    @State private var wallpaperAppearanceTarget: BeansWallpaperAppearance = .light
    @State private var showFontImporter = false
    @State private var showGreetingFontImporter = false
    /// 更新日志
    @State private var showChangelog = false
    @State private var backupDoc: BackupDocument?
    @State private var showExportBackup = false
    @State private var showRestorePicker = false
    @State private var pendingRestore: [String: Any]?
    @State private var showRestoreConfirm = false
    @State private var showSourceManager = false
    @State private var showEqualizer = false
    @State private var backupExpanded = false
    @State private var backupIncludeAccounts = false
    @State private var backupIncludeWallpapers = false
    @State private var backupMessage: String?
    @State private var clearingImageCache = false
    @State private var showAccountHub = false
    @State private var showFeedback = false
    @State private var checkingUpdate = false
    @State private var updateResult: UpdateChecker.CheckResult?
    @State private var showUpdateResult = false
    @State private var disclaimerExpanded = false
    @State private var showFloatingImagePicker = false
    @State private var showTabVisibilitySettings = false
    @State private var settingsContentReady = false
    @State private var selectedSettingsSection: SettingsSection?

    private enum SettingsSection: String, CaseIterable, Identifiable {
        case accountAndAppearance
        case playback
        case dataAndSupport

        var id: String { rawValue }

        var title: String {
            switch self {
            case .accountAndAppearance: return "账号与外观"
            case .playback: return "播放与音质"
            case .dataAndSupport: return "数据与支持"
            }
        }

        var subtitle: String {
            switch self {
            case .accountAndAppearance: return "账号、主题、壁纸与平台"
            case .playback: return "音源、音质、播放与均衡器"
            case .dataAndSupport: return "备份、缓存、更新与帮助"
            }
        }

        var systemImage: String {
            switch self {
            case .accountAndAppearance: return "person.crop.circle"
            case .playback: return "play.circle"
            case .dataAndSupport: return "externaldrive"
            }
        }
    }

    private var themeMode: BeansThemeMode {
        BeansThemeMode(rawValue: themeModeRaw) ?? .system
    }

    private var isNativeClean: Bool {
        BeansUIStyle(rawValue: uiStyleRaw) == .nativeClean
    }

    private var usesCustomWallpaper: Bool {
        theme.backgroundSyncAll && theme.customBackgroundImage(for: colorScheme) != nil
    }

    /// iOS/iPadOS 26 and earlier can tear down a large full-screen SwiftUI tree
    /// while its presenting tab is being recomputed.  Present a stable shell
    /// first, then attach the existing settings content on the next run loop.
    private var defersSettingsContentForCompatibility: Bool {
        if #available(iOS 27, *) { return false }
        return true
    }

    private var customSourceCount: Int {
        sourceStore.managementVisibleSources.count
    }

    private var thirdPartyAudioQualityOptions: [ThirdPartyAudioQuality] {
        let options = sourceStore.availableThirdPartyQualities()
        return options.isEmpty ? ThirdPartyAudioQuality.allCases : options
    }

    private var thirdPartyAudioQualitySelection: Binding<ThirdPartyAudioQuality> {
        Binding(
            get: {
                let stored = ThirdPartyAudioQuality(sourceValue: thirdPartyAudioQualityRaw) ?? .kb320
                return thirdPartyAudioQualityOptions.first(where: { $0 == stored }) ?? thirdPartyAudioQualityOptions.first ?? .kb320
            },
            set: { newValue in
                thirdPartyAudioQualityRaw = newValue.rawValue
            }
        )
    }

    private var thirdPartyAudioQualityTitle: String {
        beansLocalized("第三方音源音质", "Third-party source quality")
    }

    private var thirdPartyAudioQualityHint: String {
        beansLocalized("会优先按所选音质解析第三方音源，不可用时会自动降级。", "Third-party sources will try the selected quality first and downgrade automatically when unavailable.")
    }

    private var thirdPartyAudioQualityOptionsSignature: String {
        thirdPartyAudioQualityOptions.map(\.rawValue).joined(separator: ",")
    }

    @ViewBuilder
    private func liquidQualityOptionBackground(selected: Bool) -> some View {
        ZStack {
            BeansGlass(shape: Capsule(), forceLiquid: true)
            if selected {
                Capsule()
                    .fill(Color.beansAmber.opacity(0.16))
            }
        }
    }

    private func normalizeThirdPartyAudioQualitySelection() {
        let valid = thirdPartyAudioQualityOptions.first(where: { $0.rawValue == thirdPartyAudioQualityRaw }) ?? thirdPartyAudioQualityOptions.first ?? .kb320
        if valid.rawValue != thirdPartyAudioQualityRaw {
            thirdPartyAudioQualityRaw = valid.rawValue
        }
    }

    private var playbackAudioQualitySelection: Binding<BeansAudioQuality> {
        Binding(
            get: { BeansAudioQuality(rawValue: playbackAudioQualityRaw) ?? .hires },
            set: { playbackAudioQualityRaw = $0.rawValue }
        )
    }

    private var wifiPlaybackAudioQualitySelection: Binding<BeansAudioQuality> {
        Binding(
            get: { BeansAudioQuality(rawValue: wifiPlaybackAudioQualityRaw) ?? .hires },
            set: { wifiPlaybackAudioQualityRaw = $0.rawValue }
        )
    }

    private var cellularPlaybackAudioQualitySelection: Binding<BeansAudioQuality> {
        Binding(
            get: { BeansAudioQuality(rawValue: cellularPlaybackAudioQualityRaw) ?? .higher },
            set: { cellularPlaybackAudioQualityRaw = $0.rawValue }
        )
    }

    private var wifiThirdPartyAudioQualitySelection: Binding<ThirdPartyAudioQuality> {
        thirdPartyAudioQualityBinding(rawValue: $wifiThirdPartyAudioQualityRaw)
    }

    private var cellularThirdPartyAudioQualitySelection: Binding<ThirdPartyAudioQuality> {
        thirdPartyAudioQualityBinding(rawValue: $cellularThirdPartyAudioQualityRaw)
    }

    private func thirdPartyAudioQualityBinding(rawValue: Binding<String>) -> Binding<ThirdPartyAudioQuality> {
        Binding(
            get: {
                let stored = ThirdPartyAudioQuality(sourceValue: rawValue.wrappedValue) ?? .kb320
                return thirdPartyAudioQualityOptions.first(where: { $0 == stored }) ?? thirdPartyAudioQualityOptions.first ?? .kb320
            },
            set: { rawValue.wrappedValue = $0.rawValue }
        )
    }

    private var playbackQualitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.beansAmber)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(beansLocalized("播放音质", "Playback quality"))
                        .font(BeansFont.appFont(14, .semibold))
                        .foregroundStyle(Color.beansLabel)
                    Text(beansLocalized("按列表选择，无法使用时会由平台自动降级。", "Choose a quality below; the platform will downgrade automatically when unavailable."))
                        .font(BeansFont.appFont(10))
                        .foregroundStyle(Color.beansComment)
                        .lineLimit(1)
                }
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BeansAudioQuality.allCases) { quality in
                        let selected = playbackAudioQualitySelection.wrappedValue == quality
                        Button {
                            playbackAudioQualitySelection.wrappedValue = quality
                            BeansHaptics.select()
                        } label: {
                            HStack(spacing: 5) {
                                Text(quality.displayName)
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                            }
                            .font(BeansFont.appFont(12, selected ? .semibold : .medium))
                            .foregroundStyle(selected ? Color.beansAmber : Color.beansLabel)
                            .padding(.horizontal, 12)
                            .frame(height: 31)
                            .background {
                                liquidQualityOptionBackground(selected: selected)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var homeGreetingLines: [String] {
        let custom = homeGreetingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if custom.isEmpty { return ["自动问候"] }
        return custom.components(separatedBy: .newlines)
    }

    private func greetingLineSizeBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: {
                switch index {
                case 0: return homeGreetingLine1Size > 0 ? homeGreetingLine1Size : homeGreetingSize
                case 1: return homeGreetingLine2Size > 0 ? homeGreetingLine2Size : homeGreetingSize
                default: return homeGreetingLine3Size > 0 ? homeGreetingLine3Size : homeGreetingSize
                }
            },
            set: { value in
                switch index {
                case 0: homeGreetingLine1Size = value
                case 1: homeGreetingLine2Size = value
                default: homeGreetingLine3Size = value
                }
            }
        )
    }

    private func greetingLineColorBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: {
                let raw: String
                switch index {
                case 0: raw = homeGreetingLine1ColorHex
                case 1: raw = homeGreetingLine2ColorHex
                default: raw = homeGreetingLine3ColorHex
                }
                return Color(hex: raw) ?? (Color(hex: homeGreetingColorHex) ?? Color.beansLabel)
            },
            set: { color in
                let hex = color.hexString
                switch index {
                case 0: homeGreetingLine1ColorHex = hex
                case 1: homeGreetingLine2ColorHex = hex
                default: homeGreetingLine3ColorHex = hex
                }
            }
        )
    }

    private func greetingLineOffsetBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: {
                switch index {
                case 0: return homeGreetingLine1OffsetY
                case 1: return homeGreetingLine2OffsetY
                default: return homeGreetingLine3OffsetY
                }
            },
            set: { value in
                switch index {
                case 0: homeGreetingLine1OffsetY = value
                case 1: homeGreetingLine2OffsetY = value
                default: homeGreetingLine3OffsetY = value
                }
            }
        )
    }

    private func greetingLineGradientStartBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: {
                let raw: String
                switch index {
                case 0: raw = homeGreetingLine1GradientStartHex
                case 1: raw = homeGreetingLine2GradientStartHex
                default: raw = homeGreetingLine3GradientStartHex
                }
                return Color(hex: raw) ?? (Color(hex: homeGreetingGradientStartHex) ?? Color.beansLabel)
            },
            set: { color in
                switch index {
                case 0: homeGreetingLine1GradientStartHex = color.hexString
                case 1: homeGreetingLine2GradientStartHex = color.hexString
                default: homeGreetingLine3GradientStartHex = color.hexString
                }
            }
        )
    }

    private func greetingLineGradientEndBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: {
                let raw: String
                switch index {
                case 0: raw = homeGreetingLine1GradientEndHex
                case 1: raw = homeGreetingLine2GradientEndHex
                default: raw = homeGreetingLine3GradientEndHex
                }
                return Color(hex: raw) ?? (Color(hex: homeGreetingGradientEndHex) ?? Color.beansLabel)
            },
            set: { color in
                switch index {
                case 0: homeGreetingLine1GradientEndHex = color.hexString
                case 1: homeGreetingLine2GradientEndHex = color.hexString
                default: homeGreetingLine3GradientEndHex = color.hexString
                }
            }
        )
    }

    private func resetGreetingLineStyle(_ index: Int) {
        switch index {
        case 0:
            homeGreetingLine1Size = 0
            homeGreetingLine1ColorHex = ""
            homeGreetingLine1OffsetY = 0
            homeGreetingLine1GradientStartHex = ""
            homeGreetingLine1GradientEndHex = ""
        case 1:
            homeGreetingLine2Size = 0
            homeGreetingLine2ColorHex = ""
            homeGreetingLine2OffsetY = 0
            homeGreetingLine2GradientStartHex = ""
            homeGreetingLine2GradientEndHex = ""
        default:
            homeGreetingLine3Size = 0
            homeGreetingLine3ColorHex = ""
            homeGreetingLine3OffsetY = 0
            homeGreetingLine3GradientStartHex = ""
            homeGreetingLine3GradientEndHex = ""
        }
    }

    var body: some View {
        ZStack {
            GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
            VStack(spacing: 0) {
                settingsHeader
                Rectangle()
                    .fill(Color.beansLabel.opacity(0.08))
                    .frame(height: 1)
                if settingsContentReady {
                    settingsScrollContent
                } else {
                    Spacer(minLength: 0)
                    ProgressView()
                        .tint(Color.beansAmber)
                    Spacer(minLength: 0)
                }
            }
        }
        .environment(\.beansSettingsPerformanceMode, false)
        .preferredColorScheme(themeMode.colorScheme)
        .simultaneousGesture(settingsEdgeDismissGesture, including: .gesture)
        .onAppear {
            wallpaperAppearanceTarget = colorScheme == .dark ? .dark : .light
            if defersSettingsContentForCompatibility {
                DispatchQueue.main.async {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        settingsContentReady = true
                    }
                }
            } else {
                settingsContentReady = true
            }
            if #unavailable(iOS 26) {
                HighRefreshKeeper.shared.suspendTemporarily()
            }
        }
        .sheet(isPresented: $showWallpaperPicker) {
            WallpaperPhotoPicker { data in
                theme.addWallpaper(data, for: wallpaperAppearanceTarget.colorScheme)
                BeansHaptics.success()
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showFloatingImagePicker) {
            WallpaperPhotoPicker(allowsMultiple: false) { data in
                if let base64 = normalizedFloatingImageBase64(from: data) {
                    globalFloatingImageData = base64
                }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showFontImporter) {
            FontDocumentPicker { url in
                installFont(from: url)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showGreetingFontImporter) {
            FontDocumentPicker { url in
                installGreetingFont(from: url)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showChangelog) {
            ChangelogListView()
                .environmentObject(theme)
        }
        .fileExporter(
            isPresented: $showExportBackup,
            document: backupDoc,
            contentType: .json,
            defaultFilename: "Beans设置备份-\(Self.backupDateString())"
        ) { result in
            switch result {
            case .success:
                backupMessage = "配置备份已导出"
                ToastCenter.shared.show("配置备份已导出")
            case .failure(let error):
                backupMessage = "导出失败：\(error.localizedDescription)"
                ToastCenter.shared.show("导出失败")
            }
        }
        .sheet(isPresented: $showSourceManager) {
            ThirdPartySourceManagerSheet()
                .environmentObject(theme)
        }
        .sheet(isPresented: $showAccountHub) {
            AccountHubSheet()
                .environmentObject(auth)
                .environmentObject(theme)
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackSheet()
                .environmentObject(theme)
        }
        .alert("检查更新", isPresented: $showUpdateResult, presenting: updateResult) { result in
            switch result {
            case .update(let info):
                Button("立即更新") { UIApplication.shared.open(info.htmlURL) }
                Button("取消", role: .cancel) {}
            case .upToDate, .failed:
                Button("好", role: .cancel) {}
            }
        } message: { result in
            switch result {
            case .update(let info):
                Text("发现新版本 (info.version)，是否前往更新页？")
            case .upToDate:
                Text("当前已是最新版本")
            case .failed:
                Text("检查失败，请检查网络后重试")
            }
        }
        .sheet(isPresented: $showEqualizer) {
            EqualizerSettingsView()
                .environmentObject(theme)
        }
        .sheet(isPresented: $showTabVisibilitySettings) {
            TabVisibilitySettingsSheet()
                .environmentObject(theme)
        }
        .fullScreenCover(isPresented: $showRestorePicker) {
            BackupDocumentPicker { url in
                handleBackupImport(url)
            }
            .ignoresSafeArea()
        }
        .confirmationDialog("导入备份将覆盖当前部分设置，是否继续？", isPresented: $showRestoreConfirm, titleVisibility: .visible) {
            Button("恢复", role: .destructive) {
                applyRestore(pendingRestore)
            }
            Button("取消", role: .cancel) {}
        }
        .onAppear {
            homeRenderingPaused = true
        }
        .onDisappear {
            homeRenderingPaused = false
            if #unavailable(iOS 26) {
                HighRefreshKeeper.shared.resumeAfterTemporaryPause()
            }
        }
    }

    private var settingsScrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let section = selectedSettingsSection {
                    AnyView(settingsSectionContent(section))
                } else {
                    settingsHomeCatalog
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 40)
            .beansAdaptiveContentWidth()
        }
        .beansScrollIndicatorsHidden()
    }

    private var settingsHeader: some View {
        HStack(spacing: 12) {
            Button {
                if selectedSettingsSection == nil {
                    closeSettings()
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedSettingsSection = nil
                    }
                }
            } label: {
                Image(systemName: selectedSettingsSection == nil ? "xmark" : "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.beansLabel)
                    .frame(width: 44, height: 44)
                    .background {
                        BeansSurface(shape: Circle())
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(selectedSettingsSection == nil ? "关闭设置" : "返回设置")

            Text(selectedSettingsSection?.title ?? "设置")
                .font(BeansFont.appFont(20, .bold))
                .foregroundStyle(Color.beansLabel)

            Spacer(minLength: 0)

            if selectedSettingsSection != nil {
                Button(action: closeSettings) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.beansComment)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭设置")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var settingsHomeCatalog: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("设置")
                .font(BeansFont.appFont(30, .bold))
                .foregroundStyle(Color.beansLabel)
                .padding(.horizontal, 4)

            Text("将功能收纳为三个分类，进入后可直接调整。")
                .font(BeansFont.appFont(13))
                .foregroundStyle(Color.beansComment)
                .padding(.horizontal, 4)

            SettingsCatalogGroup {
                ForEach(SettingsSection.allCases) { section in
                    if section != .accountAndAppearance {
                        Divider()
                            .overlay(Color.primary.opacity(0.09))
                            .padding(.leading, 48)
                    }
                    settingsCatalogRow(section)
                }
            }
        }
    }

    private func settingsCatalogRow(_ section: SettingsSection) -> some View {
        Button {
            BeansHaptics.tap()
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedSettingsSection = section
            }
        } label: {
            HStack(spacing: 13) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.beansAmber)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(section.title)
                        .font(BeansFont.appFont(16, .semibold))
                        .foregroundStyle(Color.beansLabel)
                    Text(section.subtitle)
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.beansComment)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func settingsSectionContent(_ section: SettingsSection) -> AnyView {
        switch section {
        case .accountAndAppearance:
            return AnyView(VStack(spacing: 14) {
                AnyView(SettingsCatalogGroup { accountSection })
                AnyView(SettingsCatalogGroup { appearanceSection })
                AnyView(SettingsCatalogGroup { platformSection })
            })
        case .playback:
            return AnyView(VStack(spacing: 14) {
                AnyView(SettingsCatalogGroup { audioQualitySection })
                AnyView(SettingsCatalogGroup { playbackSection })
                AnyView(SettingsCatalogGroup { equalizerSection })
            })
        case .dataAndSupport:
            return AnyView(VStack(spacing: 14) {
                AnyView(SettingsCatalogGroup { backupSection })
                AnyView(SettingsCatalogGroup { changelogSection })
                AnyView(SettingsCatalogGroup { settingsSupportSection })
            })
        }
    }

    private func closeSettings() {
        onClose?()
    }

    /// Keep the familiar left-edge swipe available on every system version,
    /// including native navigation hosts that do not expose the gesture from a
    /// full-screen cover.
    private var settingsEdgeDismissGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onEnded { value in
                guard value.startLocation.x <= 42 else { return }
                guard value.translation.width >= 72 else { return }
                guard abs(value.translation.width) > abs(value.translation.height) * 1.35 else { return }
                closeSettings()
            }
    }

    private var catalogDivider: some View {
        Divider()
            .overlay(Color.primary.opacity(0.09))
            .padding(.leading, 48)
    }

    private func officialQualityPills(_ selection: Binding<BeansAudioQuality>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BeansAudioQuality.allCases) { quality in
                    let selected = selection.wrappedValue == quality
                    Button {
                        selection.wrappedValue = quality
                        BeansHaptics.select()
                    } label: {
                        Text(quality.displayName)
                            .font(BeansFont.appFont(12, selected ? .semibold : .medium))
                            .foregroundStyle(selected ? Color.beansAmber : Color.beansLabel)
                            .padding(.horizontal, 12)
                            .frame(height: 31)
                            .background { liquidQualityOptionBackground(selected: selected) }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func thirdPartyQualityPills(_ selection: Binding<ThirdPartyAudioQuality>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(thirdPartyAudioQualityOptions) { quality in
                    let selected = selection.wrappedValue == quality
                    Button {
                        selection.wrappedValue = quality
                        BeansHaptics.select()
                    } label: {
                        Text(quality.displayName)
                            .font(BeansFont.appFont(12, selected ? .semibold : .medium))
                            .foregroundStyle(selected ? Color.beansAmber : Color.beansLabel)
                            .padding(.horizontal, 12)
                            .frame(height: 31)
                            .background { liquidQualityOptionBackground(selected: selected) }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func networkQualityRow(
        title: String,
        icon: String,
        officialSelection: Binding<BeansAudioQuality>,
        thirdPartySelection: Binding<ThirdPartyAudioQuality>
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon)
                .font(BeansFont.appFont(14, .semibold))
                .foregroundStyle(Color.beansLabel)
            Text("官方音质")
                .font(BeansFont.appFont(11))
                .foregroundStyle(Color.beansComment)
            officialQualityPills(officialSelection)
            Text("第三方音源")
                .font(BeansFont.appFont(11))
                .foregroundStyle(Color.beansComment)
            thirdPartyQualityPills(thirdPartySelection)
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var audioQualitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                BeansHaptics.select()
                withAnimation(.easeInOut(duration: 0.22)) {
                    audioQualityExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.beansAmber)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("音源与音质")
                            .font(BeansFont.appFont(15))
                            .foregroundStyle(Color.beansLabel)
                        Text(connectionAwareQuality ? "已按 Wi-Fi / 蜂窝网络分别选择" : "统一音质")
                            .font(BeansFont.appFont(11))
                            .foregroundStyle(Color.beansComment)
                    }
                    Spacer()
                    Image(systemName: audioQualityExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.beansComment.opacity(0.6))
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle(scale: 0.98))

            if audioQualityExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("播放来源")
                            .font(BeansFont.appFont(14, .semibold))
                            .foregroundStyle(Color.beansLabel)
                        Picker("播放来源", selection: $playbackSourcePreferenceRaw) {
                            ForEach(PlaybackSourcePreference.allCases) { preference in
                                Text(preference.title).tag(preference.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text((PlaybackSourcePreference(rawValue: playbackSourcePreferenceRaw) ?? .automatic).detail)
                            .font(BeansFont.appFont(11))
                            .foregroundStyle(Color.beansComment)
                    }

                    Divider().overlay(Color.beansComment.opacity(0.15))
                    Toggle("按网络类型选择音质", isOn: $connectionAwareQuality)
                        .font(BeansFont.appFont(14))
                        .tint(Color.beansAmber)

                    if connectionAwareQuality {
                        networkQualityRow(
                            title: "Wi-Fi",
                            icon: "wifi",
                            officialSelection: wifiPlaybackAudioQualitySelection,
                            thirdPartySelection: wifiThirdPartyAudioQualitySelection
                        )
                        networkQualityRow(
                            title: "蜂窝数据",
                            icon: "antenna.radiowaves.left.and.right",
                            officialSelection: cellularPlaybackAudioQualitySelection,
                            thirdPartySelection: cellularThirdPartyAudioQualitySelection
                        )
                    } else {
                        playbackQualitySection
                        Divider().overlay(Color.beansComment.opacity(0.15))
                        Text(thirdPartyAudioQualityTitle)
                            .font(BeansFont.appFont(14, .semibold))
                            .foregroundStyle(Color.beansLabel)
                        thirdPartyQualityPills(thirdPartyAudioQualitySelection)
                    }

                    Divider().overlay(Color.beansComment.opacity(0.15))
                    Toggle(isOn: $autoCrossPlatformFallback) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("播放失败时切换平台")
                                .font(BeansFont.appFont(14, .semibold))
                            Text("当前平台及其音源失败后，会匹配其它平台的同一歌曲并交给已启用音源解析。")
                                .font(BeansFont.appFont(11))
                                .foregroundStyle(Color.beansComment)
                        }
                    }
                    .tint(Color.beansAmber)

                    Divider().overlay(Color.beansComment.opacity(0.15))
                    Button {
                        showSourceManager = true
                        BeansHaptics.tap()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "shippingbox.fill")
                            Text("管理 / 导入音源")
                            Spacer()
                            Text("\(customSourceCount) 个")
                                .foregroundStyle(Color.beansComment)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .font(BeansFont.appFont(13, .semibold))
                        .foregroundStyle(Color.beansLabel)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .task(id: thirdPartyAudioQualityOptionsSignature) {
                    normalizeThirdPartyAudioQualitySelection()
                }
            }
        }
    }

    /// 主题相关设置统一归组，避免平台和排行榜外观选项散落在设置页。
    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            appearanceSection
            platformSection
        }
    }

    private var accountSection: some View {
        Button {
            BeansHaptics.tap()
            showAccountHub = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.beansAmber)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(beansLocalized("账号登录", "Account sign-in"))
                        .font(BeansFont.appFont(15, .semibold))
                        .foregroundStyle(Color.beansLabel)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.beansComment.opacity(0.65))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.98))
    }

    /// 校验扩展名并安装字体（asCopy 返回的 URL 已在沙盒内，可直接读取）
    private func installFont(from url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ["ttf", "otf", "ttc"].contains(ext) else {
            ToastCenter.shared.show("请选择 ttf / otf 字体文件")
            return
        }
        if let name = FontManager.install(from: url) {
            BeansHaptics.success()
            ToastCenter.shared.show("字体已应用：\(name)")
        } else {
            ToastCenter.shared.show("字体安装失败，请使用 ttf / otf 文件")
        }
    }

    private func installGreetingFont(from url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ["ttf", "otf", "ttc"].contains(ext) else {
            ToastCenter.shared.show("请选择 ttf / otf 字体文件")
            return
        }
        if let name = FontManager.installGreeting(from: url) {
            homeGreetingFontName = name
            BeansHaptics.success()
            ToastCenter.shared.show("主页问候字体已应用：\(name)")
        } else {
            ToastCenter.shared.show("主页问候字体安装失败，请使用 ttf / otf 文件")
        }
    }

    private var platformSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                BeansHaptics.select()
                withAnimation(.easeInOut(duration: 0.22)) {
                    platformExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "checklist")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.beansAmber)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("平台显示")
                            .font(BeansFont.appFont(15))
                            .foregroundStyle(Color.beansLabel)
                    }
                    Spacer()
                    Image(systemName: platformExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.beansComment.opacity(0.6))
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle(scale: 0.98))

            if platformExpanded {
                PlatformPreferencePicker()
                    .padding(.horizontal, 4)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// 外观设置（原「我的」页外观折叠内容）
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 外观设置行：点击展开 / 收起全部外观设置
            Button {
                BeansHaptics.select()
                withAnimation(.easeInOut(duration: 0.25)) {
                    appearanceExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.beansAmber)
                        .frame(width: 28)
                    Text("主题模式")
                        .font(BeansFont.appFont(15))
                        .foregroundStyle(Color.beansLabel)
                    Spacer()
                    Image(systemName: appearanceExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.beansComment.opacity(0.6))
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle(scale: 0.98))

            if appearanceExpanded {
            VStack(alignment: .leading, spacing: 14) {
                Picker("主题模式", selection: $themeModeRaw) {
                    ForEach(BeansThemeMode.allCases) { mode in
                        Text(LocalizedStringKey(mode.title)).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Picker("语言", selection: $languageRaw) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.beansAmber)

                if #available(iOS 26, *) {
                    Toggle("关闭液态模式", isOn: $disableLiquidGlass)
                        .font(BeansFont.appFont(15))
                        .tint(Color.beansAmber)
                }

                DisclosureGroup(isExpanded: $appearanceDetailsExpanded) {
                    VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("全局漂浮特效")
                                .font(BeansFont.appFont(15))
                                .foregroundStyle(Color.beansLabel)
                        }
                    }
                    Picker("全局漂浮特效", selection: $globalFloatingEffectRaw) {
                        ForEach(BeansGlobalFloatingEffect.allCases) { effect in
                            Label(effect.title, systemImage: effect.icon).tag(effect.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(Color.beansAmber)
                    if globalFloatingEffectRaw != BeansGlobalFloatingEffect.off.rawValue {
                        layoutSettingSlider("特效密度", value: $globalFloatingDensity, range: 0.4...2.4, step: 0.1, format: "%.1fx")
                        layoutSettingSlider("粒子大小", value: $globalFloatingSize, range: 0.6...2.2, step: 0.1, format: "%.1fx")
                        layoutSettingSlider("动画速度", value: $globalFloatingSpeed, range: 0.4...1.8, step: 0.1, format: "%.1fx")
                        if globalFloatingEffectRaw == BeansGlobalFloatingEffect.customText.rawValue {
                            TextField("文字或 Emoji", text: $globalFloatingText)
                                .textFieldStyle(.roundedBorder)
                                .font(BeansFont.appFont(14))
                            HStack(spacing: 12) {
                                Button {
                                    showFloatingImagePicker = true
                                } label: {
                                    Label(
                                        globalFloatingImageData.isEmpty ? "上传漂浮图片" : "更换漂浮图片",
                                        systemImage: "photo.badge.plus"
                                    )
                                    .font(BeansFont.appFont(13, .medium))
                                    .foregroundStyle(Color.beansAmber)
                                }
                                .buttonStyle(.plain)
                                if !globalFloatingImageData.isEmpty {
                                    Button("清除图片") {
                                        globalFloatingImageData = ""
                                    }
                                    .font(BeansFont.appFont(12))
                                    .foregroundStyle(Color.beansComment)
                                    .buttonStyle(.plain)
                                }
                            }
                            layoutSettingSlider("旋转", value: $globalFloatingRotation, range: -180...180, step: 1, format: "%.0f°")
                            layoutSettingSlider("倾斜", value: $globalFloatingSkew, range: -45...45, step: 1, format: "%.0f°")
                        }
                    }
                }

                Toggle(isOn: $tabLabelsVisible) {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.3.group")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("底栏显示文字")
                                .font(BeansFont.appFont(15))
                                .foregroundStyle(Color.beansLabel)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.beansAmber)

                Button {
                    BeansHaptics.tap()
                    showTabVisibilitySettings = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.3.group.bubble")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("底部栏显示")
                                .font(BeansFont.appFont(15))
                                .foregroundStyle(Color.beansLabel)
                            Text("选择要显示的主页入口")
                                .font(BeansFont.appFont(12))
                                .foregroundStyle(Color.beansComment)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.beansComment)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        Text("底栏图标样式")
                            .font(BeansFont.appFont(15))
                            .foregroundStyle(Color.beansLabel)
                    }
                    Picker("底栏图标样式", selection: $tabIconStyleRaw) {
                        ForEach(BeansTabIconStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(Color.beansAmber)
                }

                Toggle(isOn: $showSongVIPBadge) {
                    HStack(spacing: 12) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("显示歌曲 VIP 图标")
                                .font(BeansFont.appFont(15))
                                .foregroundStyle(Color.beansLabel)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.beansAmber)

                Divider().overlay(Color.beansComment.opacity(0.15))

                Divider().overlay(Color.beansComment.opacity(0.15))

                if #unavailable(iOS 26) {
                    legacyTabBarSettings

                    Divider().overlay(Color.beansComment.opacity(0.15))
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        Text("全局 UI 样式")
                            .font(BeansFont.appFont(15))
                            .foregroundStyle(Color.beansLabel)
                        Spacer()
                    }
                    Picker("全局 UI 样式", selection: Binding(
                        get: { theme.uiStyle },
                        set: { theme.setUIStyle($0) }
                    )) {
                        ForEach(BeansUIStyle.allCases, id: \.self) { style in
                            Text(LocalizedStringKey(style.title)).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Divider().overlay(Color.beansComment.opacity(0.15))

                HStack {
                    Image(systemName: "eyedropper.halffull")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.beansAmber)
                        .frame(width: 28)
                    Text("自定义强调色")
                        .font(BeansFont.appFont(15))
                        .foregroundStyle(Color.beansLabel)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { theme.customAccent ?? Color.beansAmber },
                        set: { theme.setCustomAccent($0.hexString) }
                    ))
                    .labelsHidden()
                }
                HStack(spacing: 12) {
                    Button {
                        theme.clearCustomAccent()
                        BeansHaptics.select()
                    } label: {
                        Text("恢复预设")
                            .font(BeansFont.appFont(13, .medium))
                            .foregroundStyle(Color.beansAmber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background { BeansSurface(shape: Capsule()) }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                            Text(LocalizedStringKey(theme.customAccentHex == nil ? "使用预设主题" : "已自定义"))
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                }

                    Divider().overlay(Color.beansComment.opacity(0.15))

                    HStack {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        Text(beansLocalized("主页背景色", "Home Background Color"))
                            .font(BeansFont.appFont(15))
                            .foregroundStyle(Color.beansLabel)
                        Spacer()
                    }
                    Picker(beansLocalized("背景模式", "Background Mode"), selection: $wallpaperAppearanceTarget) {
                        ForEach(BeansWallpaperAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(Color.beansAmber)
                    HStack {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        Text(beansLocalized("背景颜色", "Background Color"))
                            .font(BeansFont.appFont(15))
                            .foregroundStyle(Color.beansLabel)
                        Spacer()
                        ColorPicker("", selection: Binding(
                            get: { theme.customBackground(for: wallpaperAppearanceTarget.colorScheme) ?? Color.beansBackground },
                            set: { theme.setBackground($0.hexString, for: wallpaperAppearanceTarget.colorScheme) }
                        ))
                        .labelsHidden()
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        Button {
                            showWallpaperPicker = true
                        } label: {
                            HStack(spacing: 8) {
                                Text("上传壁纸（可多张）")
                                    .font(BeansFont.appFont(15))
                                    .foregroundStyle(Color.beansLabel)
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color.beansAmber)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    // 壁纸库：所有已上传壁纸，点击即应用为当前背景
                    if !theme.wallpaperPaths.isEmpty {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                            ForEach(theme.wallpaperPaths, id: \.self) { path in
                                wallpaperCell(path: path, appearance: wallpaperAppearanceTarget)
                            }
                        }
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.beansComment)
                            Text("还没有壁纸，上传后会显示在这里")
                                .font(BeansFont.appFont(12))
                                .foregroundStyle(Color.beansComment)
                            Spacer()
                        }
                    }
                    HStack(spacing: 12) {
                        if theme.customBackgroundImage(for: wallpaperAppearanceTarget.colorScheme) != nil {
                            Button {
                                theme.clearBackgroundImage(for: wallpaperAppearanceTarget.colorScheme)
                                BeansHaptics.select()
                            } label: {
                                Text("清除当前背景")
                                    .font(BeansFont.appFont(13, .medium))
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background { BeansSurface(shape: Capsule()) }
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                            Text(LocalizedStringKey(theme.customBackgroundImage(for: wallpaperAppearanceTarget.colorScheme) == nil ? "当前：默认背景" : "当前：已应用壁纸"))
                            .font(BeansFont.appFont(12))
                            .foregroundStyle(Color.beansComment)
                    }
                Toggle(isOn: Binding(
                    get: { theme.backgroundSyncAll },
                    set: { theme.setBackgroundSyncAll($0) }
                )) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.beansAmber)
                        Text(LocalizedStringKey("同步到搜索 / 音乐库 / 我的"))
                            .font(BeansFont.appFont(13))
                            .foregroundStyle(Color.beansLabel)
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.beansAmber)

                Divider().overlay(Color.beansComment.opacity(0.15))

                HStack {
                    Button {
                        theme.setBackground("")
                        BeansHaptics.select()
                    } label: {
                        Text("恢复默认背景")
                            .font(BeansFont.appFont(13, .medium))
                            .foregroundStyle(Color.beansAmber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        .background { BeansSurface(shape: Capsule()) }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }

                Divider().overlay(Color.beansComment.opacity(0.15))

                HStack {
                    Image(systemName: "text.quote")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.beansAmber)
                        .frame(width: 28)
                    Text("注释文字颜色")
                        .font(BeansFont.appFont(15))
                        .foregroundStyle(Color.beansLabel)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: {
                            if let raw = UserDefaults.standard.string(forKey: "beans.commentColorHex"),
                               let c = Color(hex: raw) { return c }
                            return Color.beansComment
                        },
                        set: { UserDefaults.standard.set($0.hexString, forKey: "beans.commentColorHex") }
                    ))
                    .labelsHidden()
                }
                HStack(spacing: 12) {
                    Button {
                        UserDefaults.standard.removeObject(forKey: "beans.commentColorHex")
                        BeansHaptics.select()
                    } label: {
                        Text("恢复默认")
                            .font(BeansFont.appFont(13, .medium))
                            .foregroundStyle(Color.beansAmber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        .background { BeansSurface(shape: Capsule()) }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(LocalizedStringKey("全 App 说明文字颜色"))
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                }

                Divider().overlay(Color.beansComment.opacity(0.15))

                HStack {
                    Image(systemName: "house.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.beansAmber)
                        .frame(width: 28)
                    Text("主文字颜色")
                        .font(BeansFont.appFont(15))
                        .foregroundStyle(Color.beansLabel)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: {
                            if let c = Color(hex: labelColorHex) { return c }
                            return Color.beansLabel
                        },
                        set: {
                            labelColorHex = $0.hexString
                            theme.objectWillChange.send()
                        }
                    ), supportsOpacity: false)
                    .labelsHidden()
                }
                HStack(spacing: 12) {
                    Button {
                        labelColorHex = ""
                        theme.objectWillChange.send()
                        BeansHaptics.select()
                    } label: {
                        Text("恢复默认")
                            .font(BeansFont.appFont(13, .medium))
                            .foregroundStyle(Color.beansAmber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        .background { BeansSurface(shape: Capsule()) }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(LocalizedStringKey("全 App 主文字颜色"))
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                }

                Divider().overlay(Color.beansComment.opacity(0.15))

                // Greeting customization was removed; retain only wallpaper controls below.
                if false {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "text.badge.star")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        Text("主页问候文字")
                            .font(BeansFont.appFont(15))
                            .foregroundStyle(Color.beansLabel)
                        Spacer()
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: homeGreetingColorHex) ?? Color.beansLabel },
                            set: { homeGreetingColorHex = $0.hexString }
                        ), supportsOpacity: false)
                        .labelsHidden()
                    }

                    HStack {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        Text("主页壁纸模糊度")
                            .font(BeansFont.appFont(15))
                            .foregroundStyle(Color.beansLabel)
                        Spacer()
                        Text("\(Int(homeWallpaperBlur))")
                            .font(BeansFont.appFont(12))
                            .foregroundStyle(Color.beansComment)
                    }
                    Slider(value: $homeWallpaperBlur, in: 0...30, step: 1)
                        .tint(Color.beansAmber)
                    TextEditor(text: $homeGreetingText)
                        .font(BeansFont.appFont(15))
                        .frame(minHeight: 88, maxHeight: 180)
                        .padding(6)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            if homeGreetingText.isEmpty {
                                Text(LocalizedStringKey("留空自动显示早上好/下午好/晚上好"))
                                    .font(BeansFont.appFont(13))
                                    .foregroundStyle(Color.beansComment.opacity(0.8))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 14)
                                    .allowsHitTesting(false)
                            }
                        }
                    VStack(spacing: 8) {
                        HStack {
                            Text("文字大小")
                            Spacer()
                            Text("\(Int(homeGreetingSize))")
                                .foregroundStyle(Color.beansComment)
                        }
                        Slider(value: $homeGreetingSize, in: 20...64, step: 1)
                        HStack {
                            Text("标题区高度")
                            Spacer()
                            Text(homeGreetingHeight <= 0 ? "自动" : "\(Int(homeGreetingHeight))")
                                .foregroundStyle(Color.beansComment)
                        }
                        Slider(value: $homeGreetingHeight, in: 0...260, step: 1)
                    }
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansLabel)
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("开启文字背景发光", isOn: $homeGreetingGlowEnabled)
                        HStack {
                            Text("发光强度")
                            Spacer()
                            Text("\(Int(homeGreetingGlowIntensity * 100))%")
                                .foregroundStyle(Color.beansComment)
                        }
                        Slider(value: $homeGreetingGlowIntensity, in: 0...2, step: 0.01)
                            .tint(Color.beansAmber)
                            .disabled(!homeGreetingGlowEnabled)
                    }
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansLabel)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "textformat")
                                .foregroundStyle(Color.beansAmber)
                            Text("问候语专属字体")
                            Spacer()
                            Text(LocalizedStringKey(homeGreetingFontName.isEmpty ? "跟随全局" : "已设置"))
                                .foregroundStyle(Color.beansComment)
                        }
                        HStack(spacing: 10) {
                            Button {
                                showGreetingFontImporter = true
                            } label: {
                                Label("选择字体", systemImage: "text.badge.plus")
                            }
                            .buttonStyle(.bordered)
                            .tint(Color.beansAmber)
                            if !homeGreetingFontName.isEmpty {
                                Button("清除专属字体") {
                                    FontManager.clearGreeting()
                                    homeGreetingFontName = ""
                                    BeansHaptics.select()
                                }
                                .buttonStyle(.bordered)
                                .tint(Color.beansComment)
                            }
                        }
                        Text("仅主页问候语使用该字体；清除后跟随全局字体，没有全局字体时使用系统字体。")
                            .font(BeansFont.appFont(11))
                            .foregroundStyle(Color.beansComment)
                    }
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansLabel)
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("显示底部横线", isOn: $homeGreetingUnderline)
                        Toggle("开启上下渐变字", isOn: $homeGreetingGradient)
                        if homeGreetingGradient {
                            ColorPicker("渐变起始颜色", selection: Binding(
                                get: { Color(hex: homeGreetingGradientStartHex) ?? (Color(hex: homeGreetingColorHex) ?? Color.beansLabel) },
                                set: { homeGreetingGradientStartHex = $0.hexString }
                            ), supportsOpacity: false)
                            ColorPicker("渐变结束颜色", selection: Binding(
                                get: { Color(hex: homeGreetingGradientEndHex) ?? (Color(hex: homeGreetingColorHex) ?? Color.beansLabel) },
                                set: { homeGreetingGradientEndHex = $0.hexString }
                            ), supportsOpacity: false)
                        }
                    }
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansLabel)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("逐行调节")
                            .font(BeansFont.appFont(13, .semibold))
                            .foregroundStyle(Color.beansLabel)
                        ForEach(Array(homeGreetingLines.prefix(3).enumerated()), id: \.offset) { index, line in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(String(format: NSLocalizedString("第%d行", comment: ""), index + 1))
                                        .font(BeansFont.appFont(12, .semibold))
                                    Text(line.isEmpty ? "空行" : line)
                                        .font(BeansFont.appFont(11))
                                        .foregroundStyle(Color.beansComment)
                                        .lineLimit(1)
                                    Spacer()
                                    Button("跟随全局") {
                                        resetGreetingLineStyle(index)
                                    }
                                    .font(BeansFont.appFont(11, .medium))
                                    .foregroundStyle(Color.beansAmber)
                                    .buttonStyle(.plain)
                                }
                                HStack {
                                    Text("字号")
                                    Spacer()
                                    Text("\(Int(greetingLineSizeBinding(index).wrappedValue))")
                                        .foregroundStyle(Color.beansComment)
                                }
                                Slider(value: greetingLineSizeBinding(index), in: 12...80, step: 1)
                                    .tint(Color.beansAmber)
                                HStack(spacing: 12) {
                                    ColorPicker("颜色", selection: greetingLineColorBinding(index), supportsOpacity: false)
                                    Spacer()
                                    Text("上下偏移 \(Int(greetingLineOffsetBinding(index).wrappedValue))")
                                        .foregroundStyle(Color.beansComment)
                                }
                                Slider(value: greetingLineOffsetBinding(index), in: -80...80, step: 1)
                                    .tint(Color.beansAmber)
                                if homeGreetingGradient {
                                    HStack(spacing: 12) {
                                        ColorPicker("渐变起始", selection: greetingLineGradientStartBinding(index), supportsOpacity: false)
                                        Spacer()
                                        ColorPicker("渐变结束", selection: greetingLineGradientEndBinding(index), supportsOpacity: false)
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansLabel)
                }

                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("主页壁纸模糊度")
                        Spacer()
                        Text("\(Int(homeWallpaperBlur))")
                            .foregroundStyle(Color.beansComment)
                    }
                    .font(BeansFont.appFont(12))
                    Slider(value: $homeWallpaperBlur, in: 0...30, step: 1)
                        .tint(Color.beansAmber)
                }

                Divider().overlay(Color.beansComment.opacity(0.15))

                appearanceToggle("隐藏主页用户名", isOn: $homeHideUsername)
                appearanceToggle("隐藏所有界面排序按钮", isOn: $homeHeaderHideSort)
                appearanceToggle("隐藏顶部平台列表", isOn: $hidePlatformPicker)
                appearanceToggle("隐藏主页刷新按钮", isOn: $homeHeaderHideRefresh)
                appearanceToggle("每日推荐使用旧版样式", isOn: $dailySongsListStyle)

                HStack {
                    Image(systemName: "textformat")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.beansAmber)
                        .frame(width: 28)
                    Text("全局字体")
                        .font(BeansFont.appFont(15))
                        .foregroundStyle(Color.beansLabel)
                    Spacer()
                    Text(FontManager.installedFontName ?? "系统默认")
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                }
                HStack(spacing: 12) {
                    Button {
                        showFontImporter = true
                    } label: {
                        Text("上传字体")
                            .font(BeansFont.appFont(13, .medium))
                            .foregroundStyle(Color.beansAmber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    .background { BeansSurface(shape: Capsule()) }
                    }
                    .buttonStyle(.plain)
                    Button {
                        FontManager.clear()
                        BeansHaptics.select()
                        ToastCenter.shared.show("已恢复系统默认字体")
                    } label: {
                        Text("恢复默认字体")
                            .font(BeansFont.appFont(13, .medium))
                            .foregroundStyle(Color.beansAmber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    .background { BeansSurface(shape: Capsule()) }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                    }
                } label: {
                    Label("更多外观与主页设置", systemImage: "slider.horizontal.3")
                        .font(BeansFont.appFont(14, .semibold))
                        .foregroundStyle(Color.beansLabel)
                }
                .tint(Color.beansAmber)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 14)
            }
        }
    }

    private func appearanceToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .font(BeansFont.appFont(13))
            .toggleStyle(.switch)
            .tint(Color.beansAmber)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 10)
            .contentShape(Rectangle())
    }

    /// 播放与歌词设置。
    private var equalizerSection: some View {
        Button {
            BeansHaptics.select()
            showEqualizer = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.beansAmber)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(beansLocalized("均衡器", "Equalizer"))
                        .font(BeansFont.appFont(15))
                        .foregroundStyle(Color.beansLabel)
                }
                Spacer()
                Text(equalizer.isEnabled ? beansLocalized("已开启", "On") : beansLocalized("已关闭", "Off"))
                    .font(BeansFont.appFont(12, .medium))
                    .foregroundStyle(equalizer.isEnabled ? Color.beansAmber : Color.beansComment)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.beansComment.opacity(0.6))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.98))
    }

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                BeansHaptics.select()
                withAnimation(.easeInOut(duration: 0.22)) {
                    playbackExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.beansAmber)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("播放设置")
                            .font(BeansFont.appFont(15))
                            .foregroundStyle(Color.beansLabel)
                    }
                    Spacer()
                    Image(systemName: playbackExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.beansComment.opacity(0.6))
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle(scale: 0.98))

            if playbackExpanded {
            VStack(spacing: 14) {
                Toggle(isOn: $mixesWithOthers) {
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("与其他音频同时播放")
                                .font(BeansFont.appFont(15))
                                .foregroundStyle(Color.beansLabel)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.beansAmber)
                .onChange(of: mixesWithOthers) { value in
                    player.setMixesWithOthers(value)
                }

                Divider().overlay(Color.beansComment.opacity(0.15))

                Toggle(isOn: $nowPlayingEnabled) {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.iphone")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(beansLocalized("显示锁屏与灵动岛播放器", "Show Lock Screen and Dynamic Island player"))
                                .font(BeansFont.appFont(15))
                                .foregroundStyle(Color.beansLabel)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.beansAmber)
                .onChange(of: nowPlayingEnabled) { value in
                    player.setNowPlayingEnabled(value)
                }

                Divider().overlay(Color.beansComment.opacity(0.15))

                HStack(spacing: 12) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.beansAmber)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("120Hz 高刷新")
                            .font(BeansFont.appFont(15))
                            .foregroundStyle(Color.beansLabel)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.beansAmber)
                }
                .onAppear {
                    enableHighRefresh = true
                    HighRefreshKeeper.shared.configure(enabled: true)
                }

                Divider().overlay(Color.beansComment.opacity(0.15))

                Toggle(isOn: $autoResumeLastPlayback) {
                    HStack(spacing: 12) {
                        Image(systemName: "play.square.stack.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(beansLocalized("启动时自动播放上次歌曲", "Auto-play the last song on launch"))
                                .font(BeansFont.appFont(15))
                                .foregroundStyle(Color.beansLabel)
                            Text(beansLocalized("打开软件后自动恢复上次未播放完的歌曲", "Automatically resume the last unfinished song when the app starts."))
                                .font(BeansFont.appFont(11))
                                .foregroundStyle(Color.beansComment)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.beansAmber)

                Divider().overlay(Color.beansComment.opacity(0.15))

                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("收藏保存位置")
                                .font(BeansFont.appFont(15))
                                .foregroundStyle(Color.beansLabel)
                            Text("QQ 音乐始终保存到本地收藏")
                                .font(BeansFont.appFont(11))
                                .foregroundStyle(Color.beansComment)
                        }
                    }
                    Picker("收藏保存位置", selection: $favoriteDestinationRaw) {
                        ForEach(FavoriteDestination.allCases) { destination in
                            Text(destination.title).tag(destination.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Divider().overlay(Color.beansComment.opacity(0.15))

                Toggle(isOn: $hapticsEnabled) {
                    HStack(spacing: 12) {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        Text(beansLocalized("触感反馈", "Haptic Feedback"))
                            .font(BeansFont.appFont(15))
                            .foregroundStyle(Color.beansLabel)
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.beansAmber)

                Divider().overlay(Color.beansComment.opacity(0.15))

                Toggle(isOn: $showThirdPartyVIPNotice) {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(beansLocalized("第三方播放会员歌提醒", "VIP song notice for third-party playback"))
                                .font(BeansFont.appFont(15))
                                .foregroundStyle(Color.beansLabel)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.beansAmber)

            }
            .padding(.horizontal, 4)
            .padding(.bottom, 14)
            .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// 更新日志入口
    private var changelogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                BeansHaptics.tap()
                showChangelog = true
            } label: {
                HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.beansAmber)
                        .frame(width: 28)
                    Text("更新日志")
                        .font(BeansFont.appFont(15))
                        .foregroundStyle(Color.beansLabel)
                    Spacer()
                    Text("v\(ChangelogStore.currentVersion)")
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.beansComment.opacity(0.6))
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
    }
    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                BeansHaptics.select()
                withAnimation(.easeInOut(duration: 0.22)) {
                    backupExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "externaldrive.fill")
                        .foregroundStyle(Color.beansAmber)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("备份与恢复")
                            .font(BeansFont.appFont(15))
                            .foregroundStyle(Color.beansLabel)
                    }
                    Spacer()
                    Image(systemName: backupExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Color.beansComment)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            if backupExpanded {
            VStack(spacing: 10) {
                Toggle("备份登录信息", isOn: $backupIncludeAccounts)
                    .tint(Color.beansAmber)
                    .font(BeansFont.appFont(13))
                Divider().opacity(0.35)
                Toggle("备份壁纸图片", isOn: $backupIncludeWallpapers)
                    .tint(Color.beansAmber)
                    .font(BeansFont.appFont(13))
                Divider().opacity(0.35)
                Text("默认不带账号登录信息；关闭壁纸后只备份普通设置，不写入壁纸图片数据")
                    .font(BeansFont.appFont(11))
                    .foregroundStyle(Color.beansComment)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background {
                BeansGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            HStack(spacing: 10) {
                backupActionButton(icon: "square.and.arrow.up", title: "导出备份") {
                    BeansHaptics.tap()
                    exportBackup(includeAccounts: backupIncludeAccounts, includeWallpapers: backupIncludeWallpapers)
                }
                backupActionButton(icon: "square.and.arrow.down", title: "导入恢复") {
                    BeansHaptics.tap()
                    showRestorePicker = true
                }
            }
            backupActionButton(
                icon: clearingImageCache ? "arrow.triangle.2.circlepath" : "trash",
                title: clearingImageCache ? "正在清除图片缓存…" : "清除图片缓存"
            ) {
                guard !clearingImageCache else { return }
                clearingImageCache = true
                BeansCoverImageStore.clearCache { success in
                    clearingImageCache = false
                    backupMessage = success ? "已清除封面图片缓存" : "清除图片缓存失败"
                }
            }
            .disabled(clearingImageCache)
            if let backupMessage {
                Text(backupMessage)
                    .font(BeansFont.appFont(11))
                    .foregroundStyle(Color.beansComment)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            }
        }
    }

    private func backupActionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(LocalizedStringKey(title))
            }
            .font(BeansFont.appFont(14, .semibold))
            .foregroundStyle(Color.beansLabel)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                BeansGlass(shape: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.95))
    }

    private static func isAccountBackupKey(_ key: String) -> Bool {
        key == "beans.user"
            || key.hasPrefix("beans.netease.")
            || key.hasPrefix("beans.qqmusic.")
            || key.hasPrefix("beans.kugou.")
    }

    private static func isPrivacyBackupKey(_ key: String) -> Bool {
        key.hasPrefix("beans.search.")
            || key.hasPrefix("beans.log")
            || key.hasPrefix("beans.crash")
            || key == "beans.thirdPartyAPIKeys"
            || key == "beans.launchInProgress"
            || key == "beans.wallpapers.deleted"
    }

    private static func isWallpaperBackupKey(_ key: String) -> Bool {
        key == "beans.background.image"
            || key == "beans.background.image.light"
            || key == "beans.background.image.dark"
            || key == "beans.background.custom"
            || key == "beans.background.custom.light"
            || key == "beans.background.custom.dark"
            || key == "beans.wallpapers.list"
            || key == "beans.wallpapers.data"
            || key == "beans.lyricBackground.image"
            || key == "beans.lyricBackground.data"
    }

    private static func isSystemBackupKey(_ key: String) -> Bool {
        key.hasPrefix("Apple")
            || key.hasPrefix("NS")
            || key.hasPrefix("com.apple.")
            || key == "AddingEmojiKeybordHandled"
    }

    private static func isBackupCandidateKey(_ key: String) -> Bool {
        key.hasPrefix("beans.") && !isSystemBackupKey(key)
    }

    private static func isExcludedBackupKey(_ key: String, includeAccounts: Bool = false, includeWallpapers: Bool = true) -> Bool {
        (!includeAccounts && isAccountBackupKey(key))
            || (!includeWallpapers && isWallpaperBackupKey(key))
            || isPrivacyBackupKey(key)
            || key == "beans.backup.meta"
            || key == "beans.font.restore"
    }

    /// 导出：收集本 App 设置，排除账号、搜索记录和日志，交给系统原生导出面板
    private func exportBackup(includeAccounts: Bool, includeWallpapers: Bool) {
        let defaults = UserDefaults.standard
        var payload: [String: Any] = [:]
        if includeWallpapers {
            theme.refreshWallpaperBackupForExport()
            LyricBackgroundStore.refreshForExport()
        }
        for (key, value) in defaults.dictionaryRepresentation() {
            guard Self.isBackupCandidateKey(key) else { continue }
            guard !Self.isExcludedBackupKey(key, includeAccounts: includeAccounts, includeWallpapers: includeWallpapers) else { continue }
            // 超大原始 Data 直接跳过（壁纸 base64 已以字符串形式存于 beans.wallpapers.data，不受影响）
            if let data = value as? Data, data.count > 2 * 1024 * 1024 { continue }
            let safe = backupJSONSafe(value)
            // 逐个校验可序列化，异常类型直接跳过，避免整份备份生成失败
            guard JSONSerialization.isValidJSONObject([key: safe]) else { continue }
            payload[key] = safe
        }
        // 字体文件（Documents/Fonts）随备份一起导出
        if let font = FontManager.exportFontData() {
            payload["beans.font.restore"] = [
                "name": font.name,
                "data": font.data.base64EncodedString(),
            ] as [String: Any]
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        payload["beans.backup.meta"] = [
            "app": "Beans Music",
            "created": ISO8601DateFormatter().string(from: Date()),
            "version": version,
            "includedAccounts": includeAccounts,
            "includedWallpapers": includeWallpapers,
            "excluded": [
                includeAccounts ? nil : "account",
                includeWallpapers ? nil : "wallpapers",
                "search history",
                "logs",
            ].compactMap { $0 }.joined(separator: ", "),
        ] as [String: Any]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            backupMessage = "备份生成失败：存在无法序列化的设置项"
            ToastCenter.shared.show("备份生成失败")
            return
        }
        backupDoc = BackupDocument(data: data)
        backupMessage = nil
        BeansLogger.shared.log("导出配置备份（\(payload.count) 项，账号=\(includeAccounts ? "包含" : "排除") 壁纸=\(includeWallpapers ? "包含" : "排除")）", level: .info)
        showExportBackup = true
    }

    private static func backupDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// 读取用户选择的备份文件并解析，弹确认后恢复
    private func handleBackupImport(_ url: URL) {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            ToastCenter.shared.show("备份文件解析失败")
            return
        }
        pendingRestore = json
        showRestoreConfirm = true
    }

    /// 恢复：把 JSON 备份中除账号、搜索记录和日志外的本 App 设置写回 UserDefaults
    private func applyRestore(_ json: [String: Any]?) {
        guard let json else { return }
        let defaults = UserDefaults.standard
        var count = 0
        for (key, value) in json {
            guard Self.isBackupCandidateKey(key) else { continue }
            guard !Self.isExcludedBackupKey(key, includeAccounts: true, includeWallpapers: true) else { continue }
            guard let restored = backupPlistSafe(value) else { continue }
            defaults.set(restored, forKey: key)
            count += 1
        }
        // 兼容旧备份：旧版本只有一套背景，恢复后让浅色和深色都继承它。
        if json["beans.background.custom.light"] == nil,
           json["beans.background.custom.dark"] == nil,
           let legacy = json["beans.background.custom"] as? String {
            defaults.set(legacy, forKey: "beans.background.custom.light")
            defaults.set(legacy, forKey: "beans.background.custom.dark")
        }
        if json["beans.background.image.light"] == nil,
           json["beans.background.image.dark"] == nil,
           let legacy = json["beans.background.image"] as? String {
            defaults.set(legacy, forKey: "beans.background.image.light")
            defaults.set(legacy, forKey: "beans.background.image.dark")
        }
        theme.reloadBackgroundSettings()
        defaults.removeObject(forKey: "beans.wallpapers.deleted")
        // 恢复壁纸：写回 beans.wallpapers.* 后重建文件（沙盒路径变化也能恢复）
        theme.reloadWallpapersFromBackup()
        // 恢复歌词背景图片：路径变化时按备份的 base64 重建文件
        LyricBackgroundStore.restoreFromBackup()
        // 恢复字体文件
        if let fontPayload = json["beans.font.restore"] as? [String: Any],
           let name = fontPayload["name"] as? String,
           let b64 = fontPayload["data"] as? String,
           let fontData = Data(base64Encoded: b64) {
            if FontManager.restoreFont(name: name, data: fontData) {
                count += 1
            }
        }
        BeansLogger.shared.log("恢复配置备份：\(count) 项设置", level: .info)
        if count > 0 {
            BeansHaptics.success()
            backupMessage = "已恢复 \(count) 项设置，部分设置需重启应用后完全生效"
            ToastCenter.shared.show("已恢复 \(count) 项设置")
        } else {
            backupMessage = "备份中未找到可恢复的设置"
        }
    }

    private var legacyTabBarSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.beansAmber)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("低系统悬浮底栏")
                        .font(BeansFont.appFont(15))
                        .foregroundStyle(Color.beansLabel)
                    Text("仅 iOS 26 以下生效，用来模拟高系统悬浮底栏")
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(Color.beansComment)
                }
                Spacer()
                Button("默认") {
                    resetLegacyTabBar()
                    BeansHaptics.select()
                }
                .font(BeansFont.appFont(12, .semibold))
                .foregroundStyle(Color.beansAmber)
                .buttonStyle(.plain)
            }
            settingsSlider("圆润度", valueText: "\(Int(legacyTabCornerRadius))") {
                Slider(value: $legacyTabCornerRadius, in: 18...42, step: 1)
                    .tint(Color.beansAmber)
            }
            settingsSlider("长度", valueText: "\(Int(legacyTabWidth))") {
                Slider(value: $legacyTabWidth, in: 300...420, step: 1)
                    .tint(Color.beansAmber)
            }
            settingsSlider("X 位置", valueText: signedIntText(legacyTabOffsetX)) {
                Slider(value: $legacyTabOffsetX, in: -40...40, step: 1)
                    .tint(Color.beansAmber)
            }
            settingsSlider("Y 位置", valueText: signedIntText(legacyTabOffsetY)) {
                Slider(value: $legacyTabOffsetY, in: -36...36, step: 1)
                    .tint(Color.beansAmber)
            }
        }
        .padding(14)
        .background {
            BeansGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func resetLegacyTabBar() {
        legacyTabCornerRadius = 32
        legacyTabWidth = 356
        legacyTabOffsetX = 0
        legacyTabOffsetY = 0
    }

    private func signedIntText(_ value: Double) -> String {
        let intValue = Int(value.rounded())
        if intValue == 0 { return "0" }
        return intValue > 0 ? "+\(intValue)" : "\(intValue)"
    }

    private func layoutSettingSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: String
    ) -> some View {
        settingsSlider(title, valueText: String(format: format, value.wrappedValue)) {
            Slider(value: value, in: range, step: step)
                .tint(Color.beansAmber)
        }
    }

    private func settingsSlider<Content: View>(_ title: String, valueText: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(LocalizedStringKey(title))
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansLabel)
                Spacer()
                Text(valueText)
                    .font(BeansFont.appFont(12, .semibold))
                    .foregroundStyle(Color.beansAmber)
            }
            content()
                .transaction { transaction in transaction.animation = nil }
        }
    }

    /// 任意 UserDefaults 值 → JSON 可序列化（Data 转 base64、Date 转时间戳）
    private func backupJSONSafe(_ value: Any) -> Any {
        if let data = value as? Data {
            return ["__beansData__": data.base64EncodedString()]
        }
        if let date = value as? Date { return date.timeIntervalSince1970 }
        if let dict = value as? [String: Any] { return dict.mapValues { backupJSONSafe($0) } }
        if let array = value as? [Any] { return array.map { backupJSONSafe($0) } }
        if let dict = value as? [String: String] { return dict }
        if let array = value as? [String] { return array }
        return value
    }

    /// JSON 值 → UserDefaults 可存类型（只保留 plist 兼容类型）
    private func backupPlistSafe(_ value: Any) -> Any? {
        if let dict = value as? [String: Any], dict.count == 1,
           let b64 = dict["__beansData__"] as? String,
           let data = Data(base64Encoded: b64) {
            return data
        }
        if value is String || value is NSNumber { return value }
        if let array = value as? [Any] {
            let mapped = array.compactMap { backupPlistSafe($0) }
            return mapped.count == array.count ? mapped : nil
        }
        if let dict = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (k, v) in dict {
                guard let mv = backupPlistSafe(v) else { return nil }
                result[k] = mv
            }
            return result
        }
        return nil
    }

    private var settingsSupportSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                settingsSupportButton(
                    icon: checkingUpdate ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill",
                    title: checkingUpdate ? "正在检查更新…" : "检查更新",
                    tint: Color.beansAmber
                ) {
                    guard !checkingUpdate else { return }
                    checkingUpdate = true
                    Task {
                        let result = await UpdateChecker.checkNow()
                        await MainActor.run {
                            checkingUpdate = false
                            updateResult = result
                            showUpdateResult = true
                        }
                    }
                }
                Divider().overlay(Color.beansComment.opacity(0.14))
                settingsSupportButton(
                    icon: "bubble.left.and.exclamationmark.bubble.right.fill",
                    title: "问题反馈",
                    tint: Color.beansAmber
                ) {
                    showFeedback = true
                }
            }
            catalogDivider
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { disclaimerExpanded.toggle() }
                } label: {
                    HStack(spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.beansAmber)
                        Text("免责声明")
                        .font(BeansFont.appFont(14, .semibold))
                            .foregroundStyle(Color.beansLabel)
                        Spacer()
                        Image(systemName: disclaimerExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(Color.beansComment)
                    }
                }
                .buttonStyle(.plain)
                if disclaimerExpanded {
                    VStack(alignment: .leading, spacing: 9) {
                        disclaimerRow(1, "本软件仅为个人技术学习与开源展示用途，非商业软件、无任何盈利行为。")
                        disclaimerRow(2, "本软件所有音乐、歌词、图片等内容版权归原版权方所有，仅来源于公开网络接口聚合展示。")
                        disclaimerRow(3, "本软件不存储、不上传、不私自分发任何版权资源，仅提供在线试听与检索工具能力。")
                        disclaimerRow(4, "用户下载、保存、传播音频资源的一切行为由用户自行承担法律责任，与软件开发者无关。")
                        disclaimerRow(5, "若有版权侵权问题，版权方可联系开发者，我方将第一时间下架相关内容。")
                        disclaimerRow(6, "使用者默认同意本免责条款，禁止用于商业、盈利、侵权传播场景。")
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 14)
        }
    }

    private func disclaimerRow(_ index: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(index)")
                .font(BeansFont.appFont(11, .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.beansAmber, Color.beansHighlight],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            Text(text)
                .font(BeansFont.appFont(13, .semibold))
                .foregroundStyle(Color.beansAmber)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.beansAmber.opacity(0.075))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.beansAmber.opacity(0.22), lineWidth: 0.8)
                }
        )
    }

    private func settingsSupportButton(
        icon: String,
        title: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28)
                Text(title)
                    .font(BeansFont.appFont(14, .semibold))
                    .foregroundStyle(Color.beansLabel)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.beansComment.opacity(0.65))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.98))
        .disabled(checkingUpdate && title.hasPrefix("正在"))
    }

    private func normalizedFloatingImageBase64(from data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let maxDimension: CGFloat = 240
        let longestSide = max(image.size.width, image.size.height)
        let scale = longestSide > maxDimension ? maxDimension / longestSide : 1
        let size = CGSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )
        let renderer = UIGraphicsImageRenderer(size: size)
        let normalized = renderer.jpegData(withCompressionQuality: 0.82) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return normalized.base64EncodedString()
    }

    /// 壁纸格子：点击应用到所选外观；使用中的壁纸显示主题色边框+勾选；右上角删除
    private func wallpaperCell(path: String, appearance: BeansWallpaperAppearance) -> some View {
        let isActive = path == theme.backgroundImagePath(for: appearance.colorScheme)
        return ZStack(alignment: .topTrailing) {
            Button {
                BeansHaptics.tap()
                theme.applyWallpaper(at: path, for: appearance.colorScheme)
            } label: {
                Group {
                    if let img = BeansImageFileCache.image(at: path) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.beansGlassFill
                    }
                }
                .frame(height: 108)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.beansAmber)
                            .background { BeansSurface(shape: Circle()) }
                            .padding(5)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                BeansHaptics.medium()
                theme.deleteWallpaper(at: path)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.beansComment)
                    .frame(width: 28, height: 28)
                    .background { BeansSurface(shape: Circle()) }
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .padding(6)
            }
            .buttonStyle(.plain)
            .zIndex(2)
        }
    }
}

// MARK: - 均衡器

private struct SettingsCatalogGroup<Content: View>: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    private let content: Content

    private var usesCustomWallpaper: Bool {
        theme.backgroundSyncAll && theme.customBackgroundImage(for: colorScheme) != nil
    }

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
            .padding(.horizontal, 16)
            .background {
                let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
                BeansGlass(shape: shape, forceLiquid: usesCustomWallpaper)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.055), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

/// iOS 26 and later use the same plain full-screen surface as the home page.
/// Older systems retain the small compatibility header.
private struct SettingsNavigationContainer<Content: View>: View {
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 26, *) {
            content()
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain)

                    Text("设置")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.beansLabel)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(height: 52)

                content()
            }
        }
    }
}

/// 单独呈现底栏可见项编辑，避免首次打开设置时同时创建多组 Tab 状态绑定。
private struct TabVisibilitySettingsSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @State private var visibility = BeansTabVisibility.load()

    private var visibleTabCount: Int {
        RootTab.bottomTabs.filter { visibility.isVisible($0) }.count
    }

    var body: some View {
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                SettingsCatalogGroup {
                    tabToggle("主页", systemName: "house.fill", tab: .discover)
                    Divider().overlay(Color.beansComment.opacity(0.15))
                    tabToggle("精选", systemName: "dot.radiowaves.left.and.right", tab: .playlists)
                    Divider().overlay(Color.beansComment.opacity(0.15))
                    tabToggle("歌单", systemName: "music.note.list", tab: .library)
                    Divider().overlay(Color.beansComment.opacity(0.15))
                    tabToggle("我的", systemName: "person.crop.circle", tab: .profile)
                    Divider().overlay(Color.beansComment.opacity(0.15))
                    tabToggle("搜索", systemName: "magnifyingglass", tab: .search)
                }
                .padding(16)
            }
            .navigationTitle("底部栏显示")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundStyle(Color.beansAmber)
                }
            }
        }
        .modifier(BeansSheetModifier(detents: [.fraction(0.5)], dragIndicator: true))
    }

    private func tabToggle(_ title: String, systemName: String, tab: RootTab) -> some View {
        Toggle(isOn: visibilityBinding(for: tab)) {
            Label(title, systemImage: systemName)
                .font(BeansFont.appFont(15))
                .foregroundStyle(Color.beansLabel)
        }
        .toggleStyle(.switch)
        .tint(Color.beansAmber)
        .padding(.vertical, 10)
        .disabled(visibility.isVisible(tab) && visibleTabCount <= 1)
    }

    private func visibilityBinding(for tab: RootTab) -> Binding<Bool> {
        Binding(
            get: { visibility.isVisible(tab) },
            set: { isVisible in
                guard !(visibility.isVisible(tab) && !isVisible && visibleTabCount <= 1) else { return }
                visibility.setVisible(isVisible, for: tab)
                visibility.save()
            }
        )
    }
}

struct EqualizerSettingsView: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var equalizer = BeansEqualizer.shared
    @State private var newPresetName = ""
    @State private var showPresetNamePrompt = false

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { equalizer.isEnabled },
            set: { equalizer.setEnabled($0) }
        )
    }

    private func gainBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { equalizer.bandGains.indices.contains(index) ? equalizer.bandGains[index] : 0 },
            set: { equalizer.setBandGain(at: index, to: $0) }
        )
    }

    private var preampBinding: Binding<Double> {
        Binding(
            get: { equalizer.preampGain },
            set: { equalizer.setPreampGain($0) }
        )
    }

    var body: some View {
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        EqualizerResponseView(
                            gains: equalizer.bandGains,
                            preampGain: equalizer.preampGain
                        )
                        controlCard
                        presetCard
                        bandsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                    .beansAdaptiveContentWidth(compact: 680, regular: 980)
                }
                .beansScrollIndicatorsHidden()
            }
            .navigationTitle(beansLocalized("均衡器", "Equalizer"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(beansLocalized("完成", "Done")) { dismiss() }
                }
            }
            .alert(
                beansLocalized("保存自定义预设", "Save custom preset"),
                isPresented: $showPresetNamePrompt
            ) {
                TextField(
                    beansLocalized("预设名称", "Preset name"),
                    text: $newPresetName
                )
                Button(beansLocalized("保存", "Save")) {
                    if equalizer.saveCustomPreset(name: newPresetName) {
                        BeansHaptics.select()
                    }
                    newPresetName = ""
                }
                Button(beansLocalized("取消", "Cancel"), role: .cancel) {
                    newPresetName = ""
                }
            } message: {
                Text(beansLocalized("保存当前频段和前级增益，之后可以一键恢复。", "Save the current bands and preamp for one-tap recall later."))
            }
        }
    }

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: enabledBinding) {
                HStack(spacing: 11) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.beansAmber)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(beansLocalized("启用均衡器", "Enable Equalizer"))
                            .font(BeansFont.appFont(15, .semibold))
                            .foregroundStyle(Color.beansLabel)
                    }
                }
            }
            .toggleStyle(.switch)
            .tint(Color.beansAmber)

            Divider().overlay(Color.beansComment.opacity(0.14))

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(beansLocalized("前级增益", "Preamp"))
                        .font(BeansFont.appFont(13, .medium))
                        .foregroundStyle(Color.beansLabel)
                    Spacer()
                    Text(String(format: "%+.1f dB", equalizer.preampGain))
                        .font(BeansFont.appFont(12, .semibold))
                        .foregroundStyle(abs(equalizer.preampGain) > 0.01 ? Color.beansAmber : Color.beansComment)
                        .monospacedDigit()
                }
                Slider(value: preampBinding, in: -BeansEqualizer.maximumGain...BeansEqualizer.maximumGain, step: 0.5)
                    .tint(Color.beansAmber)
                    .transaction { transaction in transaction.animation = nil }
                HStack {
                    Text("-12")
                    Spacer()
                    Text(beansLocalized("不增益", "Unity"))
                    Spacer()
                    Text("+12")
                }
                .font(BeansFont.appFont(10))
                .foregroundStyle(Color.beansComment.opacity(0.75))
            }
        }
        .padding(14)
        .background { BeansGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)) }
    }

    private var presetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(beansLocalized("预设", "Preset"))
                    .font(BeansFont.appFont(14, .semibold))
                    .foregroundStyle(Color.beansLabel)
                Spacer()
                Menu {
                    ForEach(BeansEqualizerPreset.allCases.filter { $0 != .custom }) { preset in
                        Button(preset.displayName) {
                            equalizer.applyPreset(preset)
                            BeansHaptics.select()
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(equalizer.selectedCustomPresetName ?? equalizer.selectedPreset.displayName)
                            .font(BeansFont.appFont(13, .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Color.beansAmber)
                    .padding(.horizontal, 11)
                    .frame(height: 31)
                    .background { BeansSurface(shape: Capsule()) }
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(BeansEqualizerPreset.allCases.filter { $0 != .custom }) { preset in
                    let selected = equalizer.selectedPreset == preset
                    Button {
                        equalizer.applyPreset(preset)
                        BeansHaptics.select()
                    } label: {
                        Text(preset.displayName)
                            .font(BeansFont.appFont(11.5, selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.beansAmber : Color.beansLabel)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background {
                                Capsule().fill(selected ? Color.beansAmber.opacity(0.14) : Color.primary.opacity(0.035))
                            }
                            .overlay {
                                Capsule().strokeBorder(selected ? Color.beansAmber.opacity(0.42) : Color.primary.opacity(0.06), lineWidth: 0.8)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            if !equalizer.customPresets.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text(beansLocalized("我的预设", "My presets"))
                        .font(BeansFont.appFont(12, .semibold))
                        .foregroundStyle(Color.beansComment)
                    ForEach(equalizer.customPresets) { preset in
                        HStack(spacing: 8) {
                            Button {
                                equalizer.applyCustomPreset(preset)
                                BeansHaptics.select()
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: equalizer.selectedCustomPresetName == preset.name ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(equalizer.selectedCustomPresetName == preset.name ? Color.beansAmber : Color.beansComment)
                                    Text(preset.name)
                                        .font(BeansFont.appFont(12.5, .medium))
                                        .foregroundStyle(Color.beansLabel)
                                        .lineLimit(1)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            Button {
                                equalizer.deleteCustomPreset(preset)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.beansComment)
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    newPresetName = equalizer.selectedCustomPresetName ?? ""
                    showPresetNamePrompt = true
                } label: {
                    Label(beansLocalized("保存当前预设", "Save current preset"), systemImage: "square.and.arrow.down")
                        .font(BeansFont.appFont(12.5, .medium))
                        .foregroundStyle(Color.beansAmber)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background { BeansSurface(shape: RoundedRectangle(cornerRadius: 10, style: .continuous)) }
                }
                .buttonStyle(.plain)

                Button {
                    equalizer.reset()
                    BeansHaptics.select()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.beansComment)
                        .frame(width: 42, height: 34)
                        .background { BeansSurface(shape: RoundedRectangle(cornerRadius: 10, style: .continuous)) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(beansLocalized("重置调节", "Reset adjustments"))
            }
        }
        .padding(14)
        .background { BeansGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)) }
    }

    private var bandsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(beansLocalized("自定义调节", "Custom tuning"))
                        .font(BeansFont.appFont(14, .semibold))
                        .foregroundStyle(Color.beansLabel)
                    Text(beansLocalized("范围 -12 dB 至 +12 dB", "Range: -12 dB to +12 dB"))
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(Color.beansComment)
                }
                Spacer()
            }

            ForEach(Array(BeansEqualizer.bandFrequencies.enumerated()), id: \.offset) { index, frequency in
                equalizerBandRow(index: index, frequency: frequency)
                if index < BeansEqualizer.bandFrequencies.count - 1 {
                    Divider().overlay(Color.beansComment.opacity(0.14))
                }
            }
        }
        .padding(14)
        .background { BeansGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)) }
    }

    private func equalizerBandRow(index: Int, frequency: Double) -> some View {
        let gain = equalizer.bandGains.indices.contains(index) ? equalizer.bandGains[index] : 0
        return VStack(spacing: 6) {
            HStack {
                Text(frequencyLabel(frequency))
                    .font(BeansFont.appFont(13, .medium))
                    .foregroundStyle(Color.beansLabel)
                Spacer()
                Text(String(format: "%+.1f dB", gain))
                    .font(BeansFont.appFont(12, .semibold))
                    .foregroundStyle(abs(gain) > 0.01 ? Color.beansAmber : Color.beansComment)
                    .monospacedDigit()
            }
            Slider(value: gainBinding(index), in: -BeansEqualizer.maximumGain...BeansEqualizer.maximumGain, step: 0.5)
                .tint(Color.beansAmber)
                .transaction { transaction in transaction.animation = nil }
            HStack {
                Text("-12")
                Spacer()
                Text("0")
                Spacer()
                Text("+12")
            }
            .font(BeansFont.appFont(10))
            .foregroundStyle(Color.beansComment.opacity(0.75))
        }
    }

    private func frequencyLabel(_ frequency: Double) -> String {
        if frequency >= 1_000 {
            let value = frequency / 1_000
            return value.rounded() == value ? "\(Int(value)) kHz" : String(format: "%.1f kHz", value)
        }
        return "\(Int(frequency)) Hz"
    }
}

private struct EqualizerResponseView: View {
    let gains: [Double]
    let preampGain: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(beansLocalized("频响预览", "Response preview"))
                        .font(BeansFont.appFont(14, .semibold))
                        .foregroundStyle(Color.beansLabel)
                    Text(beansLocalized("拖动下方频段，实时塑造声音", "Shape the sound in real time by tuning each band below"))
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(Color.beansComment)
                }
                Spacer()
                Image(systemName: "waveform.path")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.beansAmber)
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let values = responseValues
                ZStack {
                    VStack(spacing: 0) {
                        ForEach(0..<5, id: \.self) { _ in
                            Divider().overlay(Color.beansComment.opacity(0.12))
                            Spacer()
                        }
                    }
                    Path { path in
                        guard let first = values.first else { return }
                        path.move(to: CGPoint(x: 0, y: yPosition(first, height: height)))
                        for index in values.indices.dropFirst() {
                            let x = width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                            path.addLine(to: CGPoint(x: x, y: yPosition(values[index], height: height)))
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [Color.beansAmber.opacity(0.65), Color.beansAmber, Color.beansHighlight],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                    )
                    Path { path in
                        guard let first = values.first else { return }
                        path.move(to: CGPoint(x: 0, y: height))
                        path.addLine(to: CGPoint(x: 0, y: yPosition(first, height: height)))
                        for index in values.indices.dropFirst() {
                            let x = width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                            path.addLine(to: CGPoint(x: x, y: yPosition(values[index], height: height)))
                        }
                        path.addLine(to: CGPoint(x: width, y: height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Color.beansAmber.opacity(0.22), Color.beansAmber.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .frame(height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.7)
            }

            HStack {
                Text("31 Hz")
                Spacer()
                Text("1 kHz")
                Spacer()
                Text("16 kHz")
            }
            .font(BeansFont.appFont(10))
            .foregroundStyle(Color.beansComment)
        }
        .padding(14)
        .background { BeansGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)) }
    }

    private var responseValues: [Double] {
        guard !gains.isEmpty else { return [preampGain] }
        return gains.map { min(max($0 + preampGain * 0.35, -12), 12) }
    }

    private func yPosition(_ value: Double, height: CGFloat) -> CGFloat {
        let normalized = (value + 12) / 24
        return height * CGFloat(1 - normalized)
    }
}

// MARK: - 壁纸照片选择器（PHPicker 封装：iOS 14+ 兼容，支持多选图片）

struct WallpaperPhotoPicker: UIViewControllerRepresentable {
    var allowsMultiple = true
    let onPicked: (Data) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = allowsMultiple ? 0 : 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: WallpaperPhotoPicker
        init(_ parent: WallpaperPhotoPicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            for result in results {
                let provider = result.itemProvider
                if provider.canLoadObject(ofClass: UIImage.self) {
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                        guard let data, !data.isEmpty else { return }
                        DispatchQueue.main.async {
                            self.parent.onPicked(data)
                        }
                    }
                }
            }
        }
    }
}

/// 赞助排行前三名的动态边框高光，不参与交互，也不影响列表布局。
private struct SponsorRankHighlight: View {
    let color: Color
    let rank: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            GeometryReader { proxy in
                let phase = proxy.size.width > 1
                    ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.8) / 2.8
                    : 0
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                color.opacity(0.05),
                                color.opacity(0.86),
                                Color.white.opacity(rank == 0 ? 0.88 : 0.56),
                                color.opacity(0.05)
                            ],
                            center: .center,
                            angle: .degrees(phase * 360 + Double(rank * 80))
                        ),
                        lineWidth: rank == 0 ? 1.7 : 1.25
                    )
                    .shadow(color: color.opacity(rank == 0 ? 0.42 : 0.28), radius: rank == 0 ? 10 : 7)
            }
        }
        .allowsHitTesting(false)
    }
}

/// 赞助排行展开后的低对比动态光效，不参与交互，也不影响列表布局。
private struct SponsorRankAtmosphere: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                guard size.width > 1, size.height > 1 else { return }
                let time = timeline.date.timeIntervalSinceReferenceDate
                let drift = CGFloat(sin(time * 0.18)) * size.width * 0.12
                let warm = Color(red: 1.0, green: 0.62, blue: 0.20)
                let cool = colorScheme == .dark ? Color.white : Color(red: 0.18, green: 0.34, blue: 0.56)

                context.fill(
                    Path(ellipseIn: CGRect(
                        x: size.width * 0.04 + drift,
                        y: -size.height * 0.12,
                        width: size.width * 0.72,
                        height: size.height * 0.62
                    )),
                    with: .radialGradient(
                        Gradient(colors: [warm.opacity(0.13), .clear]),
                        center: CGPoint(x: size.width * 0.35 + drift, y: size.height * 0.14),
                        startRadius: 2,
                        endRadius: size.width * 0.48
                    )
                )

                let counterDrift = CGFloat(cos(time * 0.15)) * size.width * 0.1
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: size.width * 0.48 + counterDrift,
                        y: size.height * 0.46,
                        width: size.width * 0.62,
                        height: size.height * 0.48
                    )),
                    with: .radialGradient(
                        Gradient(colors: [cool.opacity(0.09), .clear]),
                        center: CGPoint(x: size.width * 0.70 + counterDrift, y: size.height * 0.68),
                        startRadius: 2,
                        endRadius: size.width * 0.42
                    )
                )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 字体文件选择器（UIDocumentPicker 包装，比 SwiftUI fileImporter 稳定：所有文件可选，系统 asCopy 复制到沙盒）

struct FontDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: FontDocumentPicker
        init(_ parent: FontDocumentPicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
// MARK: - 配置备份文档（SwiftUI 原生 fileExporter 导出，稳定可靠）

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
// MARK: - 配置备份文件选择器（UIDocumentPicker 封装：比 SwiftUI fileImporter 稳定，所有文件可选）

struct BackupDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .plainText, .item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: BackupDocumentPicker
        init(_ parent: BackupDocumentPicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
