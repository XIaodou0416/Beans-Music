import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - 工具

func beansSongCountText(_ count: Int) -> String {
    beansLocalized("\(count) 首", "\(count) songs")
}

func beansLocalSongCountText(_ count: Int) -> String {
    beansLocalized("\(count) 首 · 本机", "\(count) songs · On device")
}

func beansTimeString(_ seconds: Double) -> String {
    let total = max(0, Int(seconds))
    return String(format: "%d:%02d", total / 60, total % 60)
}

// MARK: - 触感反馈（复用生成器实例，避免每次点击创建新对象造成额外开销/发热）

enum BeansHaptics {
    static let enabledKey = "beans.haptics.enabled"

    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let notification = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()

    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static func prepare() {
        guard isEnabled else { return }
        lightImpact.prepare()
        mediumImpact.prepare()
        selection.prepare()
    }

    static func tap() {
        guard isEnabled else { return }
        lightImpact.impactOccurred()
    }

    static func medium() {
        guard isEnabled else { return }
        mediumImpact.impactOccurred()
    }

    static func success() {
        guard isEnabled else { return }
        notification.notificationOccurred(.success)
    }

    static func select() {
        guard isEnabled else { return }
        selection.selectionChanged()
    }
}

// MARK: - 按压动效

struct GlassPressButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? 0.025 : 0)
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

// MARK: - 背景氛围（液态玻璃需要有可采样的动态内容）

struct GlassBackdrop: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("beans.uiStyle") private var uiStyleRaw = BeansUIStyle.liquid.rawValue
    /// 自定义背景色（nil 使用默认氛围渐变）
    var customColor: Color? = nil
    /// 主页模式：即使“同步到全部页面”关闭，也始终显示壁纸/背景色（仅发现页传 true）
    var homeMode: Bool = false
    /// 详情页使用原生氛围背景，不跟随全局壁纸同步
    var ignoreCustomBackground: Bool = false
    /// 主页壁纸额外模糊半径
    var wallpaperBlur: CGFloat = 0

    /// 当前页面是否启用自定义背景：同步开启时全部页面生效，关闭时仅主页生效
    private var showCustomBackground: Bool {
        !ignoreCustomBackground && (theme.backgroundSyncAll || homeMode)
    }

    /// 背景图上叠加的可读性遮罩：浅色模式几乎不压暗，深色模式适度压暗
    private var wallpaperOverlay: [Color] {
        colorScheme == .dark
            ? [.black.opacity(0.35), .black.opacity(0.55)]
            : [.black.opacity(0.08), .black.opacity(0.18)]
    }

    private var uiStyle: BeansUIStyle {
        uiStyleRaw == "outline" ? .clear : (BeansUIStyle(rawValue: uiStyleRaw) ?? .liquid)
    }

    var body: some View {
        let _ = theme.accent
        let activeBackgroundColor = theme.customBackground(for: colorScheme) ?? customColor
        let activeBackgroundImage = theme.customBackgroundImage(for: colorScheme)
        ZStack {
            if uiStyle == .nativeClean, !showCustomBackground || (activeBackgroundImage == nil && activeBackgroundColor == nil) {
                Color(UIColor.systemBackground)
            } else if let image = activeBackgroundImage, showCustomBackground {
                WallpaperImage(image: image, blurRadius: wallpaperBlur)
                LinearGradient(colors: wallpaperOverlay, startPoint: .top, endPoint: .bottom)
            } else if showCustomBackground, let activeBackgroundColor {
                LinearGradient(
                    colors: [activeBackgroundColor.opacity(0.9), activeBackgroundColor.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                )
            } else {
                LinearGradient.beansBackdrop
            }
            if uiStyle != .nativeClean {
                Circle()
                    .fill(Color.beansAmber.opacity(0.14))
                    .frame(width: 340, height: 340)
                    .blur(radius: 100)
                    .offset(x: 150, y: -300)
                Circle()
                    .fill(Color.beansSage.opacity(0.12))
                    .frame(width: 300, height: 300)
                    .blur(radius: 110)
                    .offset(x: -160, y: 340)
            }
        }
        .ignoresSafeArea()
    }
}


// MARK: - 背景墙纸（上传图片：固定全屏布局，不影响其他 UI 尺寸；小图轻度柔化避免像素感）

struct WallpaperImage: View {
    let image: UIImage
    var blurRadius: CGFloat = 0

