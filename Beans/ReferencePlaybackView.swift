import SwiftUI
import MediaPlayer

private struct ReferenceLyricCenterKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]

    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct ReferencePlaybackView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var clock: PlaybackClock
    @ObservedObject private var localLibrary = LocalLibraryStore.shared

    let song: Song?
    let lyrics: [LyricLine]
    @Binding var showLyrics: Bool
    let onClose: () -> Void
    let onFavorite: () -> Void
    let onQueue: () -> Void
    let onComments: () -> Void
    let onSleepTimer: () -> Void
    let onAddToLocalPlaylist: () -> Void
    let onDownload: () -> Void
    let onShare: () -> Void
    let onPlayerSettings: () -> Void

    @AppStorage("beans.lyricOffset") private var lyricOffset = 0.0
    @AppStorage("beans.appleMusic.showVolume") private var showVolumeControl = true
    @AppStorage("beans.swipeSwitchSong") private var swipeSwitchSong = true
    @AppStorage("beans.appleMusic.primaryHex") private var primaryHex = ""
    @AppStorage("beans.appleMusic.secondaryHex") private var secondaryHex = ""
    @AppStorage("beans.appleMusic.accentHex") private var accentHex = ""
    @AppStorage("beans.appleMusic.volumeHex") private var volumeHex = ""
    @AppStorage("beans.appleMusic.topY") private var topOffsetY = 0.0
    @AppStorage("beans.appleMusic.coverScale") private var coverScale = 1.0
    @AppStorage("beans.appleMusic.titleY") private var titleOffsetY = 0.0
    @AppStorage("beans.appleMusic.lyricY") private var lyricOffsetY = 0.0
    @AppStorage("beans.appleMusic.controlsY") private var controlsOffsetY = 0.0
    @AppStorage("beans.appleMusic.actionsY") private var actionsOffsetY = 0.0
    @State private var swipeOffset: CGFloat = 0
    @State private var lyricCenters: [UUID: CGFloat] = [:]
    @State private var focusedLyricID: UUID?
    @State private var lyricsViewportHeight: CGFloat = 0
    @State private var isDraggingLyrics = false
    @State private var dismissDragOffset: CGFloat = 0
    @State private var resumeTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CoverBlurBackground(url: song?.coverURL, scheme: .dark)
                    .overlay(Color.black.opacity(0.48))
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topIndicator

                    ZStack {
                        if showLyrics {
                            lyricsPage
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        } else {
                            coverPage(size: geometry.size)
                                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.easeInOut(duration: 0.22), value: showLyrics)

                    playbackControls
                        .padding(.horizontal, 24)
                        .padding(.bottom, max(14, geometry.safeAreaInsets.bottom + 4))
                }
                .offset(y: dismissDragOffset)
                .scaleEffect(1 - min(dismissDragOffset / 900, 0.035))
                .opacity(1 - min(dismissDragOffset / 520, 0.22))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .preferredColorScheme(.dark)
        .background {
            HighRefreshConfigurator()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
        .onDisappear { resumeTask?.cancel() }
    }

    private var topIndicator: some View {
        Capsule()
            .fill(.white.opacity(0.7))
            .frame(width: 42, height: 5)
            .frame(width: 64, height: 29)
            .offset(y: CGFloat(topOffsetY))
            .contentShape(Rectangle())
            .gesture(closeGesture)
            .accessibilityLabel("收起播放器")
    }

    private func coverPage(size: CGSize) -> some View {
        let contentWidth = max(size.width - 64, 0)
        let artworkSize = min(contentWidth, min(size.height * 0.50, 390))

        return VStack(spacing: 0) {
            Spacer(minLength: 8)

            CoverImage(
                url: song?.coverURL,
                size: artworkSize,
                cornerRadius: 18,
                emptyHint: player.isBuffering ? "等待开始播放…" : nil
            )
            .frame(width: artworkSize, height: artworkSize)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.46), radius: 36, y: 18)
            .scaleEffect(player.isPlaying ? 1 : 0.965)
            .scaleEffect(CGFloat(coverScale))
            .animation(.spring(response: 0.36, dampingFraction: 0.84), value: player.isPlaying)

            VStack(spacing: 5) {
                HStack(spacing: 9) {
                    Text(song?.name ?? "未在播放")
                        .font(BeansFont.appFont(22, .bold))
                        .foregroundStyle(primaryColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if song?.isVIP == true {
                        Text("VIP")
                            .font(BeansFont.appFont(9, .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.93, green: 0.25, blue: 0.22), in: Capsule())
                    }
                }
                Text(subtitle)
                    .font(BeansFont.appFont(13.5, .medium))
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: 420)
            .padding(.top, 22)
            .offset(y: CGFloat(titleOffsetY))

            MiniLyricsPreview(lines: previewLyrics, primary: primaryColor, secondary: secondaryColor) {
                guard !lyrics.isEmpty else { return }
                BeansHaptics.tap()
                showLyrics = true
            }
            .padding(.top, 18)
            .offset(y: CGFloat(lyricOffsetY))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .offset(x: swipeOffset)
        .opacity(1 - min(abs(swipeOffset) / 260, 0.35))
        .gesture(swipeGesture)
    }

    private var lyricsPage: some View {
        VStack(spacing: 0) {
            lyricsHeader
                .padding(.horizontal, 24)
                .padding(.bottom, 10)

            if lyrics.isEmpty {
                emptyLyricsView
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 26) {
                            Color.clear.frame(height: max(88, lyricsViewportHeight * 0.30))
                            ForEach(lyrics) { line in
                                lyricLine(line, isFocused: line.id == currentVisualLyricID)
                                    .id(line.id)
                                    .background {
                                        GeometryReader { rowGeometry in
                                            Color.clear.preference(
                                                key: ReferenceLyricCenterKey.self,
                                                value: [line.id: rowGeometry.frame(in: .named("referenceLyricsViewport")).midY]
                                            )
                                        }
                                    }
                            }
                            Color.clear.frame(height: max(110, lyricsViewportHeight * 0.34))
                        }
                        .padding(.horizontal, 28)
                    }
                    .coordinateSpace(name: "referenceLyricsViewport")
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black, location: 0.12),
                                .init(color: .black, location: 0.84),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .background {
                        GeometryReader { viewport in
                            Color.clear
                                .onAppear { lyricsViewportHeight = viewport.size.height }
                                .onChange(of: viewport.size.height) { lyricsViewportHeight = $0 }
                        }
                    }
                    .onPreferenceChange(ReferenceLyricCenterKey.self) { centers in
                        lyricCenters = centers
                        updateFocusedLyric(from: centers)
                    }
                    .simultaneousGesture(lyricsDragGesture(proxy: proxy))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                            scrollToPlaybackLyric(proxy: proxy, animated: false)
                        }
                    }
                    .onChange(of: currentPlaybackLyricID) { _ in
                        guard !isDraggingLyrics else { return }
                        scrollToPlaybackLyric(proxy: proxy, animated: true)
                    }
                }
            }
        }
        .gesture(swipeGesture)
    }

    private var lyricsHeader: some View {
        HStack(spacing: 12) {
            Button {
                BeansHaptics.tap()
                showLyrics = false
            } label: {
                CoverImage(url: song?.coverURL, size: 48, cornerRadius: 10)
                    .shadow(color: .black.opacity(0.26), radius: 9, y: 4)
            }
            .buttonStyle(GlassPressButtonStyle(scale: 0.94))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(song?.name ?? "未在播放")
                        .font(BeansFont.appFont(15, .semibold))
                        .foregroundStyle(primaryColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(subtitle)
                    .font(BeansFont.appFont(12, .medium))
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                compactActionButton(
                    icon: localLibrary.containsSong(song) ? "heart.fill" : "heart",
                    active: localLibrary.containsSong(song)
                ) {
                    onFavorite()
                }
                Menu {
                    Button("评论", action: onComments)
                    Button("定时关闭", action: onSleepTimer)
                    Button("添加到本地歌单", action: onAddToLocalPlaylist)
                    Button("下载歌曲", action: onDownload)
                    Button("分享歌曲", action: onShare)
                    Button("播放器设置", action: onPlayerSettings)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(primaryColor.opacity(0.78))
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
            }
        }
    }

    private var playbackControls: some View {
        VStack(spacing: 15) {
            ReferenceScrubber()
            HStack(spacing: 28) {
                Button {
                    BeansHaptics.tap()
                    player.previous()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 25, weight: .semibold))
                }
                .buttonStyle(.plain)

                Button {
                    BeansHaptics.tap()
                    player.togglePlayPause()
                } label: {
                    PlayPauseMorphIcon(isPlaying: player.isPlaying, size: 24)
                        .frame(width: 66, height: 66)
                        .foregroundStyle(primaryColor)
                }
                .buttonStyle(GlassPressButtonStyle(scale: 0.92))

                Button {
                    BeansHaptics.tap()
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 25, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(primaryColor)
            .frame(maxWidth: 320)
            .offset(y: CGFloat(controlsOffsetY))

            if showVolumeControl {
                ReferenceVolumeControl(accent: volumeColor, secondary: secondaryColor)
                    .frame(maxWidth: 420)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 48) {
                referenceActionButton(icon: "quote.bubble", active: showLyrics) {
                    guard !lyrics.isEmpty else { return }
                    showLyrics.toggle()
                }
                referenceActionButton(icon: player.playMode.icon, active: player.playMode == .shuffle) {
                    player.togglePlayMode()
                }
                referenceActionButton(icon: "list.bullet") {
                    onQueue()
                }
            }
            .frame(maxWidth: 420)
            .offset(y: CGFloat(actionsOffsetY))
        }
        .gesture(commentsGesture)
    }

    private func referenceActionButton(icon: String, active: Bool = false, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button {
            BeansHaptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(active ? accentColor : primaryColor.opacity(0.78))
                .frame(width: 58, height: 58)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func compactActionButton(icon: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            BeansHaptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(active ? accentColor : primaryColor.opacity(0.78))
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyLyricsView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "quote.bubble")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.42))
            Text("暂无歌词")
                .font(BeansFont.appFont(15, .semibold))
                .foregroundStyle(.white.opacity(0.86))
            Text("点击封面区域返回歌曲页面")
                .font(BeansFont.appFont(12))
                .foregroundStyle(.white.opacity(0.46))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            BeansHaptics.tap()
            showLyrics = false
        }
    }

    private var previewLyrics: [LyricLine] {
        guard !lyrics.isEmpty else { return [] }
        let current = currentPlaybackLyricIndex ?? 0
        let start = max(current - 1, 0)
        let end = min(start + 3, lyrics.count)
        return Array(lyrics[start..<end])
    }

    private var currentPlaybackLyricIndex: Int? {
        guard !lyrics.isEmpty else { return nil }
        let progress = LyricTiming.effectiveProgress(clock.progress, userOffset: lyricOffset)
        var low = 0
        var high = lyrics.count - 1
        var answer: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lyrics[mid].time <= progress {
                answer = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return answer
    }

    private var currentPlaybackLyricID: UUID? {
        guard let index = currentPlaybackLyricIndex, lyrics.indices.contains(index) else { return nil }
        return lyrics[index].id
    }

    private var currentVisualLyricID: UUID? {
        isDraggingLyrics ? focusedLyricID : (focusedLyricID ?? currentPlaybackLyricID)
    }

    private var subtitle: String {
        guard let song else { return "" }
        let parts = [song.artists, song.album].filter { !$0.isEmpty }
        return parts.isEmpty ? "未知歌曲" : parts.joined(separator: " · ")
    }

    private func lyricLine(_ line: LyricLine, isFocused: Bool) -> some View {
        Button {
            BeansHaptics.tap()
            player.seek(to: LyricTiming.seekTime(for: line, userOffset: lyricOffset))
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(BeansFont.appFont(isFocused ? 27 : 23, isFocused ? .bold : .semibold))
                        .foregroundStyle(primaryColor.opacity(isFocused ? 1 : 0.36))
                        .fixedSize(horizontal: false, vertical: true)
                    if isFocused && isDraggingLyrics {
                        Spacer(minLength: 8)
                        Text(beansTimeString(line.time))
                            .font(BeansFont.appFont(11, .semibold, .monospaced))
                            .foregroundStyle(secondaryColor.opacity(0.82))
                    }
                }
                if isFocused, let translation = line.translation, !translation.isEmpty {
                    Text(translation)
                        .font(BeansFont.appFont(15, .medium))
                        .foregroundStyle(secondaryColor.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .scaleEffect(isFocused ? 1.06 : 0.84, anchor: .leading)
            .blur(radius: isFocused ? 0 : 0.7)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: isFocused)
    }

    private func updateFocusedLyric(from centers: [UUID: CGFloat]) {
        guard lyricsViewportHeight > 0, !centers.isEmpty else { return }
        let center = lyricsViewportHeight / 2
        focusedLyricID = centers.min { abs($0.value - center) < abs($1.value - center) }?.key
    }

    private func scrollToPlaybackLyric(proxy: ScrollViewProxy, animated: Bool) {
        guard let id = currentPlaybackLyricID else { return }
        let action = { proxy.scrollTo(id, anchor: .center) }
        if animated {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.38)) { action() }
        } else {
            action()
        }
    }

    private func lyricsDragGesture(proxy: ScrollViewProxy) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { _ in
                isDraggingLyrics = true
                resumeTask?.cancel()
                updateFocusedLyric(from: lyricCenters)
            }
            .onEnded { _ in
                resumeTask?.cancel()
                if let id = focusedLyricID {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
                resumeTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    guard !Task.isCancelled else { return }
                    isDraggingLyrics = false
                }
            }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                guard swipeSwitchSong else {
                    swipeOffset = 0
                    return
                }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                swipeOffset = value.translation.width
            }
            .onEnded { value in
                guard swipeSwitchSong else {
                    swipeOffset = 0
                    return
                }
                if value.translation.width < -82 {
                    BeansHaptics.medium()
                    player.next()
                } else if value.translation.width > 82 {
                    BeansHaptics.medium()
                    player.previous()
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    swipeOffset = 0
                }
            }
    }

    private var closeGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                guard value.translation.height > 0,
                      value.translation.height > abs(value.translation.width) * 1.15 else { return }
                let raw = value.translation.height
                dismissDragOffset = raw < 120 ? raw : 120 + (raw - 120) * 0.45
            }
            .onEnded { value in
                let translation = max(value.translation.height, 0)
                let prediction = max(value.predictedEndTranslation.height, 0)
                if translation > 110 || prediction > 190 {
                    BeansHaptics.medium()
                    withAnimation(.interactiveSpring(response: 0.48, dampingFraction: 0.86, blendDuration: 0.08)) {
                        dismissDragOffset = max(translation, 180)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                        onClose()
                    }
                } else {
                    withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.72, blendDuration: 0.04)) {
                        dismissDragOffset = 0
                    }
                }
            }
    }

    private var commentsGesture: some Gesture {
        DragGesture(minimumDistance: 25)
            .onEnded { value in
                guard value.translation.height < -54, abs(value.translation.height) > abs(value.translation.width) else { return }
                BeansHaptics.medium()
                onComments()
            }
    }

    private var primaryColor: Color {
        if primaryHex.hasPrefix("#"), let color = Color(hex: primaryHex) { return color }
        return .white
    }

    private var secondaryColor: Color {
        if secondaryHex.hasPrefix("#"), let color = Color(hex: secondaryHex) { return color }
        return .white.opacity(0.58)
    }

    private var accentColor: Color {
        if accentHex.hasPrefix("#"), let color = Color(hex: accentHex) { return color }
        return Color(red: 1.0, green: 0.28, blue: 0.36)
    }

    private var volumeColor: Color {
        if volumeHex.hasPrefix("#"), let color = Color(hex: volumeHex) { return color }
        return primaryColor
    }
}

