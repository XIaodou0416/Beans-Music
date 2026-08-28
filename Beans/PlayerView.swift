import SwiftUI
import UIKit

// MARK: - 全屏播放器（全新重写：极简稳定布局）
// 布局原则：
// - 布局全部使用 SwiftUI 自动布局（VStack/HStack/ZStack），任何屏幕与加载时序下都稳定；
//   封面⇄歌词切换动画使用 matchedGeometryEffect 共享元素（封面从居中飞到左上角），仅作用于过渡动画，不影响布局约束。
// - 专辑模式与歌词模式是两个独立视图，if/else + transition 切换，各自内部自然居中，任何屏幕与加载时序下都稳定。
// - 封面使用固定尺寸 CoverImage（AsyncImage 仅在 overlay 中渲染），封面加载、切歌都不会影响布局。
// - 底部控制栏为普通材质圆角面板，按钮等宽对称分布，无液态玻璃依赖。
// 音频播放 / 网络 / 登录业务逻辑保持不变。

struct PlayerView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var clock: PlaybackClock
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var favorites: FavoritesStore
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool

    @State private var lyrics: [LyricLine] = []
    @State private var showLyrics = false
    @State private var showQueue = false
    @State private var showSleepTimer = false
    @State private var showAddToPlaylist = false
    @State private var showComments = false
    @State private var showDownloadPicker = false
    @State private var showShare = false
    @State private var showMoreActions = false
    /// 下载完成后直接弹原生分享（用户自行选择保存或转发）
    @State private var shareFile: ShareFileItem?
    @State private var sharedFileURL: URL?
    @State private var showAddToLocalPlaylist = false
    @State private var showPlayerSettings = false
    @State private var showArtistHome = false
    @State private var pickedArtistName = ""
    @State private var showArtistPicker = false
    @AppStorage("beans.djVisual") private var djVisualEnabled = false
    @AppStorage("beans.djVisualIntensity") private var djVisualIntensity = 0.8
    @State private var dominantColor: RGBColor?
    @Namespace private var coverNS
    @AppStorage("beans.lyricFontSize") private var lyricFontSize = 17
    @AppStorage("beans.lyricColor") private var lyricColorRaw = "accent"
    @AppStorage("beans.lyricDimColor") private var lyricDimColorRaw = "dim"
    @AppStorage("beans.lyricGlow") private var lyricGlowLevel = 1
    @AppStorage("beans.lyricGradStart") private var lyricGradStartRaw = ""
    @AppStorage("beans.lyricGradEnd") private var lyricGradEndRaw = ""
    /// 渐变模式：0=跟随封面自动取色（默认），1=始终保持用户自定义渐变
    @AppStorage("beans.lyricGradMode") private var lyricGradMode = 0
    /// 歌词行距（14~40，默认 24）
    @AppStorage("beans.lyricSpacing") private var lyricLineSpacing = 24
    /// 播放器氛围：背景流动开关 / 速度 / 呼吸光晕强度
    @AppStorage("beans.playerBreath") private var playerBreath = 0.6
    /// 播放控件颜色是否跟随封面主色；关闭后使用全局主题色
    @AppStorage("beans.playerControlsUseCoverColor") private var controlsUseCoverColor = true
    /// 显示歌词翻译（借鉴 Kumone：网易云 tlyric）
    @AppStorage("beans.lyricTranslation") private var lyricTranslation = true
    /// 进度条样式：0 流光 / 1 辉光 / 2 极光 / 3 波浪
    @AppStorage("beans.progressBarStyle") private var progressBarStyle = 0
    /// 进度条单独强调色；空值时跟随播放控件颜色
    @AppStorage("beans.progressAccentHex") private var progressAccentHex = ""
    /// 播放器布局自由调整：开关 + 各组件 x/y/z 数据 + 当前选中组件
    @AppStorage("beans.playerLayoutMode") private var layoutMode = false
    @State private var layoutData: [String: PlayerLayoutEntry] = PlayerLayoutStore.load()
    @State private var layoutPart: PlayerLayoutPart = .progress
    /// 歌词布局：对齐样式 / 水平偏移 / 垂直重心（底部更多或顶部更多歌词）
    @AppStorage("beans.lyricAlignRaw") private var lyricAlignRaw = "center"
    @AppStorage("beans.lyricOffsetX") private var lyricOffsetX = 0.0
    @AppStorage("beans.lyricAnchorY") private var lyricAnchorY = 0.0
    /// 歌词大小缩放（布局调整弹窗「大小」滑杆）
    @AppStorage("beans.lyricScale") private var lyricScale = 1.0
    /// 底部指示线开关（上滑呼出评论区）
    @AppStorage("beans.deckGrabberEnabled") private var deckGrabberEnabled = true
    /// 圆形封面模式（播放器大封面 / 歌词页左上角小封面）
    @AppStorage("beans.circularCover") private var circularCover = true
    /// 圆形封面自动旋转
    @AppStorage("beans.circularCoverSpin") private var circularCoverSpin = true
    /// 歌词自定义发光颜色（留空跟随当前行颜色 / 封面取色）
    @AppStorage("beans.lyricGlowColorRaw") private var lyricGlowColorRaw = ""
    /// 侧边滑动切歌（抖音式刷视频交互，默认开启）
    @AppStorage("beans.swipeSwitchSong") private var swipeSwitchSong = true
    /// 歌词模糊控制：起始距离（距当前行几行开始模糊）+ 模糊强度（0 = 关闭）
    @AppStorage("beans.lyricBlurStart") private var lyricBlurStart = 1
    @AppStorage("beans.lyricBlurAmount") private var lyricBlurAmount = 1.1
    /// 歌词 3D 倾斜角度（0 = 关闭；顶部向后倒，立体透视感）
    @AppStorage("beans.lyricTilt") private var lyricTilt = 0
    /// 歌词左右倾斜角度（0 = 关闭；负值向左、正值向右，立体透视感）
    @AppStorage("beans.lyricTiltY") private var lyricTiltY = 0
    /// 歌词进度偏移（秒）：歌词与音频不同步时手动校正，正数提前、负数延后
    @AppStorage("beans.lyricOffset") private var lyricOffset = 0.0
    /// 歌词界面自定义背景
    @AppStorage("beans.lyricBackground.image") private var lyricBackgroundImagePath = ""
    @AppStorage("beans.lyricBackground.blur") private var lyricBackgroundBlur = 12.0
    @AppStorage("beans.lyricBackground.syncCover") private var lyricBackgroundSyncCover = false
    /// 侧边滑动手势当前位移（刷视频式切歌过渡）
    @State private var swipeOffset: CGFloat = 0
    @State private var coverDrag: CGSize = .zero
    @State private var coverSwitchPulse = false
    @State private var animatedSongKey = ""

    private var song: Song? { player.currentSong }
    private let rateOptions: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    /// 封面主色联动调色板：背景渐变 / 进度条 / 播放暂停键 / 功能按钮 / 歌词高亮等全部跟随封面主色。
    /// 安全机制：只在切歌（.task(id: song?.identityKey)）时一次性提取并更新，绝不随封面加载过程高频重算 @State，
    /// 避免整页反复重绘导致的布局错乱与发烫。深浅模式切换时及时重算配色。
    /// 自定义歌词发光颜色
    private var lyricGlowColor: Color? {
        if lyricGlowColorRaw.hasPrefix("#"), let c = Color(hex: lyricGlowColorRaw) { return c }
        return nil
    }

    /// 歌词对齐样式（居中 / 全部居左）
    private var lyricAlign: HorizontalAlignment {
        lyricAlignRaw == "left" ? .leading : .center
    }

    /// 歌词垂直重心：0.5 居中；<0.5 当前行偏上（显示更多后续歌词），>0.5 偏下（显示更多已唱歌词）
    private var lyricAnchor: UnitPoint {
        let y = 0.5 + CGFloat(lyricAnchorY) / 200
        return UnitPoint(x: 0.5, y: min(max(y, 0.15), 0.85))
    }

    private var palette: CoverPalette {
        if let dominantColor {
            return CoverPalette.make(dominant: dominantColor, colorScheme: colorScheme)
        }
        return CoverPalette.fallback(colorScheme: colorScheme)
    }

    private var controlAccent: Color {
        controlsUseCoverColor ? palette.accent : Color.beansAmber
    }

    private var controlAccentSoft: Color {
        controlsUseCoverColor ? palette.accentSoft : Color.beansAmber.opacity(0.28)
    }

    private var progressAccent: Color {
        if progressAccentHex.hasPrefix("#"), let color = Color(hex: progressAccentHex) {
            return color
        }
        return controlAccent
    }

    private var playerVisualsActive: Bool {
        player.isPlaying && !showPlayerSettings
    }

    /// 当前行歌词颜色（可自定义；配色模式关闭时自动跟随封面取色）
    private var lyricCurrentColor: Color {
        guard lyricGradMode == 1 else { return palette.accent }
        switch lyricColorRaw {
        case "white": return .white
        case "amber": return Color.beansAmber
        case "cyan": return Color(red: 0.35, green: 0.85, blue: 0.96)
        case "pink": return Color(red: 1.0, green: 0.62, blue: 0.82)
        case "green": return Color(red: 0.42, green: 0.90, blue: 0.62)
        default:
            if lyricColorRaw.hasPrefix("#"), let c = Color(hex: lyricColorRaw) { return c }
            return palette.accent
        }
    }

    /// 未播放歌词颜色（可自定义；配色模式关闭时自动跟随封面取色）
    private var lyricDimColor: Color {
        guard lyricGradMode == 1 else { return palette.secondary }
        switch lyricDimColorRaw {
        case "white": return .white.opacity(0.78)
        case "bluegray": return Color(red: 0.72, green: 0.78, blue: 0.86)
        case "gray": return Color.gray.opacity(0.85)
        case "dark": return Color.black.opacity(0.55)
        default:
            if lyricDimColorRaw.hasPrefix("#"), let c = Color(hex: lyricDimColorRaw) { return c }
            return palette.secondary
        }
    }

    /// 当前行歌词渐变（可自定义起止色；未设置时自动从封面强调色派生，深浅模式自适应）
    /// 配色模式：开（保持自定义）时歌词颜色与渐变都一直用用户选色且切歌后不重置；关（默认）时全部自动跟随封面取色
    private var lyricGradStart: Color {
        if lyricGradMode == 1, lyricGradStartRaw.hasPrefix("#"), let c = Color(hex: lyricGradStartRaw) { return c }
        return lyricCurrentColor
    }
    private var lyricGradEnd: Color {
        if lyricGradMode == 1, lyricGradEndRaw.hasPrefix("#"), let c = Color(hex: lyricGradEndRaw) { return c }
        return mixedColor(lyricCurrentColor, with: colorScheme == .dark ? .white : .black, amount: 0.45)
    }
    private func mixedColor(_ c: Color, with other: Color, amount: CGFloat) -> Color {
        let ui = UIColor(c)
        let ui2 = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        ui.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        ui2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let a = min(max(amount, 0), 1)
        return Color(red: r1 * (1 - a) + r2 * a, green: g1 * (1 - a) + g2 * a, blue: b1 * (1 - a) + b2 * a)
    }

    private func glowName(_ level: Int) -> String {
        switch level {
        case 0: return "关闭"
        case 1: return "柔和"
        case 2: return "标准"
        default: return "强烈"
        }
    }

    /// 发光强度对应的 shadow 半径（0 关闭，最大 32，叠双层光晕更亮）
    private var lyricGlowRadius: CGFloat {
        switch lyricGlowLevel {
        case 0: return 0
        case 1: return 6
        case 2: return 12
        case 3: return 18
        case 4: return 25
        default: return 32
        }
    }

    var body: some View {
        let _ = theme.accent
        Group {
            if showPlayerSettings {
                Color.clear.ignoresSafeArea()
            } else {
                GeometryReader { geo in
                    ZStack {
                        background
                            .ignoresSafeArea()

                        VStack(spacing: 0) {
                            headerBar
                            content(geo: geo)
                        }
                        .foregroundStyle(palette.text)

                        controlDeck(bottomInset: geo.safeAreaInsets.bottom)
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: .infinity, alignment: .bottom)

                        // 布局编辑工具栏：组件选择 + X/Y/Z 滑杆 + 恢复默认 + 完成
                        if layoutMode {
                            layoutToolbar
                                .contentShape(Rectangle())
                                .frame(maxWidth: .infinity)
                                .frame(maxHeight: .infinity, alignment: .top)
                                .padding(.top, 54)
                                .transition(.opacity)
                        }

                        if showMoreActions {
                            Color.black.opacity(0.001)
                                .ignoresSafeArea()
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                                        showMoreActions = false
                                    }
                                }
                                .zIndex(70)

                            playerMoreActionsPanel
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .padding(.top, 76)
                                .zIndex(80)
                                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
                        }
                    }
                }
            }
        }
        .task(id: song?.identityKey) {
            let songKey = song?.identityKey ?? ""
            dominantColor = nil
            await MainActor.run {
                coverDrag = .zero
                let shouldPulse = !animatedSongKey.isEmpty && animatedSongKey != songKey
                animatedSongKey = songKey
                coverSwitchPulse = shouldPulse
                if shouldPulse {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        withAnimation(.easeOut(duration: 0.20)) {
                            coverSwitchPulse = false
                        }
                    }
                }
            }
            await loadLyrics()
            await extractCoverPalette()
        }
        .onChange(of: layoutData) { newValue in
            PlayerLayoutStore.save(newValue)
        }
        .sheet(isPresented: $showQueue) { QueueView().environmentObject(player) }
        .sheet(isPresented: $showSleepTimer) { SleepTimerSheet().environmentObject(player) }
        .sheet(isPresented: $showAddToPlaylist) {
            if let song {
                AddToPlaylistSheet(song: song).environmentObject(auth)
            }
        }
        .sheet(isPresented: $showComments) {
            if let song {
                CommentsSheet(song: song)
            }
        }
        .fullScreenCover(isPresented: $showPlayerSettings) {
            PlayerSettingsSheet()
        }
        .sheet(isPresented: $showShare) {
            if let song {
                ShareSheet(items: shareItems(for: song))
            }
        }
        .sheet(item: $shareFile, onDismiss: cleanupSharedFile) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(isPresented: $showAddToLocalPlaylist) {
            if let song {
                AddToLocalPlaylistSheet(song: song)
            }
        }
        .sheet(isPresented: $showArtistHome) {
            if !pickedArtistName.isEmpty {
                ArtistHomeSheet(artistName: pickedArtistName, artistSource: song?.source ?? .netease)
                    .environmentObject(player)
            }
        }
        .confirmationDialog("选择歌手", isPresented: $showArtistPicker, titleVisibility: .visible) {
            ForEach(Array(artistNames.enumerated()), id: \.offset) { _, name in
                Button(name) {
                    pickedArtistName = name
                    BeansHaptics.tap()
                    showArtistHome = true
                }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("下载《\(song?.name ?? "当前歌曲")》", isPresented: $showDownloadPicker, titleVisibility: .visible) {
            ForEach(DownloadQuality.allCases) { quality in
                Button(quality.label) {
                    Task { await downloadCurrent(quality) }
                }
            }
            Button("取消", role: .cancel) {}
        }
        .overlay(alignment: .bottom) {
            ToastView(center: ToastCenter.shared)
        }
    }

    // MARK: - 背景（主题渐变兜底 + 封面毛玻璃 + 可读性遮罩）
    // 毛玻璃封面为 UIKit 独立图层（CoverBlurBackground），加载/换图不经过 SwiftUI
    // 布局，因此封面加载完成不会引发布局重算，彻底避免"封面加载后错乱"。

    private var background: some View {
        ZStack {
            // 静态渐变：随封面主色取色，不流动（用户要求封面外液态 UI 飘动效果暂停，保持静止）
            LinearGradient(
                colors: [palette.backgroundTop, palette.backgroundBottom],
                startPoint: .top, endPoint: .bottom
            )
            if shouldUseLyricBackgroundAsPlayerBackground {
                lyricPlayerBackgroundLayer
            } else {
                CoverBlurBackground(url: song?.coverURL, scheme: colorScheme)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            AmbientGlowView(
                accent: palette.accent,
                secondary: palette.secondary,
                isPlaying: playerVisualsActive,
                breath: playerBreath
            )
            if djVisualEnabled {
                DJVisualView(
                    accent: palette.accent,
                    secondary: palette.secondary,
                    isPlaying: playerVisualsActive,
                    intensity: djVisualIntensity
                )
            }
            LinearGradient(
                colors: colorScheme == .dark
                    ? [.black.opacity(0.22), .clear, .black.opacity(0.34)]
                    : [.white.opacity(0.08), .clear, .black.opacity(0.12)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .allowsHitTesting(false)
    }

    private var shouldUseLyricBackgroundAsPlayerBackground: Bool {
        !lyricBackgroundImagePath.isEmpty && (showLyrics || lyricBackgroundSyncCover)
    }

    @ViewBuilder
    private var lyricPlayerBackgroundLayer: some View {
        if let image = UIImage(contentsOfFile: lyricBackgroundImagePath) {
            GeometryReader { proxy in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width + 96, height: proxy.size.height + 96)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .blur(radius: CGFloat(lyricBackgroundBlur))
                    .overlay(Color.black.opacity(colorScheme == .dark ? 0.48 : 0.34))
                    .clipped()
            }
            .ignoresSafeArea()
        } else {
            CoverBlurBackground(url: song?.coverURL, scheme: colorScheme)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 顶栏（收起 / 状态 / 红心 / 队列）

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button {
                BeansHaptics.tap()
                closePlayer()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .frame(width: 38, height: 38)
                    .background {
                                                BeansGlass(shape: Circle())
                    }
                    .clipShape(Circle())
            }
            .buttonStyle(GlassPressButtonStyle())
            .modifier(Layoutable(part: .topBack, enabled: layoutMode, data: $layoutData))

            Spacer(minLength: 0)

            Button {
                BeansHaptics.tap()
                withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                    showMoreActions.toggle()
                }
            } label: {
                VStack(spacing: 2) {
                    Text(player.isBuffering ? "加载中…" : (player.isPlaying ? "正在播放" : "已暂停"))
                        .font(BeansFont.appFont(12, .semibold))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                    Text(song?.album ?? "Beans Music")
                        .font(BeansFont.appFont(10))
                        .foregroundStyle(palette.secondary.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(minWidth: 118, maxWidth: 190)
                .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle(scale: 0.98))
            .modifier(Layoutable(part: .topTitle, enabled: layoutMode, data: $layoutData))

            Spacer(minLength: 0)
            Button {
                BeansHaptics.tap()
                if let song {
                    Task {
                        if await favorites.toggle(song) {
                            ToastCenter.shared.show(favorites.isLiked(song) ? "已收藏" : "已取消收藏")
                        } else {
                            ToastCenter.shared.show("收藏失败，请稍后再试")
                        }
                    }
                }
            } label: {
                Image(systemName: favorites.isLiked(song) ? "heart.fill" : "heart")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(favorites.isLiked(song) ? Color(red: 0.95, green: 0.33, blue: 0.42) : palette.text)
                    .frame(width: 38, height: 38)
                    .background {
                                                BeansGlass(shape: Circle())
                    }
                    .clipShape(Circle())
            }
            .buttonStyle(GlassPressButtonStyle())
            .modifier(Layoutable(part: .topFavorite, enabled: layoutMode, data: $layoutData))
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 1)
    }

    private var playerMoreActionsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "speedometer")
                    .font(.system(size: 13, weight: .semibold))
                Text("倍速播放")
                    .font(BeansFont.appFont(13, .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(palette.text)

            HStack(spacing: 6) {
                ForEach(rateOptions, id: \.self) { option in
                    Button {
                        player.setRate(option)
                        BeansHaptics.select()
                    } label: {
                        Text(String(format: "%.2gx", option))
                            .font(BeansFont.appFont(10, .semibold))
                            .foregroundStyle(abs(player.rate - option) < 0.01 ? Color.white : palette.text)
                            .frame(width: 36, height: 28)
                            .background {
                                Capsule().fill(abs(player.rate - option) < 0.01 ? controlAccent : Color.white.opacity(0.08))
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().overlay(Color.white.opacity(0.12))

            moreActionRow("定时关闭", systemName: player.sleepTimerRemaining > 0 ? "moon.zzz.fill" : "moon.zzz") {
                showMoreActions = false
                showSleepTimer = true
            }
            moreActionRow("添加到歌单", systemName: "text.badge.plus") {
                showMoreActions = false
                showAddToPlaylist = true
            }
            moreActionRow("下载歌曲", systemName: "arrow.down.circle") {
                showMoreActions = false
                showDownloadPicker = true
            }
            moreActionRow("分享歌曲", systemName: "square.and.arrow.up") {
                showMoreActions = false
                showShare = true
            }
            moreActionRow("加入本地歌单", systemName: "internaldrive") {
                showMoreActions = false
                showAddToLocalPlaylist = true
            }
            moreActionRow("播放器设置", systemName: "slider.horizontal.3") {
                showMoreActions = false
                showPlayerSettings = true
            }
        }
        .padding(14)
        .frame(width: 292)
        .background {
            BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .beansCardShadow(radius: 14, y: 8)
    }

    private func moreActionRow(_ title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            BeansHaptics.tap()
            withAnimation(.spring(response: 0.20, dampingFraction: 0.9)) {
                action()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20)
                Text(title)
                    .font(BeansFont.appFont(13, .semibold))
                Spacer()
            }
            .foregroundStyle(palette.text)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.98))
    }

    // MARK: - 中间内容区（专辑 / 歌词 两模式独立视图，自动布局居中）

    @ViewBuilder
    private func content(geo: GeometryProxy) -> some View {
        ZStack {
            if song == nil {
                placeholderView
            } else if showLyrics {
                lyricsPanel(geo: geo)
                    .transition(.opacity)
            } else {
                albumPanel(geo: geo)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.22), value: showLyrics)
    }

    /// 封面尺寸：固定算法，与布局时序无关
    private func coverSize(in geo: GeometryProxy) -> CGFloat {
        min(280, min(geo.size.width * 0.60, geo.size.height * 0.44))
    }

    /// 专辑模式：封面居中 + 歌名/歌手 + 轻点提示（VStack 自动居中）
    private func albumPanel(geo: GeometryProxy) -> some View {
        let size = coverSize(in: geo)
        let coverRadius: CGFloat = circularCover ? size / 2 : min(24, size * 0.08)
        return VStack(spacing: 16) {
            Spacer(minLength: 2)

            Button {
                toggleLyrics()
            } label: {
                ZStack {
                    // 静态装饰层（光晕 + 托盘）：不再呼吸/浮动（用户要求飘动效果暂停），封面本体静止
                    ZStack {
                            // 主色光晕（呼吸）
                            Circle()
                                .fill(palette.accent.opacity(0.24))
                                .frame(width: size * 1.38, height: size * 1.38)
                                .blur(radius: 46)
                                .scaleEffect(1.0)
                            // 次色光晕（反向呼吸，增加层次）
                            Circle()
                                .fill(palette.secondary.opacity(0.15))
                                .frame(width: size * 1.10, height: size * 1.10)
                                .blur(radius: 40)
                                .scaleEffect(1.0)
                            // 液态玻璃托盘（圆形模式用圆形托盘）
                            if circularCover {
                                BeansGlass(shape: Circle())
                                    .frame(width: size * 1.10, height: size * 1.10)
                                    .shadow(color: .black.opacity(0.28), radius: 26, y: 12)
                                    .offset(y: 0)
                            } else {
                                BeansGlass(shape: RoundedRectangle(cornerRadius: min(30, size * 0.10), style: .continuous))
                                    .frame(width: size * 1.10, height: size * 1.10)
                                    .shadow(color: .black.opacity(0.28), radius: 26, y: 12)
                                    .offset(y: 0)
                            }
                        }
                    .allowsHitTesting(false)

                    // 封面（静态）
                    CoverImage(url: song?.coverURL, size: size, cornerRadius: coverRadius, emptyHint: player.isBuffering ? "等待开始播放…" : nil)
                        .matchedGeometryEffect(id: "playerCover", in: coverNS)
                        .id(song?.identityKey ?? "empty-cover")
                        .modifier(CoverSpin(enabled: circularCover && circularCoverSpin, isPlaying: playerVisualsActive))
                        .overlay {
                            RoundedRectangle(cornerRadius: coverRadius, style: .continuous)
                                .strokeBorder(.white.opacity(0.28), lineWidth: 1)
                        }
                        .overlay {
                            // 顶部玻璃反光
                            RoundedRectangle(cornerRadius: coverRadius, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [.white.opacity(0.28), .white.opacity(0.03), .clear],
                                        startPoint: .top, endPoint: .center
                                    )
                                )
                        }
                        .clipShape(RoundedRectangle(cornerRadius: coverRadius, style: .continuous))
                        .shadow(color: .black.opacity(0.38), radius: 24, y: 12)
                        .scaleEffect(coverSwitchPulse ? 0.94 : 1)
                        .blur(radius: coverSwitchPulse ? 2 : 0)
                        .rotation3DEffect(.degrees(Double(coverDrag.height / -18)), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
                        .rotation3DEffect(.degrees(Double(coverDrag.width / 18)), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
                        .offset(x: coverDrag.width * 0.05, y: coverDrag.height * 0.05)
                        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: coverDrag)
                        .animation(.easeOut(duration: 0.24), value: coverSwitchPulse)
                }
                .frame(width: size * 1.10, height: size * 1.10)
                .gesture(
                    DragGesture(minimumDistance: 15)
                        .onChanged { value in
                            guard swipeSwitchSong else { return }
                            coverDrag = value.translation
                            let h = value.translation.height
                            if abs(h) > abs(value.translation.width) {
                                swipeOffset = h
                            }
                        }
                        .onEnded { value in
                            handleSwipeEnd(height: value.translation.height)
                        }
                )
            }
            .buttonStyle(GlassPressButtonStyle(scale: 0.96))
            .modifier(Layoutable(part: .cover, enabled: layoutMode, data: $layoutData))

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(song?.name ?? "未在播放")
                        .font(BeansFont.appFont(22, .bold))
                        .foregroundStyle(palette.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.55)
                        .multilineTextAlignment(.center)
                    if song?.isVIP == true {
                        Text("VIP")
                            .font(BeansFont.appFont(9, .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(red: 0.93, green: 0.25, blue: 0.22)))
                            .shadow(color: palette.accent.opacity(0.45), radius: 6)
                    }
                }
                .shadow(color: palette.accent.opacity(0.30), radius: 10)
                Text(subtitle)
                    .font(BeansFont.appFont(14, .medium))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentShape(Rectangle())
                    .onTapGesture { openArtistHome() }
            }
            .padding(.horizontal, 36)
            .modifier(Layoutable(part: .title, enabled: layoutMode, data: $layoutData))


            // 封面下歌词阅览（固定高度预留，歌词加载后布局不跳动）
            lyricPreviewBox
                .modifier(Layoutable(part: .previewLyric, enabled: layoutMode, data: $layoutData))

            Spacer(minLength: 2)
        }
        .padding(.bottom, deckInset + geo.safeAreaInsets.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 侧边上下滑动切歌（抖音式刷视频交互）：上滑下一首、下滑上一首，仅响应纵向手势
        // 使用 .gesture 与封面点击互斥：拖动时不会误触点击封面（避免切歌瞬间跳到歌词页）
        .offset(y: swipeOffset)
        .opacity(1 - min(abs(swipeOffset) / 260, 0.35))
        .gesture(
            DragGesture(minimumDistance: 15)
                .onChanged { value in
                    guard swipeSwitchSong else { return }
                    coverDrag = value.translation
                    let h = value.translation.height
                    if abs(h) > abs(value.translation.width) {
                        swipeOffset = h
                    }
                }
                .onEnded { value in
                    handleSwipeEnd(height: value.translation.height)
                }
        )
    }

    /// 封面下歌词阅览：最多 5 行，跟随当前播放行自动滚动预览
    private var lyricPreviewBox: some View {
        let rows = lyricPreviewRows
        return VStack(spacing: 3) {
            if rows.isEmpty {
                Text("暂无歌词，点击封面查看完整歌词")
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(palette.secondary.opacity(0.75))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 6) {
                        Text(item.isCurrent ? "●" : "·")
                            .font(BeansFont.appFont(8))
                            .foregroundStyle(item.isCurrent ? palette.accent : palette.secondary.opacity(0.5))
                        Text(item.text)
                            .font(BeansFont.appFont(12, item.isCurrent ? .semibold : .regular))
                            .foregroundStyle(item.isCurrent ? palette.text : palette.secondary.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: 5 * 18 + 4 * 3)
        .padding(.horizontal, 40)
        .contentShape(Rectangle())
        .onTapGesture { toggleLyrics() }
    }

    /// 歌词预览行数据：当前行前后各取几行，最多 5 行
    private struct LyricPreviewRow {
        let text: String
        let isCurrent: Bool
    }

    /// 当前歌词行索引（二分查找，与歌词面板一致）
    private var previewCurrentIndex: Int? {
        guard !lyrics.isEmpty else { return nil }
        var low = 0
        var high = lyrics.count - 1
        var answer: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lyrics[mid].time <= LyricTiming.effectiveProgress(clock.progress, userOffset: lyricOffset) {
                answer = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return answer
    }

    private var lyricPreviewRows: [LyricPreviewRow] {
        guard !lyrics.isEmpty else { return [] }
        var rows: [LyricPreviewRow] = []
        if let idx = previewCurrentIndex {
            let start = max(0, idx - 2)
            for i in start..<min(lyrics.count, start + 5) {
                let text = lyrics[i].text
                rows.append(LyricPreviewRow(text: text.isEmpty ? " " : text, isCurrent: i == idx))
            }
        } else {
            for i in 0..<min(5, lyrics.count) {
                let text = lyrics[i].text
                rows.append(LyricPreviewRow(text: text.isEmpty ? " " : text, isCurrent: i == 0))
            }
        }
        return rows
    }


    /// 歌词模式：左上小封面 + 歌名信息条 + 居中歌词（自动布局，歌词可滚动到底部透过底栏玻璃）
    private func lyricsPanel(geo: GeometryProxy) -> some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                Button {
                    toggleLyrics()
                } label: {
                    CoverImage(url: song?.coverURL, size: 48, cornerRadius: circularCover ? 24 : 12)
                        .matchedGeometryEffect(id: "playerCover", in: coverNS)
                        .modifier(CoverSpin(enabled: circularCover && circularCoverSpin, isPlaying: playerVisualsActive))
                        .overlay {
                            RoundedRectangle(cornerRadius: circularCover ? 24 : 12, style: .continuous)
                                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                        }
                }
                .buttonStyle(GlassPressButtonStyle(scale: 0.9))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(song?.name ?? "")
                            .font(BeansFont.appFont(14, .semibold))
                            .foregroundStyle(palette.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if song?.isVIP == true {
                            Text("VIP")
                                .font(BeansFont.appFont(8, .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Color(red: 0.93, green: 0.25, blue: 0.22)))
                        }
                    }
                    Text(song?.artists ?? "")
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contentShape(Rectangle())
                        .onTapGesture { openArtistHome() }
                }

                Spacer(minLength: 0)

                Button {
                    toggleLyrics()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                        .frame(width: 34, height: 34)
                        .background {
                                                        BeansGlass(shape: Circle())
                        }
                        .clipShape(Circle())
                }
                .buttonStyle(GlassPressButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 3)

            // 歌词视口截止到底栏上方：当前行在可见区居中（26 版风格，无渐隐遮挡）
            Group {
                if lyrics.isEmpty {
                    emptyLyricsView
                } else {
                    LyricsSection(lyrics: lyrics, accent: lyricCurrentColor, secondary: lyricDimColor, gradientStart: lyricGradStart, gradientEnd: lyricGradEnd, baseFontSize: CGFloat(lyricFontSize) * CGFloat(lyricScale), lineSpacing: CGFloat(lyricLineSpacing), glowRadius: lyricGlowRadius, showTranslation: lyricTranslation, alignment: lyricAlign, offsetX: CGFloat(lyricOffsetX), anchor: lyricAnchor, glowColorOverride: lyricGlowColor, blurStart: CGFloat(lyricBlurStart), blurAmount: lyricBlurAmount, tilt: CGFloat(lyricTilt), tiltY: CGFloat(lyricTiltY), lyricOffset: CGFloat(lyricOffset)) { line in
                        BeansHaptics.tap()
                        player.seek(to: LyricTiming.seekTime(for: line, userOffset: lyricOffset))
                    }
                }
            }
            .padding(.bottom, deckInset + geo.safeAreaInsets.bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id("lyricsPanel-\(song?.identityKey ?? "none")")
    }

    // MARK: - 空态兜底（歌曲数据为空时不出现空白页）

    private var placeholderView: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(palette.secondary)
            Text("暂无播放内容")
                .font(BeansFont.appFont(16, .medium))
                .foregroundStyle(palette.text)
            Text("返回选择一首歌曲即可开始播放")
                .font(BeansFont.appFont(13))
                .foregroundStyle(palette.secondary)
            Button {
                BeansHaptics.tap()
                closePlayer()
            } label: {
                Text("返回")
                    .font(BeansFont.appFont(14, .semibold))
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 10)
                    .background {
                                                BeansGlass(shape: Capsule())
                    }
            }
            .buttonStyle(GlassPressButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 空歌词兜底

    private var emptyLyricsView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            VStack(spacing: 10) {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(palette.secondary.opacity(0.7))
                Text("暂无歌词")
                    .font(BeansFont.appFont(14, .medium))
                    .foregroundStyle(palette.text)
                Text("点击左上角封面返回专辑视图")
                    .font(BeansFont.appFont(11))
                    .foregroundStyle(palette.secondary.opacity(0.8))
            }
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 底部控制栏（旧式悬浮布局：进度 / 主控制）

    /// 底部控制栏估算高度（单行控制后降低，给歌词视口更多空间）
    /// 底部控制栏预留高度（越小歌词视口越大；需 >= 控制栏实际高度避免遮挡；可视化开启时控制栏更高）
    private var deckInset: CGFloat { 116 }

    private func controlDeck(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            progressBlock
                .modifier(Layoutable(part: .progress, enabled: layoutMode, data: $layoutData))
            deckRow
                .modifier(Layoutable(part: .controls, enabled: layoutMode, data: $layoutData))
            deckGrabber
        }
        .padding(.horizontal, 24)
        .padding(.top, 0)
        .padding(.bottom, bottomInset)
        .frame(maxWidth: .infinity)
    }

    /// 底部指示线：只有在指示线附近上滑才呼出评论区（避免误触控制按钮）
    /// 指示线可关闭（透明但保留热区，仍可上滑呼出评论区）
    /// 布局模式下可直接拖动调整位置（与底部其他组件一致），滑杆同步可用
    private var deckGrabber: some View {
        Capsule()
            .fill(deckGrabberEnabled ? palette.secondary.opacity(0.5) : .clear)
            .frame(width: 40, height: 5)
            .overlay {
                if deckGrabberEnabled {
                    Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
            .scaleEffect(grabberEntry.scale)
            .offset(x: grabberEntry.x, y: grabberEntry.y)
            .gesture(
                layoutMode
                    ? AnyGesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            layoutPart = .grabber
                            var e = layoutData[PlayerLayoutPart.grabber.rawValue] ?? PlayerLayoutStore.defaultEntry(for: .grabber)
                            e.x = value.translation.width
                            e.y = value.translation.height
                            layoutData[PlayerLayoutPart.grabber.rawValue] = e
                        })
                    : AnyGesture(DragGesture(minimumDistance: 25)
                        .onEnded { value in
                            if value.translation.height < -50, song != nil {
                                BeansHaptics.medium()
                                showComments = true
                            }
                        })
            )
    }

    private var subtitle: String {
        guard let song else { return "" }
        let parts = [song.artists, song.album].filter { !$0.isEmpty }
        return parts.isEmpty ? "未知歌曲" : parts.joined(separator: " · ")
    }

    // MARK: - 进度区块（可点按 / 拖动的进度条 + 当前时间 / 总时长 + ±15 秒）

    private var progressBlock: some View {
        VStack(spacing: 1) {
            SeekBar(accent: progressAccent, track: palette.secondary.opacity(0.3), style: progressBarStyle)
            HStack(spacing: 6) {
                seekPillButton("gobackward.15") { player.seekBy(-15) }
                Text(beansTimeString(clock.progress))
                    .font(BeansFont.appFont(10, .regular, .monospaced))
                    .foregroundStyle(palette.secondary)
                    .frame(minWidth: 34, alignment: .leading)
                Spacer(minLength: 0)
                Text(beansTimeString(clock.duration))
                    .font(BeansFont.appFont(10, .regular, .monospaced))
                    .foregroundStyle(palette.secondary)
                    .frame(minWidth: 34, alignment: .trailing)
                seekPillButton("goforward.15") { player.seekBy(15) }
            }
        }
    }

    private func seekPillButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            BeansHaptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.secondary)
                .frame(width: 30, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle())
    }

    // MARK: - 合并控制行（循环 / 上一曲 / 播放暂停 / 下一曲 / 播放列表 平行排列，播放键居中）

    private var deckRow: some View {
        ZStack {
            // 两侧对称：循环模式 / 播放列表
            HStack {
                modeButton
                Spacer(minLength: 0)
                queueButton
            }
            // 中间主控制组：上一曲 / 播放暂停 / 下一曲 真正居中
            HStack(spacing: 16) {
                deckButton(icon: "backward.fill", expand: false, part: .previous) {
                    BeansHaptics.tap()
                    player.previous()
                }
                playButton
                deckButton(icon: "forward.fill", expand: false, part: .next) {
                    BeansHaptics.tap()
                    player.next()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    /// 循环 / 随机播放按钮（随机模式高亮）
    private var modeButton: some View {
        Button {
            BeansHaptics.select()
            player.togglePlayMode()
        } label: {
            Image(systemName: player.playMode.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(player.playMode == .shuffle ? controlAccent : palette.secondary)
                .frame(width: 24, height: 24)
                .background {
                                        BeansGlass(shape: Circle())
                }
                .clipShape(Circle())
        }
        .buttonStyle(GlassPressButtonStyle())
        .modifier(Layoutable(part: .loop, enabled: layoutMode, data: $layoutData))
    }

    /// 播放列表按钮
    private var queueButton: some View {
        Button {
            BeansHaptics.tap()
            showQueue = true
        } label: {
            Image(systemName: "list.bullet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.secondary)
                .frame(width: 24, height: 24)
                .background {
                                        BeansGlass(shape: Circle())
                }
                .clipShape(Circle())
        }
        .buttonStyle(GlassPressButtonStyle())
        .modifier(Layoutable(part: .queue, enabled: layoutMode, data: $layoutData))
    }

    private func deckButton(icon: String, accent: Bool = false, expand: Bool = true, part: PlayerLayoutPart? = nil, action: @escaping () -> Void) -> some View {
        Button {
            BeansHaptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(accent ? controlAccent : palette.text)
                .frame(width: 34, height: 34)
                .background {
                                        BeansGlass(shape: Circle())
                }
                .clipShape(Circle())
        }
        .buttonStyle(GlassPressButtonStyle())
        .frame(maxWidth: expand ? .infinity : nil)
        .modifier(Layoutable(part: part ?? .controls, enabled: layoutMode && part != nil, data: $layoutData))
    }

    private var playButton: some View {
        Button {
            BeansHaptics.tap()
            player.togglePlayPause()
        } label: {
            PlayPauseMorphIcon(isPlaying: player.isPlaying, size: 22)
                .foregroundStyle(Color.white)
                .frame(width: 56, height: 56)
                .background {
                                        BeansGlass(shape: Circle())
                    .overlay {
                        Circle().fill(
                            LinearGradient(
                                colors: [controlAccent.opacity(0.55), controlAccentSoft.opacity(0.55)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    }
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.30), lineWidth: 1)
                    }
                }
                .clipShape(Circle())
                .shadow(color: controlAccent.opacity(0.4), radius: 14, y: 7)
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.9))
    }


    // MARK: - 播放器自定义布局工具栏（x / y / z + 恢复默认）

    /// 当前选中组件的绑定（滑杆读写；歌词映射到独立存储的偏移值）
    private var selectedLayoutEntry: Binding<PlayerLayoutEntry> {
        Binding(
            get: {
                switch layoutPart {
                case .lyric:
                    return PlayerLayoutEntry(x: CGFloat(lyricOffsetX), y: CGFloat(lyricAnchorY), scale: CGFloat(lyricScale))
                default:
                    return layoutData[layoutPart.rawValue] ?? PlayerLayoutStore.defaultEntry(for: layoutPart)
                }
            },
            set: { newValue in
                switch layoutPart {
                case .lyric:
                    lyricOffsetX = Double(newValue.x)
                    lyricAnchorY = Double(newValue.y)
                    lyricScale = Double(newValue.scale)
                default:
                    layoutData[layoutPart.rawValue] = newValue
                }
            }
        )
    }

    /// 指示线位置（存于布局数据字典，X / Y 偏移）
    private var grabberEntry: PlayerLayoutEntry {
        layoutData[PlayerLayoutPart.grabber.rawValue] ?? PlayerLayoutStore.defaultEntry(for: .grabber)
    }

    /// 各组件 X 滑杆范围
    private var layoutXRange: ClosedRange<CGFloat> {
        switch layoutPart {
        case .lyric:
            return -80...80
        case .topBack, .topTitle, .topFavorite, .cover, .title, .previewLyric:
            return -180...180
        default:
            return -140...140
        }
    }

    /// 各组件 Y 滑杆范围
    private var layoutYRange: ClosedRange<CGFloat> {
        switch layoutPart {
        case .lyric: return -80...80
        case .topBack, .topTitle, .topFavorite: return -80...160
        case .cover, .title, .previewLyric: return -220...220
        case .grabber: return -120...120
        default: return -300...300
        }
    }

    private var layoutToolbar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("自定义布局")
                    .font(BeansFont.appFont(15, .bold))
                Spacer()
                Button {
                    BeansHaptics.select()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { layoutMode = false }
                } label: {
                    Text("完成")
                        .font(BeansFont.appFont(13, .semibold))
                        .foregroundStyle(Color.beansAmber)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PlayerLayoutPart.allCases) { part in
                        Button {
                            BeansHaptics.select()
                            layoutPart = part
                        } label: {
                            Text(part.rawValue)
                                .font(BeansFont.appFont(12, .semibold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .foregroundStyle(layoutPart == part ? Color.white : palette.secondary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background {
                                    Capsule().fill(layoutPart == part ? Color.beansAmber : Color.beansGlassFill)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            layoutSlider("X", value: selectedLayoutEntry.x, range: layoutXRange)
            layoutSlider("Y", value: selectedLayoutEntry.y, range: layoutYRange)
            layoutSlider("大小", value: selectedLayoutEntry.scale, range: 0.6...1.5, step: 0.05, format: "%.2f")
            HStack(spacing: 10) {
                Button {
                    resetCurrentLayoutPart()
                    BeansHaptics.success()
                } label: {
                    Label("恢复默认", systemImage: "arrow.counterclockwise")
                        .font(BeansFont.appFont(13, .medium))
                        .foregroundStyle(Color.beansAmber)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("编辑模式：顶部、封面、歌名、歌词和底部控件都可调")
                    .font(BeansFont.appFont(11))
                    .foregroundStyle(palette.secondary)
            }
        }
        .padding(14)
        .background {
            BeansGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(.horizontal, 12)
    }

    private func resetCurrentLayoutPart() {
        switch layoutPart {
        case .lyric:
            lyricOffsetX = 0
            lyricAnchorY = 0
            lyricScale = 1
        default:
            layoutData.removeValue(forKey: layoutPart.rawValue)
            PlayerLayoutStore.save(layoutData)
        }
    }

    private func layoutSlider(_ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>, step: CGFloat = 1, format: String = "%.0f") -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(BeansFont.appFont(12, .medium))
                .foregroundStyle(palette.secondary)
                .frame(width: 56, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .tint(Color.beansAmber)
            Text(String(format: format, value.wrappedValue))
                .font(BeansFont.appFont(11, .regular, .monospaced))
                .foregroundStyle(palette.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    // MARK: - 分享

    /// 原生系统分享内容：歌名 - 歌手 + 对应平台链接
    private func shareItems(for song: Song) -> [Any] {
        var text = "\(song.name) - \(song.artists)"
        if let url = shareURL(for: song) {
            text += "\n\(url.absoluteString)"
        }
        return [text]
    }

    /// 各平台歌曲链接（网易云 / QQ音乐 / 酷狗音乐）
    private func shareURL(for song: Song) -> URL? {
        switch song.source {
        case .netease:
            return URL(string: "https://music.163.com/#/song?id=\(song.id)")
        case .qq:
            if let mid = song.qqMid, !mid.isEmpty {
                return URL(string: "https://y.qq.com/n/ryqq/songDetail/\(mid)")
            }
            let encoded = song.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? song.name
            return URL(string: "https://y.qq.com/n/ryqq/search?w=\(encoded)")
        case .kugou:
            let encoded = song.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? song.name
            return URL(string: "https://www.kugou.com/yy/html/search.html#searchType=song&searchKeyWord=\(encoded)")
        }
    }

    // MARK: - 下载

    private func downloadCurrent(_ quality: DownloadQuality) async {
        guard let song else { return }
        BeansHaptics.medium()
        ToastCenter.shared.show("开始下载：\(song.name)")
        let result = await DownloadManager.shared.download(song: song, quality: quality)
        switch result {
        case .success(let downloadResult):
            BeansLogger.shared.log("下载完成，弹出分享：\(song.name)（\(quality.rawValue)\(downloadResult.downgraded ? "，已自动降级" : "")）", level: .info)
            sharedFileURL = downloadResult.url
            shareFile = ShareFileItem(url: downloadResult.url)
        case .failure(let error):
            BeansLogger.shared.log("下载失败：\(song.name) - \(error.localizedDescription)", level: .error)
            ToastCenter.shared.show("下载失败：\(error.localizedDescription)", duration: 3)
        }
    }

    /// 分享面板关闭后清理临时下载文件（不占用户存储）
    private func cleanupSharedFile() {
        if let url = sharedFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        sharedFileURL = nil
        shareFile = nil
    }

    // MARK: - 动作

    /// 全部歌手名（多歌手歌曲点击时弹出选择，避免只打开第一位）
    private var artistNames: [String] {
        guard let artists = song?.artists else { return [] }
        return artists
            .replacingOccurrences(of: " / ", with: "/")
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).description }
            .filter { !$0.isEmpty }
    }

    /// 首位歌手名（用于跳转歌手主页）
    private var primaryArtistName: String {
        artistNames.first ?? ""
    }

    private func openArtistHome() {
        guard !primaryArtistName.isEmpty else { return }
        BeansHaptics.tap()
        if artistNames.count > 1 {
            showArtistPicker = true
        } else {
            pickedArtistName = primaryArtistName
            showArtistHome = true
        }
    }

    private func toggleLyrics() {
        BeansHaptics.tap()
        withAnimation(.easeInOut(duration: 0.22)) {
            showLyrics.toggle()
        }
    }

    private func closePlayer() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
            isPresented = false
        }
    }

    /// 刷抖音式切歌：松手后旧封面继续飞出屏幕，新封面从对侧滑入（上滑下一首：旧向上飞、新从底部上来；下滑反之）
    private func handleSwipeEnd(height: CGFloat) {
        guard swipeSwitchSong else { return }
        let h = height
        if h < -70 {
            BeansHaptics.tap()
            coverDrag = .zero
            flySwipe(direction: -1)
        } else if h > 70 {
            BeansHaptics.tap()
            coverDrag = .zero
            flySwipe(direction: 1)
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                swipeOffset = 0
                coverDrag = .zero
            }
        }
    }

    private func flySwipe(direction: CGFloat) {
        let flyOut: CGFloat = direction * 560
        let flyIn: CGFloat = -direction * 560
        // 1) 当前封面继续向滑动方向飞出
        withAnimation(.easeIn(duration: 0.17)) { swipeOffset = flyOut }
        // 2) 飞出后立即切歌，并把新封面放到对侧屏幕外，再滑回中央
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) {
            // 动画期间开关被关闭：面板直接复位，避免卡在屏幕外
            guard swipeSwitchSong else {
                withAnimation(.easeOut(duration: 0.2)) {
                    swipeOffset = 0
                    coverDrag = .zero
                }
                return
            }
            if direction < 0 { player.next() } else { player.previous() }
            swipeOffset = flyIn
            // 等下一帧先渲染出新封面在屏幕外的位置，再动画滑回中央（否则动画会从旧位置开始，方向不对）
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.26)) { swipeOffset = 0 }
            }
        }
    }

    private func loadLyrics() async {
        lyrics = []
        guard let song else { return }
        let identity = song.identityKey
        func apply(_ parsed: [LyricLine]) {
            guard self.song?.identityKey == identity else { return }
            self.lyrics = parsed
        }
        if song.source == .kugou, let hash = song.kugouHash {
            let raw = await KugouMusicAPI.shared.lyric(hash: hash, duration: song.duration)
            apply(LyricParser.parse(raw))
        } else if song.source == .qq, let mid = song.qqMid {
            if let raw = try? await QQMusicAPI.shared.lyric(songmid: mid) {
                apply(LyricParser.parse(raw))
            }
        } else {
            if let (lrc, tlyric) = try? await NetEaseAPI.shared.lyricWithTranslation(id: song.id) {
                apply(LyricParser.parse(lrc ?? "", translationRaw: tlyric))
            }
        }
    }

    /// 一次性提取当前封面主色，带动整个播放器配色动态变化（失败时保持主题回退色，不影响任何功能）
    private func extractCoverPalette() async {
        guard let url = song?.coverURL else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data),
                  let dominant = PaletteExtractor.dominantColor(in: image) else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                dominantColor = dominant
            }
        } catch {
            // 提取失败：静默保持回退色
        }
    }

}

// MARK: - 自定义进度条（点击 / 拖动均可跳转，配色跟随封面主色）

struct SeekBar: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var clock: PlaybackClock
    let accent: Color
    let track: Color
    /// 进度条样式：0 流光 / 1 辉光 / 2 极光 / 3 波浪
    var style: Int = 0

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    /// 流光样式：光点游动相位（0→1 往返）
    @State private var flowPhase: CGFloat = 0
    @State private var lastPreviewSecond: Int?

    private var progress: Double {
        scrubbing ? scrubValue : clock.progress
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let total = max(clock.duration, 1)
            let ratio = min(max(progress / total, 0), 1)
            let thumbX = min(max(width * ratio, 10), max(width - 10, 10))

            ZStack(alignment: .leading) {
                // 轨道与已播放段（按样式）
                switch style {
                case 1:
                    // 辉光：全宽渐变底轨 + 明亮已播放段 + 底部柔光
                    Capsule()
                        .fill(
                            LinearGradient(colors: [accent.opacity(0.28), track.opacity(0.5), accent.opacity(0.18)],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(height: 7)
                    Capsule()
                        .fill(
                            LinearGradient(colors: [.white.opacity(0.9), accent],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: thumbX, height: 7)
                        .shadow(color: accent.opacity(0.65), radius: 5, y: 1)
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: max(3, thumbX - 4), height: 2)
                        .offset(y: -2)
                        .clipShape(Capsule())
                case 2:
                    // 极光：发丝细线 + 极光渐变 + 大号光晕滑块
                    Capsule()
                        .fill(track.opacity(0.6))
                        .frame(height: 2.5)
                    Capsule()
                        .fill(
                            LinearGradient(colors: [accent, .white.opacity(0.85), accent.opacity(0.6)],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: thumbX, height: 2.5)
                        .shadow(color: accent.opacity(0.7), radius: 4)
                    Circle()
                        .fill(.white.opacity(0.16))
                        .frame(width: 30, height: 30)
                        .overlay {
                            Circle()
                                .fill(
                                    LinearGradient(colors: [.white, accent.opacity(0.85)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                                .frame(width: 18, height: 18)
                                .overlay {
                                    Circle().strokeBorder(.white.opacity(0.95), lineWidth: 1)
                                }
                        }
                        .shadow(color: accent.opacity(0.85), radius: scrubbing ? 9 : 6)
                        .scaleEffect(scrubbing ? 1.15 : 1)
                        .offset(x: thumbX - 15)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: scrubbing)
                case 3:
                    // 波浪：正弦波形，已播放段高亮发光
                    WaveBar(ratio: ratio, accent: accent, track: track, width: width, isPlaying: player.isPlaying)
                default:
                    // 流光：清透轨道 + 渐变已播放段 + 顶部高光 + 游动光点
                    Capsule()
                        .fill(track.opacity(0.55))
                        .frame(height: 5)
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .frame(height: 5)
                        .overlay {
                            Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                        }
                    Capsule()
                        .fill(
                            LinearGradient(colors: [accent, accent.opacity(0.6), .white.opacity(0.85)],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: thumbX, height: 5)
                        .shadow(color: accent.opacity(0.45), radius: 4, y: 1)
                        .overlay(alignment: .top) {
                            LinearGradient(colors: [.white.opacity(0.55), .clear],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: 2.5)
                                .clipShape(Capsule())
                        }
                    if player.isPlaying {
                        // 游动光点仅在播放中运行，暂停后不保留 repeatForever 动画。
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.35))
                                .blur(radius: 4)
                                .frame(width: 14, height: 14)
                            Circle()
                                .fill(.white.opacity(0.95))
                                .frame(width: 5, height: 5)
                                .shadow(color: .white.opacity(0.7), radius: 2)
                        }
                        .offset(x: max(2, thumbX - 5) * flowPhase)
                        .animation(.linear(duration: 2.4).repeatForever(autoreverses: true), value: flowPhase)
                    }
                }

                // 滑块（流光/辉光/波浪用发光圆点；极光自带大滑块）
                if style != 2 {
                    Circle()
                        .fill(.white)
                        .frame(width: scrubbing ? 22 : 14, height: scrubbing ? 22 : 14)
                        .overlay {
                            Circle().strokeBorder(.white.opacity(0.95), lineWidth: 0.8)
                        }
                        .shadow(color: accent.opacity(0.7), radius: scrubbing ? 10 : 3.5, y: scrubbing ? 3 : 1)
                        .offset(x: thumbX - (scrubbing ? 11 : 7))
                        .animation(.spring(response: 0.24, dampingFraction: 0.76), value: scrubbing)
                }

                if scrubbing {
                    Text(beansTimeString(scrubValue))
                        .font(BeansFont.appFont(11, .semibold, .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background {
                            Capsule()
                                .fill(.black.opacity(0.48))
                                .overlay {
                                    Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.7)
                                }
                        }
                        .shadow(color: accent.opacity(0.35), radius: 10, y: 4)
                        .offset(x: min(max(thumbX - 31, 0), max(width - 62, 0)), y: -25)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .frame(width: width, height: 42)
            .onAppear {
                if player.isPlaying, flowPhase == 0 { flowPhase = 1 }
            }
            .onChange(of: player.isPlaying) { playing in
                flowPhase = playing ? 1 : 0
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !scrubbing {
                            BeansHaptics.medium()
                        }
                        scrubbing = true
                        let raw = min(max(value.location.x / width, 0), 1) * total
                        let snapped = raw.rounded()
                        scrubValue = snapped
                        let previewSecond = Int(snapped)
                        if previewSecond != lastPreviewSecond, previewSecond % 15 == 0 {
                            BeansHaptics.select()
                        }
                        lastPreviewSecond = previewSecond
                    }
                    .onEnded { _ in
                        BeansHaptics.tap()
                        player.seek(to: scrubValue)
                        scrubbing = false
                        lastPreviewSecond = nil
                    }
            )
        }
        .frame(height: 42)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: scrubbing)
    }
}


// MARK: - 波浪进度条（正弦波形：已播放段高亮，波面缓慢流动）

private struct WaveShape: Shape {
    var phase: CGFloat = 0
    var amplitude: CGFloat = 3.2

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mid = rect.midY
        let freq: CGFloat = 2.4
        path.move(to: CGPoint(x: 0, y: mid))
        var x: CGFloat = 0
        while x <= rect.width {
            let y = mid + sin(x / rect.width * .pi * 2 * freq + phase * .pi * 2) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            x += 2
        }
        return path
    }
}

private struct WaveBar: View {
    let ratio: Double
    let accent: Color
    let track: Color
    let width: CGFloat
    let isPlaying: Bool

    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack(alignment: .leading) {
            // 辉光底层光晕（已播放段模糊扩散，辉光渐变氛围）
            WaveShape(phase: phase)
                .stroke(accent.opacity(0.5), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .blur(radius: 8)
                .frame(width: width, height: 16)
                .frame(width: max(0, width * CGFloat(ratio)), alignment: .leading)
                .clipped()
            // 未播放波形（暗色渐变轨道）
            WaveShape(phase: phase)
                .stroke(
                    LinearGradient(colors: [accent.opacity(0.25), track.opacity(0.45), accent.opacity(0.15)],
                                   startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 2.6, lineCap: .round)
                )
                .frame(width: width, height: 16)
            // 已播放波形（辉光渐变高亮：白→主色→淡，双阴影辉光）
            WaveShape(phase: phase)
                .stroke(
                    LinearGradient(colors: [.white.opacity(0.95), accent, accent.opacity(0.6)],
                                   startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 3.6, lineCap: .round)
                )
                .shadow(color: accent.opacity(0.8), radius: 6, y: 1)
                .shadow(color: accent.opacity(0.45), radius: 14)
                .frame(width: width, height: 16)
                .frame(width: max(0, width * CGFloat(ratio)), alignment: .leading)
                .clipped()
        }
        .frame(height: 20)
        .onAppear {
            if isPlaying, phase == 0 { phase = 1 }
        }
        .onChange(of: isPlaying) { playing in
            phase = playing ? 1 : 0
        }
        .animation(isPlaying ? .linear(duration: 3).repeatForever(autoreverses: false) : .default, value: phase)
    }
}

// MARK: - 歌词（居中显示 + 逐行高亮 + 自动滚动 + 点击跳转）

struct LyricsSection: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var clock: PlaybackClock
    let lyrics: [LyricLine]
    let accent: Color
    let secondary: Color
    var gradientStart: Color? = nil
    var gradientEnd: Color? = nil
    var baseFontSize: CGFloat = 17
    var lineSpacing: CGFloat = 24
    var glowRadius: CGFloat = 9
    /// 显示歌词翻译（当前行下方小字）
    var showTranslation: Bool = false
    /// 歌词对齐样式（居中 / 居左）
    var alignment: HorizontalAlignment = .center
    /// 歌词水平偏移
    var offsetX: CGFloat = 0
    /// 当前行在视口中的垂直锚点
    var anchor: UnitPoint = .center
    /// 自定义发光颜色（nil 时跟随当前行颜色 / 封面取色）
    var glowColorOverride: Color? = nil
    /// 歌词模糊控制：距当前行几行后开始模糊 + 模糊强度（0 = 完全关闭模糊）
    var blurStart: CGFloat = 1
    var blurAmount: CGFloat = 1.1
    /// 歌词 3D 倾斜角度（绕 X 轴，顶部向后倒，0 = 关闭）
    var tilt: CGFloat = 0
    /// 歌词左右倾斜角度（绕 Y 轴，负值向左、正值向右，0 = 关闭）
    var tiltY: CGFloat = 0
    /// 歌词进度偏移（秒）：正数提前、负数延后
    var lyricOffset: CGFloat = 0
    let onTapLine: (LyricLine) -> Void

    /// 长按歌词进入多选复制模式（可多选 / 全选复制）
    @State private var selectionMode = false
    @State private var selected: Set<Int> = []
    /// 用户手动滚动时暂停自动跟随（借鉴 Kumone：3 秒后恢复）
    @State private var isUserScrolling = false
    @State private var resumeScrollTask: Task<Void, Never>?

    /// 二分查找当前行（歌词按时间升序），避免逐行扫描降低 CPU
    private var currentIndex: Int? {
        guard !lyrics.isEmpty else { return nil }
        var low = 0
        var high = lyrics.count - 1
        var answer: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lyrics[mid].time <= LyricTiming.effectiveProgress(clock.progress, userOffset: Double(lyricOffset)) {
                answer = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return answer
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: lineSpacing) {
                    ForEach(Array(lyrics.enumerated()), id: \.element.id) { index, line in
                        lyricRow(index: index, line: line)
                            .contentShape(Rectangle())
                            .overlay(alignment: .topTrailing) {
                                if selectionMode {
                                    Image(systemName: selected.contains(index) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(selected.contains(index) ? accent : secondary.opacity(0.55))
                                        .padding(.trailing, 10)
                                        .padding(.top, 2)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .gesture(
                                LongPressGesture(minimumDuration: 0.35)
                                    .onEnded { _ in
                                        BeansHaptics.medium()
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            if !selectionMode {
                                                selectionMode = true
                                                selected = [index]
                                            } else {
                                                toggleSelect(index)
                                            }
                                        }
                                    }
                                    .exclusively(before: TapGesture().onEnded { _ in
                                        if selectionMode {
                                            withAnimation(.easeInOut(duration: 0.2)) { toggleSelect(index) }
                                        } else {
                                            onTapLine(line)
                                        }
                                    })
                            )
                            .id(index)
                    }
                }
                .padding(.vertical, 210)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .offset(x: offsetX)
            .beansScrollIndicatorsHidden()
            // 3D 倾斜：绕 X 轴顶部向后倒，anchor 底部固定，营造立体透视感
            .rotation3DEffect(.degrees(Double(tilt)), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
            // 左右倾斜：绕 Y 轴以中心为支点，负值向左、正值向右
            .rotation3DEffect(.degrees(Double(tiltY)), axis: (x: 0, y: 1, z: 0), anchor: .center, perspective: 0.5)
            // 上下渐隐遮罩（借鉴 Kumone 歌词界面）：歌词接近顶部/底部时自然淡出
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.10),
                        .init(color: .black, location: 0.90),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(alignment: .top) {
                if selectionMode {
                    selectionBar
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onAppear {
                // 延迟到布局稳定后再定位当前行，避免从封面页调整进度后切回歌词错位
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    scrollToCurrent(proxy)
                }
            }
            .onChange(of: currentIndex) { newIndex in
                guard let newIndex, !isUserScrolling else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newIndex, anchor: anchor)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { _ in
                        guard !isUserScrolling else { return }
                        isUserScrolling = true
                        resumeScrollTask?.cancel()
                        resumeScrollTask = Task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            guard !Task.isCancelled else { return }
                            await MainActor.run { isUserScrolling = false }
                        }
                    }
            )
        }
    }

    /// Apple Music 风格渐隐：当前行最大最亮，已播放行与未播放行按距离逐层变暗变淡
    private func lyricRow(index: Int, line: LyricLine) -> some View {
        let isCurrent = index == currentIndex
        let isPlayed = (currentIndex ?? -1) >= 0 && index < (currentIndex ?? 0)
        let distance = abs(index - (currentIndex ?? 0))
        let opacity: Double = isCurrent
            ? 1.0
            : (isPlayed ? 0.38 : 0.72) - Double(min(distance, 4)) * 0.05
        let size = isCurrent ? baseFontSize + 4 : baseFontSize - CGFloat(min(distance, 2)) * 1.5
        // 歌词行模糊：当前行与邻近行保持清晰，距离越远才越柔和（避免只剩一行清晰显得突兀）
        // 模糊起始距离与强度由用户控制（0 强度 = 完全关闭模糊）
        let blurRadius: CGFloat = isCurrent ? 0 : min(CGFloat(max(distance - Int(blurStart), 0)) * blurAmount, 6.0)

        // 当前行用渐变（封面色或自定义），光晕跟随渐变起始色
        let lineStyle: AnyShapeStyle
        if isCurrent, let gradientStart, let gradientEnd {
            lineStyle = AnyShapeStyle(LinearGradient(colors: [gradientStart, gradientEnd], startPoint: .top, endPoint: .bottom))
        } else {
            lineStyle = AnyShapeStyle(isCurrent ? accent : secondary)
        }
        let glowColor = glowColorOverride ?? (gradientStart ?? accent)

        let lineFont: Font = BeansFont.appFont(size)
        // 翻译行：仅当前行展示（借鉴 Kumone 的歌词翻译显示）
        let translationText = (isCurrent && showTranslation) ? line.translation : nil

        return VStack(spacing: 3) {
            Text(line.text.isEmpty ? " " : line.text)
                .font(lineFont)
                .foregroundStyle(lineStyle)
                // 双层光晕：内层亮、外层宽，发光更明显
                .shadow(
                    color: isCurrent ? glowColor.opacity(glowRadius > 0 ? 0.9 : 0) : .clear,
                    radius: isCurrent ? glowRadius * 0.45 : 0
                )
                .shadow(
                    color: isCurrent ? glowColor.opacity(glowRadius > 0 ? 0.55 : 0) : .clear,
                    radius: isCurrent ? glowRadius : 0
                )
                .blur(radius: blurRadius)
                .opacity(max(opacity, 0.15))
                .scaleEffect(isCurrent ? 1.05 : 1)
                .multilineTextAlignment(alignment == .leading ? .leading : .center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            if let translationText, !translationText.isEmpty {
                Text(translationText)
                    .font(BeansFont.appFont(size * 0.68, .regular))
                    .foregroundStyle(secondary.opacity(isCurrent ? 0.9 : 0.45))
                    .multilineTextAlignment(alignment == .leading ? .leading : .center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .blur(radius: blurRadius * 0.5)
                    .opacity(max(opacity, 0.2))
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
        .padding(.horizontal, alignment == .leading ? 40 : 36)
        .animation(.easeInOut(duration: 0.25), value: currentIndex)
    }

    private func toggleSelect(_ index: Int) {
        if selected.contains(index) {
            selected.remove(index)
        } else {
            selected.insert(index)
        }
    }

    private func copySelected() {
        let text = selected.sorted()
            .compactMap { idx -> String? in
                lyrics.indices.contains(idx) ? lyrics[idx].text : nil
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        BeansHaptics.success()
        withAnimation(.easeInOut(duration: 0.2)) {
            selectionMode = false
            selected = []
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 16) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { selected = Set(lyrics.indices) }
            } label: {
                Text("全选")
                    .font(BeansFont.appFont(13, .medium))
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
            Button {
                copySelected()
            } label: {
                Text(selected.isEmpty ? "复制" : "复制 (\(selected.count))")
                    .font(BeansFont.appFont(13, .semibold))
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectionMode = false
                    selected = []
                }
            } label: {
                Text("取消")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
                }
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy) {
        guard let currentIndex else { return }
        proxy.scrollTo(currentIndex, anchor: anchor)
    }
}

// MARK: - 歌词渐变预设（一键组合：渐变起止色 + 发光强度）

struct LyricPreset {
    let name: String
    let start: String
    let end: String
    let glow: Int

    static let all: [LyricPreset] = [
        LyricPreset(name: "晨曦金", start: "#FFD08A", end: "#FF7A3D", glow: 2),
        LyricPreset(name: "冰蓝极光", start: "#8FD8FF", end: "#5B6BFF", glow: 2),
        LyricPreset(name: "霓虹紫", start: "#E8A2FF", end: "#8A2BE2", glow: 3),
        LyricPreset(name: "草莓奶昔", start: "#FF9AB5", end: "#FF5E8A", glow: 1),
        LyricPreset(name: "鎏金夜曲", start: "#F5D98B", end: "#C9A227", glow: 2),
        LyricPreset(name: "薄荷气泡", start: "#A8F0D4", end: "#2BC48D", glow: 2),
    ]
}

// MARK: - 播放器设置（更多菜单 → 播放器设置：进度条样式 / 背景光晕 / 歌词字号 / 颜色色盘）

struct PlayerSettingsSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @AppStorage("beans.playerBreath") private var breath = 0.6
    @AppStorage("beans.playerControlsUseCoverColor") private var controlsUseCoverColor = true
    @AppStorage("beans.progressBarStyle") private var progressBarStyle = 0
    @AppStorage("beans.progressAccentHex") private var progressAccentHex = ""
    @AppStorage("beans.lyricFontSize") private var fontSize = 17
    @AppStorage("beans.lyricSpacing") private var lineSpacing = 24
    @AppStorage("beans.lyricGlow") private var glowLevel = 1
    @AppStorage("beans.lyricColor") private var currentColorRaw = "accent"
    @AppStorage("beans.lyricDimColor") private var dimColorRaw = "dim"
    @AppStorage("beans.lyricGradStart") private var gradStartRaw = ""
    @AppStorage("beans.lyricGradEnd") private var gradEndRaw = ""
    @AppStorage("beans.lyricGradMode") private var gradMode = 0
    @AppStorage("beans.lyricTranslation") private var lyricTranslation = true
    @AppStorage("beans.playerLayoutMode") private var layoutMode = false
    @AppStorage("beans.lyricAlignRaw") private var lyricAlignRaw = "center"
    @AppStorage("beans.lyricOffsetX") private var lyricOffsetX = 0.0
    @AppStorage("beans.lyricAnchorY") private var lyricAnchorY = 0.0
    @AppStorage("beans.deckGrabberEnabled") private var deckGrabberEnabled = true
    @AppStorage("beans.circularCover") private var circularCover = true
    @AppStorage("beans.circularCoverSpin") private var circularCoverSpin = true
    @AppStorage("beans.djVisual") private var djVisualEnabled = false
    @AppStorage("beans.djVisualIntensity") private var djVisualIntensity = 0.8
    @AppStorage("beans.lyricGlowColorRaw") private var glowColorRaw = ""
    @AppStorage("beans.swipeSwitchSong") private var swipeSwitchSong = true
    @AppStorage("beans.lyricBlurStart") private var lyricBlurStart = 1
    @AppStorage("beans.lyricBlurAmount") private var lyricBlurAmount = 1.1
    @AppStorage("beans.lyricTilt") private var lyricTilt = 0
    @AppStorage("beans.lyricTiltY") private var lyricTiltY = 0
    @AppStorage("beans.lyricOffset") private var lyricOffset = 0.0
    @AppStorage("beans.lyricBackground.image") private var lyricBackgroundImagePath = ""
    @AppStorage("beans.lyricBackground.blur") private var lyricBackgroundBlur = 12.0
    @AppStorage("beans.lyricBackground.syncCover") private var lyricBackgroundSyncCover = false
    @AppStorage("beans.audio.mixothers.v1") private var mixesWithOthers = false
    @Environment(\.dismiss) private var dismiss
    @State private var playbackExpanded = false
    @State private var lyricDisplayExpanded = false
    @State private var lyricEffectExpanded = false
    @State private var layoutExpanded = false
    @State private var coverExpanded = false
    @State private var showLyricBackgroundPicker = false

    /// 左右倾斜文案：0 关闭，负值左倾、正值右倾
    private var tiltYText: String {
        if lyricTiltY == 0 { return "关闭" }
        return lyricTiltY > 0 ? "右倾 \(lyricTiltY)°" : "左倾 \(-lyricTiltY)°"
    }

    /// 预设按钮：点击应用渐变起止色 + 发光强度
    private func presetButton(_ preset: LyricPreset) -> some View {
        Button {
            gradStartRaw = preset.start
            gradEndRaw = preset.end
            glowLevel = preset.glow
            gradMode = 1
            BeansHaptics.select()
        } label: {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(
                        colors: [(Color(hex: preset.start) ?? Color.beansAmber), (Color(hex: preset.end) ?? Color.beansComment)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(height: 26)
                Text(preset.name)
                    .font(BeansFont.appFont(10, .medium))
                    .foregroundStyle(Color.beansLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// 当前行高亮色：色盘选色写入 hex，关闭面板后依然生效
    private var currentColor: Binding<Color> {
        Binding(
            get: {
                if currentColorRaw.hasPrefix("#"), let c = Color(hex: currentColorRaw) { return c }
                return Color.beansAmber
            },
            set: { newValue in
                currentColorRaw = "#" + UIColor(newValue).hexString
                gradMode = 1
            }
        )
    }

    /// 未播放歌词颜色：同上
    private var dimColor: Binding<Color> {
        Binding(
            get: {
                if dimColorRaw.hasPrefix("#"), let c = Color(hex: dimColorRaw) { return c }
                return Color.beansComment
            },
            set: { newValue in
                dimColorRaw = "#" + UIColor(newValue).hexString
                gradMode = 1
            }
        )
    }

    /// 歌词发光颜色：留空时跟随当前行颜色 / 封面取色
    private var glowColor: Binding<Color> {
        Binding(
            get: {
                if glowColorRaw.hasPrefix("#"), let c = Color(hex: glowColorRaw) { return c }
                return Color.beansAmber
            },
            set: { newValue in
                glowColorRaw = "#" + UIColor(newValue).hexString
            }
        )
    }

    /// 进度条单独颜色：留空时跟随播放控件颜色
    private var progressAccentColor: Binding<Color> {
        Binding(
            get: {
                if progressAccentHex.hasPrefix("#"), let c = Color(hex: progressAccentHex) { return c }
                return Color.beansAmber
            },
            set: { newValue in
                progressAccentHex = "#" + UIColor(newValue).hexString
            }
        )
    }

    /// 渐变起始色：空值时自动用主题强调色
    private var gradStart: Binding<Color> {
        Binding(
            get: {
                if gradStartRaw.hasPrefix("#"), let c = Color(hex: gradStartRaw) { return c }
                return Color.beansAmber
            },
            set: { newValue in
                gradStartRaw = "#" + UIColor(newValue).hexString
                gradMode = 1
            }
        )
    }

    /// 渐变结束色：空值时自动用主题次色
    private var gradEnd: Binding<Color> {
        Binding(
            get: {
                if gradEndRaw.hasPrefix("#"), let c = Color(hex: gradEndRaw) { return c }
                return Color.beansComment
            },
            set: { newValue in
                gradEndRaw = "#" + UIColor(newValue).hexString
                gradMode = 1
            }
        )
    }

    var body: some View {
        let _ = theme.accent
        BeansNavigationStack {
            ScrollView {
                LazyVStack(spacing: 8) {
                    playingCard
                    lyricDisplayCard
                    lyricEffectCard
                    layoutCard
                    coverCard
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
            }
            .navigationTitle("播放器设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .fullScreenCover(isPresented: $showLyricBackgroundPicker) {
            WallpaperPhotoPicker { data in
                if let path = LyricBackgroundStore.save(data) {
                    lyricBackgroundImagePath = path
                    BeansHaptics.success()
                    ToastCenter.shared.show("歌词背景已应用")
                } else {
                    ToastCenter.shared.show("歌词背景保存失败")
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - 设置卡片（液态玻璃圆角分组，紧凑排版）

    /// 设置卡片容器：液态玻璃圆角卡片
    private func settingCard<Content: View>(_ title: String, isExpanded: Binding<Bool>? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if let isExpanded {
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        isExpanded.wrappedValue.toggle()
                    }
                    BeansHaptics.select()
                } label: {
                    HStack(spacing: 10) {
                        Text(title)
                            .font(BeansFont.appFont(13, .bold))
                            .foregroundStyle(Color.beansLabel)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.beansComment)
                            .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
                            .frame(width: 24, height: 24)
                    }
                    .frame(minHeight: 38)
                    .contentShape(Rectangle())
                }
                .buttonStyle(GlassPressButtonStyle(scale: 0.98))

                if isExpanded.wrappedValue {
                    content()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else {
                Text(title)
                    .font(BeansFont.appFont(14, .bold))
                    .foregroundStyle(Color.beansLabel)
                content()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            PlayerSettingsLiquidGlass(shape: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    /// 开关行（标题 + 可选的短说明）
    private func settingToggle(_ title: String, isOn: Binding<Bool>, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: isOn)
                .tint(Color.beansAmber)
                .font(BeansFont.appFont(14))
            if let caption {
                Text(caption)
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansComment)
            }
        }
    }

    /// 滑块行（标题 + 数值内联显示）
    private func settingSlider<L: View>(_ title: String, valueText: String, @ViewBuilder slider: () -> L) -> some View {
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
            slider()
        }
    }

    /// 播放卡片：切歌 / 进度条样式 / 背景光晕 / DJ 视觉
    private var playingCard: some View {
        settingCard("播放", isExpanded: $playbackExpanded) {
            settingToggle("播放控件跟随封面取色", isOn: $controlsUseCoverColor,
                          caption: "开启：播放键、进度条和高亮跟随封面；关闭：使用你设置的主题色")
            Divider().opacity(0.5)
            settingToggle("播放页上下滑动切换歌曲", isOn: $swipeSwitchSong,
                          caption: "上下滑动像刷视频一样切歌：上滑下一首、下滑上一首")
            Divider().opacity(0.5)
            Text("进度条样式")
                .font(BeansFont.appFont(13))
                .foregroundStyle(Color.beansLabel)
            progressStyleGrid
            Divider().opacity(0.5)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("进度条颜色")
                        .font(BeansFont.appFont(13))
                        .foregroundStyle(Color.beansLabel)
                    Text(progressAccentHex.isEmpty ? "跟随播放控件颜色" : "使用自定义颜色")
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                }
                Spacer()
                ColorPicker("", selection: progressAccentColor)
                    .labelsHidden()
                Button {
                    progressAccentHex = ""
                    BeansHaptics.select()
                } label: {
                    Text("跟随")
                        .font(BeansFont.appFont(12, .semibold))
                        .foregroundStyle(Color.beansAmber)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Divider().opacity(0.5)
            settingSlider("背景光晕强度", valueText: "\(Int((breath * 100).rounded()))%") {
                Slider(value: $breath, in: 0...1, step: 0.05)
                    .tint(Color.beansAmber)
            }
            Divider().opacity(0.5)
            settingToggle("DJ 节奏脉冲光效", isOn: $djVisualEnabled,
                          caption: "封面背后随节拍扩散光环（仅播放时运行动画）")
            if djVisualEnabled {
                settingSlider("光效强度", valueText: "\(Int((djVisualIntensity * 100).rounded()))%") {
                    Slider(value: $djVisualIntensity, in: 0...1, step: 0.05)
                        .tint(Color.beansAmber)
                }
            }
            Divider().opacity(0.5)
            settingToggle("与其他音频同时播放", isOn: $mixesWithOthers,
                          caption: "默认关闭以显示锁屏/灵动岛；开启后可与其他 App 声音同时播放")
                .onChange(of: mixesWithOthers) { value in
                    PlayerManager.applyAudioMixPreference(value)
                }
        }
    }

    /// 进度条样式四宫格图标选择
    private var progressStyleGrid: some View {
        let styles: [(Int, String, String)] = [
            (0, "流光", "rays"),
            (1, "辉光", "sun.max"),
            (2, "极光", "sparkles"),
            (3, "波浪", "waveform"),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(styles, id: \.0) { idx, name, icon in
                Button {
                    progressBarStyle = idx
                    BeansHaptics.select()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .medium))
                        Text(name)
                            .font(BeansFont.appFont(11, .medium))
                    }
                    .foregroundStyle(progressBarStyle == idx ? Color.beansAmber : Color.beansLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        (progressBarStyle == idx ? Color.beansAmber.opacity(0.16) : Color.primary.opacity(0.05)),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(progressBarStyle == idx ? Color.beansAmber.opacity(0.5) : .clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 歌词显示卡片：字号 / 行距 / 翻译
    private var lyricOffsetText: String {
        if lyricOffset == 0 { return "同步" }
        return lyricOffset > 0
            ? "提前 " + String(format: "%.1f", lyricOffset) + "s"
            : "延后 " + String(format: "%.1f", -lyricOffset) + "s"
    }

    private var lyricDisplayCard: some View {
        settingCard("歌词显示", isExpanded: $lyricDisplayExpanded) {
            settingSlider("歌词字号", valueText: "\(fontSize) pt") {
                Slider(
                    value: Binding(get: { Double(fontSize) }, set: { fontSize = Int($0) }),
                    in: 12...28,
                    step: 1
                )
                .tint(Color.beansAmber)
            }
            Divider().opacity(0.5)
            settingSlider("歌词行距", valueText: "\(lineSpacing) pt") {
                Slider(
                    value: Binding(get: { Double(lineSpacing) }, set: { lineSpacing = Int($0) }),
                    in: 14...40,
                    step: 1
                )
                .tint(Color.beansAmber)
            }
            Divider().opacity(0.5)
            settingSlider("歌词进度偏移", valueText: lyricOffsetText) {
                Slider(value: Binding(get: { lyricOffset }, set: { lyricOffset = Double($0) }), in: -10...10, step: 0.1)
                    .tint(Color.beansAmber)
            }
            HStack {
                Text("歌词与音频不同步时手动校正（正数提前、负数延后）")
                    .font(BeansFont.appFont(11))
                    .foregroundStyle(Color.beansComment)
                Spacer()
                Button("重置") { lyricOffset = 0 }
                    .font(BeansFont.appFont(12, .semibold))
                    .foregroundStyle(Color.beansAmber)
                    .buttonStyle(.plain)
            }
            Divider().opacity(0.5)
            settingToggle("显示歌词翻译", isOn: $lyricTranslation,
                          caption: "当前播放歌词下方显示译文（网易云 tlyric）")
        }
    }

    /// 歌词效果卡片：模糊 / 发光 / 渐变预设 / 配色
    private var lyricEffectCard: some View {
        settingCard("歌词效果", isExpanded: $lyricEffectExpanded) {
            settingSlider("模糊起始距离", valueText: "\(lyricBlurStart) 行") {
                Slider(value: Binding(get: { Double(lyricBlurStart) }, set: { lyricBlurStart = Int($0) }), in: 0...4, step: 1)
                    .tint(Color.beansAmber)
            }
            settingSlider("模糊强度", valueText: lyricBlurAmount < 0.05 ? "关闭" : String(format: "%.1f", lyricBlurAmount)) {
                Slider(value: $lyricBlurAmount, in: 0...6, step: 0.1)
                    .tint(Color.beansAmber)
            }
            Divider().opacity(0.5)
            settingSlider("3D 倾斜", valueText: lyricTilt == 0 ? "关闭" : "\(lyricTilt)°") {
                Slider(
                    value: Binding(get: { Double(lyricTilt) }, set: { lyricTilt = Int($0) }),
                    in: 0...45,
                    step: 1
                )
                .tint(Color.beansAmber)
            }
            Divider().opacity(0.5)
            settingSlider("左右倾斜", valueText: tiltYText) {
                Slider(
                    value: Binding(get: { Double(lyricTiltY) }, set: { lyricTiltY = Int($0) }),
                    in: -45...45,
                    step: 1
                )
                .tint(Color.beansAmber)
            }
            Divider().opacity(0.5)
            settingSlider("歌词发光", valueText: glowName(glowLevel)) {
                Slider(
                    value: Binding(get: { Double(glowLevel) }, set: { glowLevel = Int($0) }),
                    in: 0...5,
                    step: 1
                )
                .tint(Color.beansAmber)
            }
            Divider().opacity(0.5)
            Text("渐变预设")
                .font(BeansFont.appFont(13))
                .foregroundStyle(Color.beansLabel)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(Array(LyricPreset.all.prefix(3).enumerated()), id: \.element.name) { _, preset in
                        presetButton(preset)
                    }
                }
                HStack(spacing: 8) {
                    ForEach(Array(LyricPreset.all.dropFirst(3).enumerated()), id: \.element.name) { _, preset in
                        presetButton(preset)
                    }
                }
            }
            Divider().opacity(0.5)
            settingToggle("保持自定义配色", isOn: Binding(get: { gradMode == 1 }, set: { gradMode = $0 ? 1 : 0 }),
                          caption: "关闭时自动跟随歌曲封面取色调整")
            ColorPicker("当前行颜色", selection: currentColor, supportsOpacity: false)
                .font(BeansFont.appFont(14))
            ColorPicker("未播放行颜色", selection: dimColor, supportsOpacity: false)
                .font(BeansFont.appFont(14))
            ColorPicker("歌词发光颜色", selection: glowColor, supportsOpacity: false)
                .font(BeansFont.appFont(14))
            Divider().opacity(0.5)
            ColorPicker("渐变起始色", selection: gradStart, supportsOpacity: false)
                .font(BeansFont.appFont(14))
            ColorPicker("渐变结束色", selection: gradEnd, supportsOpacity: false)
                .font(BeansFont.appFont(14))
            Divider().opacity(0.5)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("歌词界面背景")
                        .font(BeansFont.appFont(13))
                        .foregroundStyle(Color.beansLabel)
                    Text(lyricBackgroundImagePath.isEmpty ? "未设置" : "已使用自定义图片")
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                }
                Spacer()
                Button {
                    showLyricBackgroundPicker = true
                    BeansHaptics.tap()
                } label: {
                    Text("上传")
                        .font(BeansFont.appFont(12, .semibold))
                        .foregroundStyle(Color.beansAmber)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                if !lyricBackgroundImagePath.isEmpty {
                    Button {
                        LyricBackgroundStore.clear()
                        lyricBackgroundImagePath = ""
                        BeansHaptics.select()
                    } label: {
                        Text("清除")
                            .font(BeansFont.appFont(12, .semibold))
                            .foregroundStyle(Color.red)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            if !lyricBackgroundImagePath.isEmpty {
                settingSlider("背景模糊", valueText: "\(Int(lyricBackgroundBlur))") {
                    Slider(value: $lyricBackgroundBlur, in: 0...30, step: 1)
                        .tint(Color.beansAmber)
                }
                settingToggle("同步到封面页背景", isOn: $lyricBackgroundSyncCover,
                              caption: "开启后播放器封面界面也使用这张自定义背景")
            }
            HStack {
                Button("恢复默认颜色") {
                    currentColorRaw = ""
                    dimColorRaw = ""
                    glowColorRaw = ""
                    gradMode = 0
                    BeansHaptics.select()
                }
                .font(BeansFont.appFont(13))
                .foregroundStyle(Color.beansAmber)
                Spacer()
                Button("恢复默认渐变") {
                    gradStartRaw = ""
                    gradEndRaw = ""
                    gradMode = 0
                    BeansHaptics.select()
                }
                .font(BeansFont.appFont(13))
                .foregroundStyle(Color.beansAmber)
            }
        }
    }

    /// 布局卡片：播放器自定义布局 / 指示线 / 歌词对齐
    private var layoutCard: some View {
        settingCard("布局", isExpanded: $layoutExpanded) {
            settingToggle("播放器自定义布局", isOn: Binding(
                get: { layoutMode },
                set: { newValue in
                    layoutMode = newValue
                    // 开启后直接回到播放页进行调节
                    if newValue { dismiss() }
                }
            ), caption: "开启后回到播放页，可拖动顶部栏、封面、歌名、预览歌词和底部控件")
            Divider().opacity(0.5)
            settingToggle("显示底部指示线", isOn: $deckGrabberEnabled,
                          caption: "关闭后隐藏指示线，仍可上滑呼出评论区")
            Divider().opacity(0.5)
            HStack {
                Text("歌词对齐样式")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansLabel)
                Spacer()
                Picker("歌词对齐样式", selection: $lyricAlignRaw) {
                    Text("居中").tag("center")
                    Text("全部居左").tag("left")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 190)
            }
            Button("恢复歌词默认") {
                lyricAlignRaw = "center"
                lyricOffsetX = 0
                lyricAnchorY = 0
                BeansHaptics.select()
            }
            .font(BeansFont.appFont(13))
            .foregroundStyle(Color.beansAmber)
        }
    }

    /// 封面卡片：圆形封面 / 旋转
    private var coverCard: some View {
        settingCard("封面", isExpanded: $coverExpanded) {
            settingToggle("圆形封面模式", isOn: $circularCover,
                          caption: "播放器封面与歌词页左上角封面显示为圆形")
            Divider().opacity(0.5)
            settingToggle("圆形封面旋转", isOn: $circularCoverSpin,
                          caption: "开启后播放时封面自动匀速旋转")
        }
    }

    private func glowName(_ level: Int) -> String {
        switch level {
        case 0: return "关闭"
        case 1: return "柔和"
        case 2: return "标准"
        case 3: return "强烈"
        case 4: return "明亮"
        default: return "极亮"
        }
    }
}

private struct PlayerSettingsLiquidGlass<S: Shape>: View {
    let shape: S

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer {
                shape
                    .fill(.clear)
                    .glassEffect(.clear, in: shape)
            }
        } else {
            shape
                .fill(Color.beansGlassFill.opacity(0.72))
        }
    }
}

// MARK: - 下载文件分享（Identifiable 包装，供 sheet(item:) 使用）

struct ShareFileItem: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - 原生系统分享面板（UIActivityViewController 封装，直接调系统自带分享）

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad 弹出需要 popover 锚点，否则会崩溃
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
            popover.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - 圆形封面旋转（播放中匀速旋转，暂停即停）
struct CoverSpin: ViewModifier {
    let enabled: Bool
    let isPlaying: Bool

    func body(content: Content) -> some View {
        if enabled {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isPlaying)) { context in
                let angle = (context.date.timeIntervalSinceReferenceDate * 15)
                    .truncatingRemainder(dividingBy: 360)
                return content
                    .rotationEffect(.degrees(angle))
            }
        } else {
            content
        }
    }
}