    /// 小于约 700x700 视为小图：放大时轻度模糊柔化，避免满屏马赛克
    private static func isSmall(_ image: UIImage) -> Bool {
        image.size.width * image.size.height < 480_000
    }

    var body: some View {
        // 用 GeometryReader 明确采用父容器尺寸渲染，图片尺寸/比例与 UI 布局完全隔离
        GeometryReader { geo in
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .blur(radius: max(Self.isSmall(image) ? 5 : 0, blurRadius))
        }
        .ignoresSafeArea()
    }
}

// MARK: - 全局容器（跟随全局 UI 样式）

struct BeansGlass<S: Shape>: View {
    @AppStorage("beans.uiStyle") private var uiStyleRaw = BeansUIStyle.liquid.rawValue

    let shape: S
    var forceLiquid = false

    private var uiStyle: BeansUIStyle {
        uiStyleRaw == "outline" ? .clear : (BeansUIStyle(rawValue: uiStyleRaw) ?? .liquid)
    }

    private var isLiquid: Bool {
        forceLiquid || uiStyle == .liquid || uiStyle == .nativeClean
    }

    var body: some View {
        if isLiquid {
            if #available(iOS 26, *) {
                GlassEffectContainer {
                    shape
                        .fill(.clear)
                        .glassEffect(.clear, in: shape)
                }
            } else {
                shape
                    .fill(.ultraThinMaterial)
            }
        } else {
            switch uiStyle {
            case .clear, .liquid:
                shape
                    .fill(.ultraThinMaterial)
            case .compact:
                shape
                    .fill(Color.beansGlassFill.opacity(0.74))
            case .nativeClean:
                shape
                    .fill(Color.beansGlassFill.opacity(0.62))
            }
        }
    }
}

/// 统一表面容器：Apple 简洁样式使用低存在感的平面底色，
/// 其他样式继续沿用原有的玻璃材质，避免页面局部出现不同质感。
struct BeansSurface<S: Shape>: View {
    @AppStorage("beans.uiStyle") private var uiStyleRaw = BeansUIStyle.liquid.rawValue

    let shape: S

    private var uiStyle: BeansUIStyle {
        uiStyleRaw == "outline" ? .clear : (BeansUIStyle(rawValue: uiStyleRaw) ?? .liquid)
    }

    var body: some View {
        BeansGlass(shape: shape)
    }
}

// MARK: - 通用卡片（跟随全局 UI 样式）

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    @AppStorage("beans.uiStyle") private var uiStyleRaw = BeansUIStyle.liquid.rawValue
    @ViewBuilder var content: () -> Content

    private var uiStyle: BeansUIStyle {
        uiStyleRaw == "outline" ? .clear : (BeansUIStyle(rawValue: uiStyleRaw) ?? .liquid)
    }

    private var isLiquid: Bool {
        uiStyle == .liquid || uiStyle == .nativeClean
    }

    private var resolvedCornerRadius: CGFloat {
        if uiStyle == .compact { return min(cornerRadius, 16) }
        if uiStyle == .nativeClean { return min(cornerRadius, 18) }
        return cornerRadius
    }

    private var resolvedPadding: CGFloat {
        if uiStyle == .compact { return 12 }
        if uiStyle == .nativeClean { return 13 }
        return 16
    }

    var body: some View {
        if isLiquid {
            if #available(iOS 26, *) {
                GlassEffectContainer {
                    content()
                        .padding(resolvedPadding)
                        .glassEffect(.clear, in: .rect(cornerRadius: resolvedCornerRadius))
                }
                .beansCardShadow(radius: 9, y: 3)
            } else {
                content()
                    .padding(resolvedPadding)
                    .background(RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous).fill(.ultraThinMaterial))
                    .clipShape(RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous))
                    .beansCardShadow(radius: 9, y: 3)
            }
        } else {
            content()
                .padding(resolvedPadding)
                .background {
                    RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
                        .fill(uiStyle == .compact ? Color.beansGlassFill.opacity(0.72) : Color.clear)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous))
                }
                .clipShape(RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous))
                .beansCardShadow(radius: 9, y: 3)
        }
    }
}

/// 播放/暂停图标切换过渡：iOS 17+ 使用符号替换动画，低版本回退透明度过渡
struct BeansSymbolReplace: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content.contentTransition(.symbolEffect(.replace))
        } else if #available(iOS 16, *) {
            content.contentTransition(.opacity)
        } else {
            content
        }
    }
}

/// 播放/暂停 morph 图标：三角播放态与双竖线暂停态共享一个固定画布，避免按钮尺寸跳动。
struct PlayPauseMorphIcon: View {
    let isPlaying: Bool
    var size: CGFloat = 22