private struct ReferenceScrubber: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var clock: PlaybackClock
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let total = max(max(clock.duration, player.currentSong?.duration ?? 0), 1)
                let progress = min(max((scrubbing ? scrubValue : clock.progress) / total, 0), 1)
                let width = geometry.size.width

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.18))
                        .frame(height: 4)
                    Capsule()
                        .fill(.white.opacity(0.88))
                        .frame(width: width * progress, height: 4)
                    Circle()
                        .fill(.white)
                        .frame(width: scrubbing ? 18 : 12, height: scrubbing ? 18 : 12)
                        .shadow(color: .white.opacity(scrubbing ? 0.55 : 0.28), radius: scrubbing ? 10 : 3)
                        .offset(x: max(0, min(width - (scrubbing ? 18 : 12), width * progress - (scrubbing ? 9 : 6))))
                }
                .frame(height: 30)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !scrubbing {
                                scrubValue = clock.progress
                                BeansHaptics.medium()
                            }
                            scrubbing = true
                            scrubValue = min(max(value.location.x / max(width, 1), 0), 1) * total
                        }
                        .onEnded { _ in
                            player.seek(to: scrubValue)
                            scrubbing = false
                            BeansHaptics.tap()
                        }
                )
                .overlay(alignment: .topLeading) {
                    if scrubbing {
                        Text(beansTimeString(scrubValue))
                            .font(BeansFont.appFont(11, .semibold, .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.44), in: Capsule())
                            .offset(x: max(0, min(width - 62, width * progress - 31)), y: -28)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }
                }
            }
            .frame(height: 30)

            HStack {
                Text(beansTimeString(scrubbing ? scrubValue : clock.progress))
                Spacer()
                Text(beansTimeString(max(clock.duration, player.currentSong?.duration ?? 0)))
            }
            .font(BeansFont.appFont(11, .regular, .monospaced))
            .foregroundStyle(.white.opacity(0.52))
        }
        .frame(maxWidth: 420)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: scrubbing)
    }
}

