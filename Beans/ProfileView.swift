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
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerManager
    @AppStorage("beans.themeMode") private var themeModeRaw = BeansThemeMode.system.rawValue
    @AppStorage("beans.homeHeaderHideSort") private var homeHeaderHideSort = false
    @AppStorage("beans.pauseHomeRendering") private var homeRenderingPaused = false

    @State private var showHistory = false

    /// 统一账号登录面板（网易云 + QQ 音乐整合）
    @State private var showAccountHub = false
    /// 设置页（外观 + 歌词翻译等）
    @State private var showSettings = false
    @State private var showSectionSort = false
    /// 我的界面板块顺序（账号 / 关于，可自定义）
    @State private var profileOrder = SectionOrderStore.load(SectionOrderStore.profileKey, defaults: SectionOrderStore.profileDefaults)
    /// 软件使用说明
    @State private var showUsageGuide = false
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
    @ObservedObject private var qqAuth = QQMusicAuth.shared
    @ObservedObject private var kugouAuth = KugouMusicAuth.shared
    @ObservedObject private var platformPrefs = PlatformPreferenceStore.shared

    private var themeMode: BeansThemeMode {
        BeansThemeMode(rawValue: themeModeRaw) ?? .system
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
            parts.append(qqAuth.nickname.isEmpty ? "QQ 已登录" : qqAuth.nickname)
        }
        if platformPrefs.isEnabled(SearchProvider.kugou), kugouAuth.isLoggedIn {
            parts.append(kugouAuth.nickname.isEmpty ? "酷狗已登录" : kugouAuth.nickname)
        }
        if parts.isEmpty { return "登录后可同步 \(platformPrefs.summaryText) 歌单" }
        return parts.joined(separator: " · ")
    }

    private var hasVisibleAccountLogin: Bool {
        (platformPrefs.isEnabled(SearchProvider.netease) && auth.isLoggedIn)
            || (platformPrefs.isEnabled(SearchProvider.qq) && qqAuth.isLoggedIn)
            || (platformPrefs.isEnabled(SearchProvider.kugou) && kugouAuth.isLoggedIn)
    }

    /// 顶部标题 + 右上角设置齿轮
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("我的")
                    .font(BeansFont.appFont(30, .bold))
                    .foregroundStyle(Color.beansLabel)
                Text("\(platformPrefs.summaryText) 账号与外观设置")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansComment)
            }
            Spacer()
            HStack(spacing: 10) {
                if !homeHeaderHideSort {
                    GlassIconButton(systemName: "arrow.up.arrow.down") {
                        BeansHaptics.tap()
                        showSectionSort = true
                    }
                }
                GlassIconButton(systemName: "gearshape.fill") {
                    BeansHaptics.tap()
                    homeRenderingPaused = true
                    showSettings = true
                }
            }
        }
        .padding(.top, 8)
    }

    var body: some View {
        let _ = theme.accent
        ZStack {
            // 页面背景：同步开启时显示壁纸/背景色，否则默认氛围渐变
            GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
            // 实例级 UITabBar 清透风格（固定全透明，无需调节）
            TabBarAppearanceConfigurator()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    // 板块按用户自定义顺序渲染（可拖拽排序）
                    ForEach(profileOrder, id: \.self) { key in
                        switch key {
                        case "账号":
                            userCard
                        case "关于":
                            aboutSection
                        default:
                            EmptyView()
                        }
                    }
                    // 更新入口固定放在“我的”页面最底部，避免被板块排序隐藏。
                    updateLinkCard
                    communityCard
                    donationCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 190)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
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
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .environmentObject(player)
                .environmentObject(auth)
                .environmentObject(theme)
        }
        .sheet(isPresented: $showAccountHub) {
            AccountHubSheet()
                .environmentObject(auth)
                .environmentObject(theme)
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(theme)
                .environmentObject(player)
                .ignoresSafeArea(.all)
        }
        .sheet(isPresented: $showSectionSort) {
            SectionOrderSheet(
                title: "我的板块排序",
                sections: SectionOrderStore.profileDefaults,
                order: $profileOrder,
                platformOrder: Binding(
                    get: { platformPrefs.orderedRaw },
                    set: { platformPrefs.orderedRaw = $0 }
                )
            )
                .onDisappear { SectionOrderStore.save(SectionOrderStore.profileKey, profileOrder) }
        }
        .sheet(isPresented: $showUsageGuide) {
            UsageGuideSheet()
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
                Text("检查失败，请检查网络后重试\n如果长时间无反应，可能需要特殊网络环境（代理 / VPN）才能访问 GitHub")
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
                Text("下载失败：\(message)\n如果长时间无反应，可能需要特殊网络环境（代理 / VPN）才能访问 GitHub")
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
                Text("下载完成后将自动打开系统分享面板")
                    .font(BeansFont.appFont(11))
                    .foregroundStyle(Color.beansComment.opacity(0.8))
                    .multilineTextAlignment(.center)
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

    private var userCard: some View {
        VStack(spacing: 16) {
            Button {
                BeansHaptics.tap()
                // 统一账号面板：网易云 + QQ 音乐登录整合在一起
                showAccountHub = true
            } label: {
                HStack(spacing: 14) {
                    // 头像：主题渐变描边环
                    AsyncImage(url: auth.user?.avatarURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(Color.beansComment)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    .background(Color.beansGlassFill, in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(auth.user?.nickname ?? (auth.isLoggedIn ? "网易云音乐已登录" : "免登录 · 点击登录"))
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
            if let badge {
                VIPBadgeView(text: badge)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
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
                            .background(Circle().fill(.ultraThinMaterial))
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
                    .background(Circle().fill(.ultraThinMaterial))
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
                featureCell(icon: "clock.arrow.circlepath", title: "播放历史", subtitle: "最近播放 \(player.history.count) 首") {
                    showHistory = true
                }
                featureCell(icon: hasVisibleAccountLogin ? "checkmark.seal.fill" : "globe", title: "账号与登录", subtitle: hasVisibleAccountLogin ? accountStatusLine : "登录 \(platformPrefs.summaryText)") {
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
                    Text(title)
                        .font(BeansFont.appFont(14, .semibold))
                        .foregroundStyle(Color.beansLabel)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(Color.beansComment)
                        .lineLimit(1)
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


    /// 软件使用说明入口
    private var usageGuideCard: some View {
        Button {
            BeansHaptics.tap()
            showUsageGuide = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.beansAmber)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("软件使用说明")
                        .font(BeansFont.appFont(15, .semibold))
                        .foregroundStyle(Color.beansLabel)
                    Text("了解多平台切换、账号、播放与个性化玩法")
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(Color.beansComment)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.beansComment.opacity(0.6))
            }
            .padding(16)
            .background {
                                BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .beansCardShadow(radius: 9, y: 3)
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "关于")
            VStack(spacing: 8) {
                Label(appVersionText, systemImage: "beats.headphones")
                    .font(BeansFont.appFont(14, .semibold))
                    .foregroundStyle(Color.beansLabel)
                Text("网易云 / QQ音乐 / 酷狗音乐 第三方客户端 · 仅供学习研究")
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansComment)
                    .multilineTextAlignment(.center)
                Text("只用作个人学习研究，禁止用于商业及非法用途，如产生法律纠纷与本人无关")
                    .font(BeansFont.appFont(11))
                    .foregroundStyle(Color.beansComment.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("本软件完全免费，全部功能开源 · GitHub：XIaodou0416/Beans-Music")
                    .font(BeansFont.appFont(11, .semibold))
                    .foregroundStyle(Color.beansAmber)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background {
                                BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .beansCardShadow(radius: 9, y: 3)

            copyrightDisclosure

        }
    }

    /// 版权声明（默认折叠，可展开查看）
    private var copyrightDisclosure: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text("“QQ”、“QQ音乐”及企鹅形象等文字、图形和商业标识，其著作权或商标权归腾讯公司所有。QQ音乐享有对其平台授权音乐的版权，请勿随意下载、复制版权内容。具体内容请参考QQ音乐用户协议。")
                Text("“网易云”、“网易云音乐”等文字、图形和商业标识，其著作权或商标权归网易所有。网易云音乐享有对其平台授权音乐的版权，请勿随意下载、复制版权内容。具体内容请参考网易云音乐用户协议。")
                Text("“酷狗音乐”及其名称、图形和商业标识归酷狗音乐及相关权利方所有。酷狗音乐享有对其平台授权音乐的版权，请勿随意下载、复制版权内容。具体内容请参考酷狗音乐用户协议。")
                Text("音乐 API 来自 GitHub 开源项目，非官方版 API；本软件不提供任何音频存储服务，如需下载音频，请支持正版！")
            }
            .font(BeansFont.appFont(11))
            .foregroundStyle(Color.beansComment)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.beansAmber)
                    .frame(width: 26)
                Text("版权声明")
                    .font(BeansFont.appFont(14, .semibold))
                    .foregroundStyle(Color.beansLabel)
                Spacer()
            }
            .padding(.vertical, 2)
        }
        .tint(Color.beansAmber)
        .padding(16)
        .background {
                            BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .beansCardShadow(radius: 9, y: 3)
    }

    /// 自动下载新版 IPA（带进度浮层）
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

    /// 更新地址 + 检查更新（GitHub 项目，可点击交互）
    private var updateLinkCard: some View {
        VStack(spacing: 0) {
            Button {
                BeansHaptics.tap()
                if let url = URL(string: "https://github.com/XIaodou0416/Beans-Music") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.beansHighlight)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("更新地址")
                            .font(BeansFont.appFont(14, .semibold))
                            .foregroundStyle(Color.beansLabel)
                        Text("GitHub：XIaodou0416/Beans-Music")
                            .font(BeansFont.appFont(11))
                            .foregroundStyle(Color.beansComment)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.beansComment)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            Divider()
                .overlay(Color.beansComment.opacity(0.16))
                .padding(.horizontal, 16)

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
                            // 发现新版：自动下载 IPA（无安装包时回退到更新提示）
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
                        Text("检测 GitHub 最新版本")
                            .font(BeansFont.appFont(11))
                            .foregroundStyle(Color.beansComment)
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
                    Text("点击跳转 Telegram")
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(Color.beansComment)
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

    /// 我的页底部赞助入口与赞助排行榜
    private var donationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    donationExpanded.toggle()
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
                        Text(donationExpanded ? "点击收起赞助信息" : "点击展开赞助信息")
                            .font(BeansFont.appFont(11))
                            .foregroundStyle(Color.beansComment)
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
                .frame(maxWidth: 300)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.beansComment.opacity(0.14), lineWidth: 0.8)
                }

                Text("虽然没有服务器运营成本，但是软件本身使用AI构建，需要消耗大量token，音源接口也由本人购买，本身就会有些压力，因为软件本身公益所以自愿赞助，感谢各位的喜欢")
                .font(BeansFont.appFont(13))
                .foregroundStyle(Color.beansLabel)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("赞助人员")
                        .font(BeansFont.appFont(15, .semibold))
                        .foregroundStyle(Color.beansLabel)
                    Spacer()
                    Text("按金额排序")
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(Color.beansComment)
                }

                ForEach(Self.donors.indices, id: \.self) { index in
                    let donor = Self.donors[index]
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(BeansFont.appFont(13, .bold))
                            .foregroundStyle(index == 0 ? Color.beansAmber : Color.beansComment)
                            .frame(width: 24, height: 24)
                            .background(
                                (index == 0 ? Color.beansAmber : Color.beansComment).opacity(index == 0 ? 0.16 : 0.08),
                                in: Circle()
                            )
                        Text(donor.name)
                            .font(BeansFont.appFont(13, .medium))
                            .foregroundStyle(Color.beansLabel)
                        Spacer()
                        Text(String(format: "¥ %.2f", donor.amount))
                            .font(BeansFont.appFont(13, .semibold))
                            .foregroundStyle(index == 0 ? Color.beansAmber : Color.beansLabel)
                    }
                    if index < Self.donors.count - 1 {
                        Divider().overlay(Color.beansComment.opacity(0.12))
                    }
                }
                }
            }
        }
        .padding(16)
        .background {
            BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .beansCardShadow(radius: 9, y: 3)
    }

    private struct Donor {
        let name: String
        let amount: Double
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
    @Environment(\.dismiss) private var dismiss

    @State private var showNeteaseLogin = false
    @State private var showQQLogin = false
    @State private var showKugouLogin = false
    @State private var confirmNeteaseLogout = false
    @State private var confirmQQLogout = false
    @State private var confirmKugouLogout = false

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
                        Text("\(platformPrefs.summaryText) 登录后可同步歌单并提升可播成功率")
                            .font(BeansFont.appFont(11))
                            .foregroundStyle(Color.beansComment)
                            .padding(.horizontal, 4)
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
                        Text(auth.isLoggedIn ? (auth.user?.nickname ?? "已登录") : "未登录 · 扫码登录同步歌单")
                            .font(BeansFont.appFont(12))
                            .foregroundStyle(Color.beansComment)
                            .lineLimit(1)
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
                    .background(.ultraThinMaterial, in: Capsule())
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
                        Text(qqAuth.isLoggedIn ? (qqAuth.nickname.isEmpty ? "已登录" : qqAuth.nickname) : "未登录 · 网页 / 扫码 / Cookie 登录")
                            .font(BeansFont.appFont(12))
                            .foregroundStyle(Color.beansComment)
                            .lineLimit(1)
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
                    .background(.ultraThinMaterial, in: Capsule())
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
                        Text(kugouAuth.isLoggedIn ? (kugouAuth.nickname.isEmpty ? "已登录" : kugouAuth.nickname) : "未登录 · App 扫码同步歌单")
                            .font(BeansFont.appFont(12))
                            .foregroundStyle(Color.beansComment)
                            .lineLimit(1)
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
                    .background(.ultraThinMaterial, in: Capsule())
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
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("beans.themeMode") private var themeModeRaw = BeansThemeMode.system.rawValue
    /// 音质等级（借鉴 Kumone）
    @AppStorage("beans.audioQuality") private var audioQualityRaw = BeansAudioQuality.exhigh.rawValue
    /// 底栏是否显示文字（关闭后只显示图标）
    @AppStorage("beans.tabLabelsVisible") private var tabLabelsVisible = true
    @AppStorage("beans.legacyTabCornerRadius") private var legacyTabCornerRadius = 32.0
    @AppStorage("beans.legacyTabWidth") private var legacyTabWidth = 356.0
    @AppStorage("beans.legacyTabOffsetX") private var legacyTabOffsetX = 0.0
    @AppStorage("beans.legacyTabOffsetY") private var legacyTabOffsetY = 0.0
    /// 官方地址不可用时，是否尝试内置音源
    @AppStorage("beans.enableUnblock") private var enableBuiltInSources = true
    /// 第三方音源播放会员歌成功时提醒，默认开启
    @AppStorage("beans.showThirdPartyVIPNotice") private var showThirdPartyVIPNotice = true
    /// 可选高刷新率动效，默认开启；可手动关闭以降低发热
    @AppStorage("beans.enableHighRefresh") private var enableHighRefresh = true
    @AppStorage("beans.audio.mixothers.v1") private var mixesWithOthers = false
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
    @ObservedObject private var sourceStore = UnblockSourceStore.shared
    @ObservedObject private var platformPrefs = PlatformPreferenceStore.shared

    @State private var appearanceExpanded = false
    @State private var platformExpanded = false
    @State private var playbackExpanded = false
    @State private var showWallpaperPicker = false
    @State private var showFontImporter = false
    @State private var showGreetingFontImporter = false
    /// 更新日志
    @State private var showChangelog = false
    /// 配置备份与恢复
    @State private var backupDoc: BackupDocument?
    @State private var showExportBackup = false
    @State private var showRestorePicker = false
    @State private var pendingRestore: [String: Any]?
    @State private var showRestoreConfirm = false
    @State private var showResetSettingsConfirm = false
    @State private var backupIncludeAccounts = false
    @State private var backupIncludeWallpapers = true
    @State private var backupMessage: String?
    /// 日志
    @State private var showLogViewer = false
    @State private var showUsageGuide = false

    private var themeMode: BeansThemeMode {
        BeansThemeMode(rawValue: themeModeRaw) ?? .system
    }

    private var presetSourceCount: Int {
        sourceStore.presetSources.count
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
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        appearanceSection
                        platformSection
                        playbackSection
                        changelogSection
                        backupSection
                        logSection
                        settingsUsageGuideSection
                        footerNote
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                    .frame(maxWidth: 860)
                    .frame(maxWidth: .infinity)
                }
                .beansScrollIndicatorsHidden()
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showWallpaperPicker) {
            WallpaperPhotoPicker { data in
                theme.addWallpaper(data)
                BeansHaptics.success()
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
        .sheet(isPresented: $showUsageGuide) {
            UsageGuideSheet()
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
        .sheet(isPresented: $showLogViewer) {
            LogViewerSheet(importedText: nil)
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
        .confirmationDialog("重置所有设置？", isPresented: $showResetSettingsConfirm, titleVisibility: .visible) {
            Button("重置设置", role: .destructive) {
                resetAllSettingsKeepingAccounts()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会恢复主题、播放器、平台显示、壁纸、布局等设置，但保留已登录账号。")
        }
        .onAppear {
            homeRenderingPaused = true
        }
        .onDisappear {
            homeRenderingPaused = false
        }
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
                        Text(platformPrefs.summaryText)
                            .font(BeansFont.appFont(11))
                            .foregroundStyle(Color.beansComment)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: platformExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.beansComment.opacity(0.6))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background {
                    BeansGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle(scale: 0.98))

            if platformExpanded {
                PlatformPreferencePicker()
                    .padding(14)
                    .background {
                        BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// 外观设置（原「我的」页外观折叠内容）
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "外观")
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
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background {
                                        BeansGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle(scale: 0.98))

            if appearanceExpanded {
            VStack(alignment: .leading, spacing: 14) {
                Picker("主题模式", selection: $themeModeRaw) {
                    ForEach(BeansThemeMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

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
                            Text("关闭后底栏只保留图标，界面更简洁")
                                .font(BeansFont.appFont(11))
                                .foregroundStyle(Color.beansComment)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.beansAmber)

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
                            Text(style.title).tag(style)
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
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(theme.customAccentHex == nil ? "使用预设主题" : "已自定义")
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                }

                    Divider().overlay(Color.beansComment.opacity(0.15))

                    HStack {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        Text("主页背景色")
                            .font(BeansFont.appFont(15))
                            .foregroundStyle(Color.beansLabel)
                        Spacer()
                        ColorPicker("", selection: Binding(
                            get: { theme.customBackground ?? Color.beansBackground },
                            set: { theme.setBackground($0.hexString) }
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
                                wallpaperCell(path: path)
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
                        if theme.customBackgroundImage != nil {
                            Button {
                                theme.clearBackgroundImage()
                                BeansHaptics.select()
                            } label: {
                                Text("清除当前背景")
                                    .font(BeansFont.appFont(13, .medium))
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                        Text(theme.customBackgroundImage == nil ? "当前：默认背景" : "当前：已应用壁纸")
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
                        Text("同步到搜索 / 音乐库 / 我的")
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
                            .background(.ultraThinMaterial, in: Capsule())
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
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("全 App 说明文字颜色")
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
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("全 App 主文字颜色")
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                }

                Divider().overlay(Color.beansComment.opacity(0.15))

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
                    TextEditor(text: $homeGreetingText)
                        .font(BeansFont.appFont(15))
                        .frame(minHeight: 88, maxHeight: 180)
                        .padding(6)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            if homeGreetingText.isEmpty {
                                Text("留空自动显示早上好/下午好/晚上好")
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
                            Text(homeGreetingFontName.isEmpty ? "跟随全局" : "已设置")
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
                                    Text("第\(index + 1)行")
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
                    Toggle("隐藏主页用户名", isOn: $homeHideUsername)
                        .font(BeansFont.appFont(13))
                    Toggle("隐藏所有界面排序按钮", isOn: $homeHeaderHideSort)
                        .font(BeansFont.appFont(13))
                    Toggle("隐藏主页刷新按钮", isOn: $homeHeaderHideRefresh)
                        .font(BeansFont.appFont(13))
                }

                Divider().overlay(Color.beansComment.opacity(0.15))

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
                            .background(.ultraThinMaterial, in: Capsule())
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
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                Text("支持 ttf / otf 字体，上传后全局生效（含歌词），重启保留")
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansComment)

            }
            .padding(16)
            .background {
                        BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
            .beansCardShadow(radius: 9, y: 3)
            }
        }
    }

    /// 播放与歌词设置（借鉴 Kumone：音质 / 免费听歌 / 显示歌词翻译）
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
                        Text("\(BeansAudioQuality(rawValue: audioQualityRaw)?.displayName ?? "高品质") · \(enableBuiltInSources ? "内置音源已开" : "内置音源已关")")
                            .font(BeansFont.appFont(11))
                            .foregroundStyle(Color.beansComment)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: playbackExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.beansComment.opacity(0.6))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background {
                    BeansGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle(scale: 0.98))

            if playbackExpanded {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        Text("音质")
                            .font(BeansFont.appFont(15))
                            .foregroundStyle(Color.beansLabel)
                    }
                    Picker("音质", selection: $audioQualityRaw) {
                        ForEach(BeansAudioQuality.allCases) { q in
                            Text(q.displayName).tag(q.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("无损与 Hi-Res 需要黑胶 VIP，未开通时自动回落到可用音质")
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(Color.beansComment)
                }

                Divider().overlay(Color.beansComment.opacity(0.15))

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
                            Text("默认关闭以显示锁屏/灵动岛；开启后可与其他 App 声音同时播放")
                                .font(BeansFont.appFont(11))
                                .foregroundStyle(Color.beansComment)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.beansAmber)
                .onChange(of: mixesWithOthers) { value in
                    PlayerManager.applyAudioMixPreference(value)
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
                        Text("已强制开启；用于修复我的、设置和播放器页面最高只有 60Hz 的问题")
                            .font(BeansFont.appFont(11))
                            .foregroundStyle(Color.beansComment)
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

                Toggle(isOn: $enableBuiltInSources) {
                    HStack(spacing: 12) {
                        Image(systemName: "externaldrive.connected.to.line.below")
                            .font(.system(size: 14))
                        .foregroundStyle(Color.beansAmber)
                        .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("使用内置音源")
                                .font(BeansFont.appFont(15))
                                .foregroundStyle(Color.beansLabel)
                            Text("仅在官方地址不可用或为试听片段时回退到预设")
                                .font(BeansFont.appFont(11))
                                .foregroundStyle(Color.beansComment)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.beansAmber)

                Toggle(isOn: $showThirdPartyVIPNotice) {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("第三方播放会员歌提醒")
                                .font(BeansFont.appFont(15))
                                .foregroundStyle(Color.beansLabel)
                            Text("未识别到对应会员且会员歌曲通过内置音源播放成功时提示")
                                .font(BeansFont.appFont(11))
                                .foregroundStyle(Color.beansComment)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.beansAmber)

                HStack(spacing: 10) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.beansAmber)
                    Text("内置音源预设")
                        .font(BeansFont.appFont(13, .semibold))
                        .foregroundStyle(Color.beansLabel)
                    Spacer()
                    Text("\(presetSourceCount) 个")
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                }

                ForEach(sourceStore.presetSources) { source in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.name)
                                .font(BeansFont.appFont(13, .medium))
                                .foregroundStyle(Color.beansLabel)
                                .lineLimit(1)
                            Text("内置预设 · \(source.kind.replacingOccurrences(of: "paid-", with: "").uppercased())")
                                .font(BeansFont.appFont(10))
                                .foregroundStyle(Color.beansComment)
                        }
                        Spacer()
                        Toggle("", isOn: sourceEnabledBinding(source.id))
                            .labelsHidden()
                            .tint(Color.beansAmber)
                    }
                }

            }
            .padding(16)
            .background {
                                BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .beansCardShadow(radius: 9, y: 3)
            .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func sourceEnabledBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { sourceStore.presetSources.first(where: { $0.id == id })?.enabled ?? false },
            set: { value in
                guard let index = sourceStore.presetSources.firstIndex(where: { $0.id == id }) else { return }
                sourceStore.presetSources[index].enabled = value
            }
        )
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
                .padding(16)
                .background {
                                    BeansGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .buttonStyle(.plain)
            .beansCardShadow(radius: 8, y: 3)
        }
    }

    /// 软件使用说明入口（放在设置页底部）
    private var settingsUsageGuideSection: some View {
        Button {
            BeansHaptics.tap()
            showUsageGuide = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.beansAmber)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("软件使用说明")
                        .font(BeansFont.appFont(15))
                        .foregroundStyle(Color.beansLabel)
                    Text("多平台切换、账号、播放与个性化说明")
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(Color.beansComment)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.beansComment.opacity(0.6))
            }
            .padding(16)
            .background {
                BeansGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .beansCardShadow(radius: 8, y: 3)
    }

    /// 配置备份与恢复：导出全部 beans.* 设置为 JSON 分享；导入后写回 UserDefaults
    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "备份与恢复")
            VStack(spacing: 10) {
                Toggle("备份登录信息", isOn: $backupIncludeAccounts)
                    .tint(Color.beansAmber)
                    .font(BeansFont.appFont(13))
                Divider().opacity(0.35)
                Toggle("备份壁纸图片", isOn: $backupIncludeWallpapers)
                    .tint(Color.beansAmber)
                    .font(BeansFont.appFont(13))
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
            backupActionButton(icon: "arrow.counterclockwise.circle", title: "重置所有设置（保留登录）") {
                BeansHaptics.tap()
                showResetSettingsConfirm = true
            }
            if let backupMessage {
                Text(backupMessage)
                    .font(BeansFont.appFont(11))
                    .foregroundStyle(Color.beansComment)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func backupActionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
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
            || key == "beans.launchInProgress"
            || key == "beans.wallpapers.deleted"
    }

    private static func isWallpaperBackupKey(_ key: String) -> Bool {
        key == "beans.background.image"
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

    private func settingsSlider<Content: View>(_ title: String, valueText: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title)
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansLabel)
                Spacer()
                Text(valueText)
                    .font(BeansFont.appFont(12, .semibold))
                    .foregroundStyle(Color.beansAmber)
            }
            content()
        }
    }

    private func resetAllSettingsKeepingAccounts() {
        let defaults = UserDefaults.standard
        var removed = 0
        for key in defaults.dictionaryRepresentation().keys {
            guard Self.isBackupCandidateKey(key) else { continue }
            guard !Self.isAccountBackupKey(key) else { continue }
            guard !Self.isSystemBackupKey(key) else { continue }
            guard key != "beans.disclaimerAccepted" else { continue }
            defaults.removeObject(forKey: key)
            removed += 1
        }
        theme.set(.amber)
        theme.clearCustomAccent()
        theme.setBackground("")
        theme.setBackgroundSyncAll(true)
        theme.clearAllWallpapers()
        theme.setUIStyle(.liquid)
        LyricBackgroundStore.clear()
        PlatformPreferenceStore.shared.resetToDefault()
        BeansHaptics.success()
        backupMessage = "已重置 \(removed) 项设置，登录信息已保留"
        ToastCenter.shared.show("设置已重置")
        BeansLogger.shared.log("重置所有设置：移除 \(removed) 项，保留登录信息", level: .info)
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

    /// 日志：查看 / 清空（导出入口放在日志查看器右上角）
    private var logSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "日志")
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    logActionButton(icon: "doc.text.magnifyingglass", title: "查看日志") {
                        showLogViewer = true
                    }
                    logActionButton(icon: "trash", title: "清空日志") {
                        BeansLogger.shared.clear()
                        ToastCenter.shared.show("日志已清空")
                    }
                }
                Text("日志记录搜索、播放、登录、备份等关键事件；遇到问题可在查看日志里导出，方便快速定位 Bug")
                    .font(BeansFont.appFont(11))
                    .foregroundStyle(Color.beansComment)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background {
                BeansGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private func logActionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(BeansFont.appFont(13, .semibold))
            .foregroundStyle(Color.beansLabel)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background {
                BeansGlass(shape: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.95))
    }

    private var footerNote: some View {
        VStack(spacing: 6) {
            Text("Beans Music · 仅供学习交流，纯 AI 实现此应用")
                .font(BeansFont.appFont(11))
                .foregroundStyle(Color.beansComment.opacity(0.7))
            Text("接入网易云音乐、QQ 音乐等公开接口")
                .font(BeansFont.appFont(11))
                .foregroundStyle(Color.beansComment.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
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
                            .background(Circle().fill(.ultraThinMaterial))
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
                    .background(Circle().fill(.ultraThinMaterial))
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .padding(6)
            }
            .buttonStyle(.plain)
            .zIndex(2)
        }
    }
}

// MARK: - 壁纸照片选择器（PHPicker 封装：iOS 14+ 兼容，支持多选图片）

struct WallpaperPhotoPicker: UIViewControllerRepresentable {
    let onPicked: (Data) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 0 // 0 = 多选
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