    private var progress: CGFloat { isPlaying ? 1 : 0 }

    var body: some View {
        ZStack {
            Image(systemName: "play.fill")
                .font(.system(size: size, weight: .semibold))
                .opacity(1 - progress)
                .scaleEffect(1 - progress * 0.18)
                .offset(x: progress * 5)
            HStack(spacing: max(3, size * 0.18)) {
                RoundedRectangle(cornerRadius: max(1.5, size * 0.08), style: .continuous)
                    .frame(width: max(4, size * 0.24), height: size * 0.86)
                RoundedRectangle(cornerRadius: max(1.5, size * 0.08), style: .continuous)
                    .frame(width: max(4, size * 0.24), height: size * 0.86)
            }
            .opacity(progress)
            .scaleEffect(0.82 + progress * 0.18)
            .offset(x: (1 - progress) * -5)
        }
        .frame(width: size + 6, height: size + 6)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isPlaying)
    }
}


// MARK: - iOS 15 兼容包装（低版本自动降级）

/// iOS 16+ 使用 NavigationStack，iOS 15 回退 NavigationView（堆栈样式）
struct BeansNavigationStack<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 16, *) {
            NavigationStack { content() }
        } else {
            NavigationView { content() }.navigationViewStyle(.stack)
        }
    }
}

/// 弹窗尺寸（自定义枚举，避免在低版本引用 iOS 16 类型）
enum BeansDetent {
    case medium
    case large
    case fraction(CGFloat)
    case height(CGFloat)
}

/// 弹窗尺寸与拖拽指示条：iOS 16+ 生效，低版本全屏展示
struct BeansSheetModifier: ViewModifier {
    let detents: [BeansDetent]
    var dragIndicator: Bool?

    @available(iOS 16, *)
    private static func makeDetents(_ detents: [BeansDetent]) -> Set<PresentationDetent> {
        var result: Set<PresentationDetent> = []
        for detent in detents {
            switch detent {
            case .medium: result.insert(.medium)
            case .large: result.insert(.large)
            case .fraction(let f): result.insert(.fraction(f))
            case .height(let h): result.insert(.height(h))
            }
        }
        return result
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16, *) {
            if let dragIndicator {
                content
                    .presentationDetents(Self.makeDetents(detents))
                    .presentationDragIndicator(dragIndicator ? .visible : .hidden)
            } else {
                content
                    .presentationDetents(Self.makeDetents(detents))
            }
        } else {
            content
        }
    }
}

extension View {
    /// iOS 16+ 隐藏滚动条，低版本保持默认
    @ViewBuilder
    func beansScrollIndicatorsHidden() -> some View {
        if #available(iOS 16, *) { self.scrollIndicators(.hidden) } else { self }
    }

    /// iOS 16+ 滚动时收起键盘，低版本保持默认
    @ViewBuilder
    func beansScrollDismissesKeyboard() -> some View {
        if #available(iOS 16, *) { self.scrollDismissesKeyboard(.interactively) } else { self }
    }

    /// iOS 16+ 隐藏滚动内容默认背景，低版本保持默认
    @ViewBuilder
    func beansScrollContentBackgroundHidden() -> some View {
        if #available(iOS 16, *) { self.scrollContentBackground(.hidden) } else { self }
    }

    /// 在歌单、排行榜等详情页底部保留可用的迷你播放器。
    func beansDetailMiniPlayer() -> some View {
        modifier(BeansDetailMiniPlayerModifier())
    }
}

private struct BeansDetailMiniPlayerModifier: ViewModifier {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var theme: ThemeStore
    @ObservedObject private var favorites = FavoritesStore.shared
    @State private var showPlayer = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if player.currentSong != nil {
                    MiniPlayerView(
                        showPlayer: $showPlayer,
                        presentation: .dock
                    )
                    .environmentObject(player.clock)
                    .environmentObject(theme)
                    .environmentObject(favorites)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .fullScreenCover(isPresented: $showPlayer) {
                // 详情页使用与主页相同的播放页容器，确保顶部下拉手势可以关闭播放器。
                BeansNowPlayingPresentation(
                    isPresented: $showPlayer,
                    usesSystemInteractiveDismissal: false
                ) {
                    PlayerView(isPresented: $showPlayer)
                        .environmentObject(auth)
                        .environmentObject(player)
                        .environmentObject(player.clock)
                        .environmentObject(theme)
                        .environmentObject(favorites)
                }
            }
    }
}