private struct ReferenceVolumeControl: View {
    let accent: Color
    let secondary: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(secondary.opacity(0.84))
            ReferenceSystemVolumeView(accent: accent, secondary: secondary)
                .frame(height: 32)
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(secondary.opacity(0.84))
        }
        .frame(height: 34)
    }
}

private struct ReferenceSystemVolumeView: UIViewRepresentable {
    let accent: Color
    let secondary: Color

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        styleVolumeSlider(in: view)
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        styleVolumeSlider(in: uiView)
    }

    private func styleVolumeSlider(in view: MPVolumeView) {
        let applyStyle = {
            let sliders = allSubviews(in: view).compactMap { $0 as? UISlider }
            sliders.forEach { slider in
                slider.minimumTrackTintColor = UIColor(accent.opacity(0.88))
                slider.maximumTrackTintColor = UIColor(secondary.opacity(0.32))
                slider.thumbTintColor = UIColor(accent)
            }
        }

        // MPVolumeView creates its internal slider during layout, so apply the tint once more after it settles.
        applyStyle()
        DispatchQueue.main.async {
            applyStyle()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                applyStyle()
            }
        }
    }

    private func allSubviews(in view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap { allSubviews(in: $0) }
    }
}

private struct MiniLyricsPreview: View {
    let lines: [LyricLine]
    let primary: Color
    let secondary: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                if lines.isEmpty {
                    Text("暂无歌词")
                        .font(BeansFont.appFont(15, .semibold))
                        .foregroundStyle(secondary.opacity(0.54))
                } else {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(BeansFont.appFont(index == 1 ? 17 : 15, index == 1 ? .semibold : .medium))
                            .foregroundStyle((index == 1 ? primary : secondary).opacity(index == 1 ? 0.86 : 0.5))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
            }
            .frame(maxWidth: 420, minHeight: 92)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