// MARK: - 封面图

struct CoverImage: View {
    let url: URL?
    var size: CGFloat
    var cornerRadius: CGFloat = 12
    /// 封面未加载时的提示文字（播放器大封面用：等待开始播放）；nil 显示中性图标
    var emptyHint: String? = nil

    // 布局尺寸完全由外层固定容器决定；AsyncImage 只放在 overlay 中渲染，
    // 图片加载完成与否都不会改变任何布局尺寸（根治"封面加载后错乱"）。
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.beansGlassFill)
            .frame(width: size, height: size)
            .overlay {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                            .frame(width: size, height: size)
                            .clipped()
                    case .failure:
                        placeholderIcon
                    case .empty:
                        if url == nil {
                            // 封面地址为空时：直接显示占位图标，避免一直转圈
                            placeholderIcon
                        } else {
                            ZStack {
                                placeholderIcon
                                ProgressView().tint(Color.beansAmber)
                            }
                        }
                    @unknown default:
                        placeholderIcon
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholderIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.beansGlassFill)
            if let emptyHint {
                Text(emptyHint)
                    .font(BeansFont.appFont(max(11, min(size * 0.09, 15)), .medium))
                    .foregroundStyle(Color.beansComment)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
            } else {
                // 中性等待图标（不再使用音乐音符）
                Image(systemName: "waveform")
                    .font(.system(size: size * 0.28, weight: .medium))
                    .foregroundStyle(Color.beansComment)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 会员标识小标（SVIP 金色 / VIP 红色）

struct VIPBadgeView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(BeansFont.appFont(9, .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(text == "SVIP" ? Color(red: 0.85, green: 0.62, blue: 0.18) : Color(red: 0.93, green: 0.25, blue: 0.22)))
    }
}

// MARK: - 玻璃图标按钮（清透 + 按压动效）

struct GlassIconButton: View {
    @EnvironmentObject private var theme: ThemeStore
    @AppStorage("beans.uiStyle") private var uiStyleRaw = BeansUIStyle.liquid.rawValue
    let systemName: String
    var size: CGFloat = 44
    var active = false
    var forceLiquid = false
    let action: () -> Void

    private var isNativeClean: Bool {
        BeansUIStyle(rawValue: uiStyleRaw) == .nativeClean
    }

    var body: some View {
        let _ = theme.accent
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * (isNativeClean ? 0.42 : 0.38), weight: .semibold))
                .foregroundStyle(active ? Color.beansAmber : (isNativeClean ? Color.primary : Color.beansLabel))
                .frame(width: size, height: size)
                .background {
                    if isNativeClean && !forceLiquid {
                        Circle().fill(active ? Color.beansAmber.opacity(0.12) : .clear)
                    } else {
                        BeansGlass(shape: Circle())
                    }
                }
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(GlassPressButtonStyle())
    }
}

// MARK: - 玻璃按钮（清透 + 按压动效）

struct GlassButton: View {
    @EnvironmentObject private var theme: ThemeStore
    @AppStorage("beans.uiStyle") private var uiStyleRaw = BeansUIStyle.liquid.rawValue
    let title: String
    var systemName: String?
    var prominent = false
    let action: () -> Void

    private var isNativeClean: Bool {
        BeansUIStyle(rawValue: uiStyleRaw) == .nativeClean
    }

    var body: some View {
        let _ = theme.accent
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemName {
                    Image(systemName: systemName)
                }
                Text(LocalizedStringKey(title))
            }
            .font(BeansFont.appFont(15, .semibold))
            .foregroundStyle(prominent ? Color.white : Color.beansLabel)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background {
                if prominent {
                    ZStack {
                        BeansGlass(shape: Capsule(), forceLiquid: true)
                        Capsule().fill(Color.beansAmber.opacity(0.78))
                    }
                } else if isNativeClean {
                    Capsule().fill(Color.primary.opacity(0.055))
                } else {
                    Capsule().fill(.thinMaterial)
                }
            }
            .overlay {
                if isNativeClean && !prominent {
                    Capsule().strokeBorder(Color.primary.opacity(0.075), lineWidth: 0.7)
                }
            }
            .clipShape(Capsule())
        }
        .buttonStyle(GlassPressButtonStyle())
    }
}

// MARK: - 区块标题

struct SectionHeader: View {
    @AppStorage("beans.uiStyle") private var uiStyleRaw = BeansUIStyle.liquid.rawValue
    let title: String
    var trailing: String?
    var titleColor: Color = Color.beansLabel
    var trailingColor: Color = Color.beansComment
    var onTrailingTap: (() -> Void)?

    private var isNativeClean: Bool {
        BeansUIStyle(rawValue: uiStyleRaw) == .nativeClean
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(BeansFont.appFont(isNativeClean ? 26 : 21, .bold))
                .foregroundStyle(titleColor)
            Spacer()
            if let trailing {
                Button {
                    onTrailingTap?()
                } label: {
                    HStack(spacing: 3) {
                        Text(LocalizedStringKey(trailing))
                            .font(BeansFont.appFont(13, .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(trailingColor)
                }
                .buttonStyle(GlassPressButtonStyle(scale: 0.9))
            }
        }
    }
}

// MARK: - 空态 / 错误 / 加载

struct EmptyStateView: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.beansComment)
            Text(LocalizedStringKey(text))
                .font(BeansFont.appFont(14))
                .foregroundStyle(Color.beansComment)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.beansComment)
            Text(message)
                .font(BeansFont.appFont(14))
                .foregroundStyle(Color.beansComment)
                .multilineTextAlignment(.center)
            GlassButton(title: "重试", systemName: "arrow.clockwise", action: retry)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

struct LoadingStateView: View {
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        let _ = theme.accent
        ProgressView()
            .controlSize(.large)
            .tint(Color.beansAmber)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }
}

// MARK: - 二维码

struct QRCodeView: View {
    let text: String
    var size: CGFloat = 220

    var body: some View {
        if let image = Self.generateQR(from: text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            EmptyView()
        }
    }

    private static func generateQR(from text: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - 当前播放指示（均衡器动效）

struct NowPlayingIndicator: View {
    @EnvironmentObject private var theme: ThemeStore
    @State private var animating = false

    var body: some View {
        let _ = theme.accent
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(Color.beansAmber)
                    .frame(width: 3, height: animating ? 14 : 5)
                    .animation(
                        .easeInOut(duration: 0.35)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.12),
                        value: animating
                    )
            }
        }
        .frame(height: 16)
        .onAppear { animating = true }
        .onDisappear { animating = false }
    }
}

// MARK: - 播放进度线（迷你播放器用）

struct ProgressLine: View {
    @EnvironmentObject private var theme: ThemeStore
    let progress: Double
    let duration: Double

    private var ratio: Double {
        guard duration > 0.001 else { return 0 }
        return min(max(progress / duration, 0), 1)
    }

    var body: some View {
        let _ = theme.accent
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.beansComment.opacity(0.25))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.beansAmber, Color.beansAmber.opacity(0.5)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(geo.size.width * ratio, 6))
                    .shadow(color: Color.beansAmber.opacity(0.5), radius: 3, y: 1)
                    .overlay(alignment: .trailing) {
                        ZStack {
                            // 柔圆光晕（替代生硬方边阴影）
                            Circle()
                                .fill(Color.beansAmber.opacity(0.45))
                                .blur(radius: 4)
                                .frame(width: 14, height: 14)
                            Circle()
                                .fill(Color.beansAmber)
                                .frame(width: 5, height: 5)
                                .shadow(color: Color.beansAmber.opacity(0.8), radius: 2)
                        }
                    }
            }
        }
    }
}
// MARK: - 板块进入动画（首页错落渐入，纯视觉不影响布局）

struct SectionEntrance: ViewModifier {
    @State private var appeared = false
    var delay: Double = 0

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(delay)) {
                    appeared = true
                }
            }
    }
}

extension View {
    /// 页面内板块错落渐入：opacity + 轻微上移，不影响布局
    func sectionEntrance(delay: Double = 0) -> some View {
        modifier(SectionEntrance(delay: delay))
    }
}

// MARK: - 全局轻提示（Toast，收藏/歌单等操作反馈用）

@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    @Published var message: String?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ text: String, duration: Double = 2.2) {
        dismissTask?.cancel()
        message = text
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}

struct ToastView: View {
    @ObservedObject var center: ToastCenter
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        let _ = theme.accent
        Text(center.message ?? "")
            .font(BeansFont.appFont(14, .medium))
            .foregroundStyle(Color.beansLabel)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
                    }
            }
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            .padding(.horizontal, 30)
            .padding(.bottom, 92)
            .opacity(center.message == nil ? 0 : 1)
            .offset(y: center.message == nil ? 16 : 0)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: center.message)
            .allowsHitTesting(false)
    }
}
