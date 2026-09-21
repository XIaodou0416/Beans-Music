import SwiftUI
import MediaPlayer
import UIKit

private struct ReferenceLyricCenterKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]

    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct ReferencePlaybackPresentationMetrics {
    static let headerTopSpacing: CGFloat = 20
}

struct ReferencePlaybackView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var clock: PlaybackClock
    @EnvironmentObject private var favorites: FavoritesStore
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var localLibrary = LocalLibraryStore.shared
    @ObservedObject private var appleLayout = AppleMusicLayoutStore.shared
    @ObservedObject private var customCovers = CustomSongCoverStore.shared
    @ObservedObject private var dynamicWallpaper = DynamicWallpaperStore.shared

    let song: Song?
    let lyrics: [LyricLine]
    @Binding var showLyrics: Bool
    @Binding var showQueue: Bool
    let onFavorite: () -> Void
    let onComments: () -> Void
    let onSleepTimer: () -> Void
    let onAddToLocalPlaylist: () -> Void
    let onDownload: () -> Void
    let onPlayerSettings: () -> Void
    let onArtist: () -> Void

    @AppStorage("beans.lyricOffset") private var lyricOffset = 0.0
    @AppStorage("beans.appleMusic.showVolume") private var showVolumeControl = false
    @AppStorage("beans.appleMusic.primaryHex") private var primaryHex = ""
    @AppStorage("beans.appleMusic.secondaryHex") private var secondaryHex = ""
    @AppStorage("beans.appleMusic.accentHex") private var accentHex = ""
    @AppStorage("beans.appleMusic.volumeHex") private var volumeHex = ""
    @AppStorage("beans.appleMusic.syncWallpaper") private var syncWallpaper = false
    @AppStorage("beans.appleMusic.wallpaperBlur") private var wallpaperBlur = 14.0
    @AppStorage("beans.showSongVIPBadge") private var showSongVIPBadge = true
    @AppStorage("beans.appleMusic.showLyricPreview") private var showLyricPreview = true
    @AppStorage(BeansBackendSettings.downloadUnlockKey) private var downloadFeatureUnlocked = false
    @State private var lyricCenters: [UUID: CGFloat] = [:]
    @State private var focusedLyricID: UUID?
    @State private var selectedLyricID: UUID?
    @State private var lyricsViewportHeight: CGFloat = 0
    @State private var isDraggingLyrics = false
    @State private var resumeTask: Task<Void, Never>?
    @State private var lyricTapTask: Task<Void, Never>?
    @State private var showCustomCoverPicker = false

    init(
        song: Song?,
        lyrics: [LyricLine],
        showLyrics: Binding<Bool>,
        showQueue: Binding<Bool>,
        onFavorite: @escaping () -> Void,
        onComments: @escaping () -> Void,
        onSleepTimer: @escaping () -> Void,
        onAddToLocalPlaylist: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onPlayerSettings: @escaping () -> Void,
        onArtist: @escaping () -> Void = {}
    ) {
        self.song = song
        self.lyrics = lyrics
        self._showLyrics = showLyrics
        self._showQueue = showQueue
        self.onFavorite = onFavorite
        self.onComments = onComments
        self.onSleepTimer = onSleepTimer
        self.onAddToLocalPlaylist = onAddToLocalPlaylist
        self.onDownload = onDownload
        self.onPlayerSettings = onPlayerSettings
        self.onArtist = onArtist
    }

    private func layoutEntry(_ part: AppleMusicLayoutPart) -> PlayerLayoutEntry {
        appleLayout.entry(for: part)
    }

    private var displayCoverURL: URL? {
        customCovers.url(for: song) ?? song?.coverURL
    }

    private func displayCoverURL(for song: Song?) -> URL? {
        customCovers.url(for: song) ?? song?.coverURL
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                playerBackground

                VStack(spacing: 0) {
                    Color.clear.frame(height: ReferencePlaybackPresentationMetrics.headerTopSpacing)

                    ZStack {
                        if showQueue {
                            compactQueuePage
                                .transition(.opacity)
                        } else if showLyrics {
                            lyricsPage
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                ))
                        } else {
                            coverPage(size: geometry.size)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                ))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.easeInOut(duration: 0.22), value: showLyrics)
                    .animation(.easeInOut(duration: 0.22), value: showQueue)

                    playbackControls(bottomInset: geometry.safeAreaInsets.bottom)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background {
            HighRefreshConfigurator()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
        .onDisappear {
            resumeTask?.cancel()
            lyricTapTask?.cancel()
        }
        .sheet(isPresented: $showCustomCoverPicker) {
            CustomSongCoverPicker(
                onPick: { url in
                    showCustomCoverPicker = false
                    saveCustomCover(from: url)
                },
                onCancel: { showCustomCoverPicker = false }
            )
        }
    }

    @ViewBuilder
    private var playerBackground: some View {
        ZStack {
            // Full-screen covers need an opaque base so the home page cannot show through
            // while the cover image is loading or when a presentation uses a clear surface.
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            if dynamicWallpaper.syncsDynamicWallpaperToPlayer {
                BeansDynamicWallpaperView(forPlayer: true)
                    .ignoresSafeArea()
            } else if syncWallpaper, let image = theme.customBackgroundImage(for: colorScheme) {
                WallpaperImage(image: image)
                    .blur(radius: CGFloat(wallpaperBlur))
                    .scaleEffect(wallpaperBlur > 0 ? 1.08 : 1)
                    .overlay(Color.black.opacity(colorScheme == .dark ? 0.44 : 0.16))
                    .ignoresSafeArea()
            } else if syncWallpaper, let color = theme.customBackground(for: colorScheme) {
                LinearGradient(
                    colors: [color.opacity(0.92), color.opacity(0.58), colorScheme == .dark ? .black.opacity(0.88) : .white.opacity(0.70)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blur(radius: CGFloat(wallpaperBlur * 0.35))
                .ignoresSafeArea()
            } else {
                CoverBlurBackground(url: displayCoverURL, scheme: colorScheme)
                    .overlay(Color.black.opacity(colorScheme == .dark ? 0.48 : 0.14))
                    .ignoresSafeArea()
            }
        }
    }

    private func coverPage(size: CGSize) -> some View {
        let contentWidth = max(size.width - 64, 0)
        let artworkSize = min(contentWidth, min(size.height * 0.50, 390))

        return VStack(spacing: 0) {
            Spacer(minLength: 8)

            CoverImage(
                url: displayCoverURL,
                size: artworkSize,
                cornerRadius: 18,
                emptyHint: player.isBuffering ? "等待开始播放…" : nil,
                playsCoverVideoAudio: true
            )
            .frame(width: artworkSize, height: artworkSize)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.46), radius: 36, y: 18)
            .scaleEffect(player.isPlaying ? 1 : 0.965)
            .modifier(AppleMusicLayoutTransform(entry: layoutEntry(.cover)))
            .animation(.spring(response: 0.36, dampingFraction: 0.84), value: player.isPlaying)

            if showLyricPreview {
            VStack(spacing: 5) {
                HStack(spacing: 9) {
                Text(song?.name ?? "未在播放")
                    .font(BeansFont.appFont(22, .bold))
                    .foregroundStyle(primaryColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contextMenu {
                        Button("复制歌名") {
                            copySongTitle()
                        }
                    }
                    if showSongVIPBadge, song?.isVIP == true {
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
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onArtist)
            }
            .frame(maxWidth: 420)
            .padding(.top, 22)
            .modifier(AppleMusicLayoutTransform(entry: layoutEntry(.title)))

            MiniLyricsPreview(lines: previewLyrics, primary: primaryColor, secondary: secondaryColor) {
                BeansHaptics.tap()
                showLyrics = true
            }
            .padding(.top, 18)
            .modifier(AppleMusicLayoutTransform(entry: layoutEntry(.previewLyric)))
            } else {
                compactTrackHeader
                    .padding(.top, 22)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
    }

    private var compactTrackHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(song?.name ?? "未在播放")
                    .font(BeansFont.appFont(16, .semibold))
                    .foregroundStyle(primaryColor)
                    .lineLimit(1)
                    .contextMenu {
                        Button("复制歌名") {
                            copySongTitle()
                        }
                    }
                Text(subtitle)
                    .font(BeansFont.appFont(12, .medium))
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onArtist)
            }
            Spacer(minLength: 0)
            favoriteActionButton()
            Menu {
                Button("定时关闭", action: onSleepTimer)
                Button("添加到本地歌单", action: onAddToLocalPlaylist)
                customCoverActions
                if downloadFeatureUnlocked {
                    Button("下载歌曲", action: onDownload)
                }
                Button("播放器设置", action: onPlayerSettings)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(primaryColor.opacity(0.78))
                    .frame(width: 38, height: 38)
            }
        }
        .frame(maxWidth: 420)
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
                                lyricLine(line, isFocused: line.id == currentVisualLyricID, proxy: proxy)
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
    }

    private var lyricsHeader: some View {
        HStack(spacing: 12) {
            Button {
                BeansHaptics.tap()
                showLyrics = false
            } label: {
                CoverImage(url: displayCoverURL, size: 48, cornerRadius: 10)
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
                        .contextMenu {
                            Button("复制歌名") {
                                copySongTitle()
                            }
                        }
                }
                Text(subtitle)
                    .font(BeansFont.appFont(12, .medium))
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onArtist)
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                favoriteActionButton()
                Menu {
                    Button("定时关闭", action: onSleepTimer)
                    Button("添加到本地歌单", action: onAddToLocalPlaylist)
                    customCoverActions
                    if downloadFeatureUnlocked {
                        Button("下载歌曲", action: onDownload)
                    }
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

    private func playbackControls(bottomInset: CGFloat) -> some View {
        AppleMusicPlaybackControls(
            bottomInset: bottomInset,
            primary: primaryColor,
            secondary: secondaryColor,
            accent: accentColor,
            volumeColor: volumeColor,
            showVolume: showVolumeControl,
            lyricsActive: showLyrics,
            queueActive: showQueue,
            layout: AppleMusicPlaybackControlLayout(
                progress: layoutEntry(.progress),
                previous: layoutEntry(.previous),
                play: layoutEntry(.play),
                next: layoutEntry(.next),
                volume: layoutEntry(.volume),
                actions: layoutEntry(.actions),
                container: PlayerLayoutEntry()
            ),
            onLyrics: {
                withAnimation(.easeInOut(duration: 0.22)) {
                    if showQueue {
                        showQueue = false
                        showLyrics = true
                    } else {
                        showLyrics.toggle()
                    }
                }
            },
            onQueue: {
                withAnimation(.easeInOut(duration: 0.22)) {
                    showQueue.toggle()
                }
            },
            onComments: onComments
        )
    }

    private var compactQueuePage: some View {
        VStack(spacing: 12) {
            compactQueueHeader
            AppleMusicCompactQueueContent()
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 4)
    }

    private var compactQueueHeader: some View {
        HStack(spacing: 11) {
            CoverImage(url: displayCoverURL, size: 46, cornerRadius: 10)
                .shadow(color: .black.opacity(0.26), radius: 9, y: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(song?.name ?? "未在播放")
                    .font(BeansFont.appFont(16, .bold))
                    .foregroundStyle(primaryColor)
                    .lineLimit(1)
                    .contextMenu {
                        Button("复制歌名") {
                            copySongTitle()
                        }
                    }
                Text(song?.artists ?? "")
                    .font(BeansFont.appFont(12, .medium))
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onArtist)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            favoriteActionButton()

            Menu {
                Button("清空播放列表", role: .destructive) {
                    player.clearQueue()
                }
                Divider()
                Button("定时关闭", action: onSleepTimer)
                Button("添加到本地歌单", action: onAddToLocalPlaylist)
                customCoverActions
                if downloadFeatureUnlocked {
                    Button("下载歌曲", action: onDownload)
                }
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

    @ViewBuilder
    private var customCoverActions: some View {
        if let song {
            Button("更换自定义封面") {
                showCustomCoverPicker = true
            }
            if customCovers.isVideoCover(for: song) {
                Toggle(
                    "播放视频封面声音",
                    isOn: Binding(
                        get: { customCovers.videoAudioEnabled(for: customCovers.url(for: song)) },
                        set: { customCovers.setVideoAudioEnabled($0, for: song) }
                    )
                )
            }
            if customCovers.hasCover(for: song) {
                Button("恢复默认封面", role: .destructive) {
                    customCovers.removeCover(for: song)
                    ToastCenter.shared.show("已恢复默认封面")
                }
            }
        }
    }

    private func saveCustomCover(from url: URL) {
        guard let song else { return }
        do {
            try customCovers.saveCover(from: url, for: song)
            try? FileManager.default.removeItem(at: url)
            ToastCenter.shared.show("自定义封面已保存")
        } catch {
            ToastCenter.shared.show(error.localizedDescription)
        }
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
        isDraggingLyrics ? (focusedLyricID ?? currentPlaybackLyricID) : currentPlaybackLyricID
    }

    private var subtitle: String {
        guard let song else { return "" }
        let parts = [song.artists, song.album].filter { !$0.isEmpty }
        return parts.isEmpty ? "未知歌曲" : parts.joined(separator: " · ")
    }

    private func copySongTitle() {
        guard let title = song?.name.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return }
        UIPasteboard.general.string = title
        BeansHaptics.success()
        ToastCenter.shared.show("歌名已复制")
    }

    private func lyricLine(_ line: LyricLine, isFocused: Bool, proxy: ScrollViewProxy) -> some View {
        let isSelected = selectedLyricID == line.id || (isDraggingLyrics && isFocused)
        let visualFocus = isFocused || isSelected
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(line.text.isEmpty ? " " : line.text)
                    .font(BeansFont.appFont(visualFocus ? 27 : 23, visualFocus ? .bold : .semibold))
                    .foregroundStyle(primaryColor.opacity(visualFocus ? 1 : 0.36))
                    .fixedSize(horizontal: false, vertical: true)
                if isSelected {
                    Spacer(minLength: 8)
                    Text(beansTimeString(line.time))
                        .font(BeansFont.appFont(11, .semibold, .monospaced))
                        .foregroundStyle(secondaryColor.opacity(0.82))
                    Button {
                        lyricTapTask?.cancel()
                        playLyric(line, proxy: proxy)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(accentColor)
                            .frame(width: 24, height: 24)
                            .background(accentColor.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if visualFocus, let translation = line.translation, !translation.isEmpty {
                Text(translation)
                    .font(BeansFont.appFont(15, .medium))
                    .foregroundStyle(secondaryColor.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .scaleEffect(visualFocus ? 1.06 : 0.84, anchor: .leading)
        .blur(radius: visualFocus ? 0 : 0.7)
        .onTapGesture {
            scheduleLyricSelection(line.id)
        }
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    lyricTapTask?.cancel()
                    playLyric(line, proxy: proxy)
                }
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: visualFocus)
    }

    private func scheduleLyricSelection(_ id: UUID) {
        lyricTapTask?.cancel()
        lyricTapTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                selectedLyricID = id
            }
            BeansHaptics.tap()
        }
    }

    private func playLyric(_ line: LyricLine, proxy: ScrollViewProxy) {
        selectedLyricID = line.id
        resumeTask?.cancel()
        isDraggingLyrics = false
        focusedLyricID = nil
        BeansHaptics.tap()
        player.seek(to: LyricTiming.seekTime(for: line, userOffset: lyricOffset))
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.3)) {
            proxy.scrollTo(line.id, anchor: .center)
        }
    }

    private func updateFocusedLyric(from centers: [UUID: CGFloat]) {
        guard lyricsViewportHeight > 0, !centers.isEmpty else { return }
        let center = lyricsViewportHeight / 2
        let nextID = centers.min { abs($0.value - center) < abs($1.value - center) }?.key
        focusedLyricID = nextID
        if isDraggingLyrics {
            selectedLyricID = nextID
        }
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

    private func favoriteActionButton() -> some View {
        Button {
            BeansHaptics.tap()
            onFavorite()
        } label: {
            FavoriteHeartView(
                mark: favoriteMark,
                size: 17,
                inactiveColor: primaryColor.opacity(0.78)
            )
            .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
    }

    private var favoriteMark: FavoriteMark {
        guard let song else { return .none }
        let local = localLibrary.containsSong(song)
        let official = favorites.isOfficiallyLiked(song)
        switch (local, official) {
        case (true, true): return .both
        case (true, false): return .local
        case (false, true): return .official
        case (false, false): return .none
        }
    }
}

struct AppleMusicPlaybackControlLayout {
    let progress: PlayerLayoutEntry
    let previous: PlayerLayoutEntry
    let play: PlayerLayoutEntry
    let next: PlayerLayoutEntry
    let volume: PlayerLayoutEntry
    let actions: PlayerLayoutEntry
    let container: PlayerLayoutEntry
}

struct AppleMusicPlaybackControls: View {
    @EnvironmentObject private var player: PlayerManager

    let bottomInset: CGFloat
    let primary: Color
    let secondary: Color
    let accent: Color
    let volumeColor: Color
    let showVolume: Bool
    let lyricsActive: Bool
    let queueActive: Bool
    let layout: AppleMusicPlaybackControlLayout
    let onLyrics: () -> Void
    let onQueue: () -> Void
    let onComments: () -> Void

    var body: some View {
        VStack(spacing: 15) {
            ReferenceScrubber()
                .modifier(AppleMusicLayoutTransform(entry: layout.progress))
                .contentShape(Rectangle())

            VStack(spacing: 15) {
                HStack(spacing: 28) {
                    Button {
                        BeansHaptics.tap()
                        player.previous()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 25, weight: .semibold))
                            .frame(width: 42, height: 42)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .modifier(AppleMusicLayoutTransform(entry: layout.previous))

                    Button {
                        BeansHaptics.tap()
                        player.togglePlayPause()
                    } label: {
                        PlayPauseMorphIcon(isPlaying: player.isPlaying, size: 24)
                            .frame(width: 66, height: 66)
                            .foregroundStyle(primary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(GlassPressButtonStyle(scale: 0.92))
                    .modifier(AppleMusicLayoutTransform(entry: layout.play))

                    Button {
                        BeansHaptics.tap()
                        player.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 25, weight: .semibold))
                            .frame(width: 42, height: 42)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .modifier(AppleMusicLayoutTransform(entry: layout.next))
                }
                .foregroundStyle(primary)
                .frame(maxWidth: 320)

                if showVolume {
                    ReferenceVolumeControl(accent: volumeColor, secondary: secondary)
                        .frame(maxWidth: 420)
                        .modifier(AppleMusicLayoutTransform(entry: layout.volume))
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                HStack(spacing: 44) {
                    actionButton(icon: lyricsActive && !queueActive ? "quote.bubble.fill" : "quote.bubble", active: lyricsActive && !queueActive, action: onLyrics)
                    actionButton(icon: "text.bubble", action: onComments)
                    actionButton(icon: "list.bullet", active: queueActive, action: onQueue)
                }
                .frame(maxWidth: 500)
                .modifier(AppleMusicLayoutTransform(entry: layout.actions))
            }
            .modifier(AppleMusicLayoutTransform(entry: layout.container))
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, max(14, bottomInset + 4))
    }

    private func actionButton(
        icon: String,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            BeansHaptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(active ? accent : primary.opacity(0.78))
                .frame(width: 58, height: 58)
                .background { BeansGlass(shape: Circle(), forceLiquid: true) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

}

struct AppleMusicCompactQueueContent: View {
    @EnvironmentObject private var player: PlayerManager
    @State private var draggingPosition: Int?
    @State private var dragStartPosition: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                modeButton(
                    mode: .sequential,
                    icon: "arrow.right",
                    label: "顺序播放",
                    isActive: player.playMode == .sequential
                )
                modeButton(
                    mode: .shuffle,
                    icon: "shuffle",
                    label: "随机播放",
                    isActive: player.playMode == .shuffle
                )
                modeButton(
                    mode: .repeatAll,
                    icon: "repeat",
                    label: "列表循环",
                    isActive: player.playMode == .repeatAll
                )
                modeButton(
                    mode: .repeatOne,
                    icon: "repeat.1",
                    label: "单曲循环",
                    isActive: player.playMode == .repeatOne
                )
            }
            .frame(maxWidth: .infinity)

            HStack(alignment: .firstTextBaseline) {
                Text("继续播放")
                    .font(BeansFont.appFont(20, .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(player.upcomingQueue.count) 首")
                    .font(BeansFont.appFont(12, .regular, .monospaced))
                    .foregroundStyle(.white.opacity(0.46))
            }

            if player.upcomingQueue.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 28, weight: .light))
                    Text("播放队列是空的")
                        .font(BeansFont.appFont(14, .semibold))
                }
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(player.upcomingQueue.prefix(100).enumerated()), id: \.element.song.identityKey) { position, item in
                            AppleMusicCompactQueueRow(
                                index: item.index,
                                position: position,
                                maxPosition: min(player.upcomingQueue.count, 100) - 1,
                                song: item.song,
                                activePosition: $draggingPosition,
                                startPosition: $dragStartPosition
                            ) { source, destination in
                                player.moveUpcomingQueueItem(from: source, to: destination)
                            }
                        }
                    }
                }
                .mask(
                    LinearGradient(
                        colors: [.black, .black, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .padding(.top, 6)
    }

    private func modeButton(
        mode: PlayMode,
        icon: String,
        label: String,
        isActive: Bool
    ) -> some View {
        Button {
            activate(mode)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isActive ? Color.black.opacity(0.76) : .white.opacity(0.76))
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(
                    isActive ? AnyShapeStyle(.white.opacity(0.66)) : AnyShapeStyle(.white.opacity(0.1)),
                    in: Capsule()
                )
        }
        .buttonStyle(RecordModePressButtonStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func activate(_ mode: PlayMode) {
        BeansHaptics.tap()
        player.setPlayMode(mode)
    }
}

private struct AppleMusicCompactQueueRow: View {
    @EnvironmentObject private var player: PlayerManager
    @ObservedObject private var customCovers = CustomSongCoverStore.shared

    let index: Int
    let position: Int
    let maxPosition: Int
    let song: Song
    @Binding var activePosition: Int?
    @Binding var startPosition: Int?
    let onMove: (Int, Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                BeansHaptics.tap()
                player.playQueueIndex(index)
            } label: {
                HStack(spacing: 11) {
                    CoverImage(url: customCovers.url(for: song) ?? song.coverURL, size: 46, cornerRadius: 8)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.name)
                            .font(BeansFont.appFont(14, .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                        Text(song.artists)
                            .font(BeansFont.appFont(12))
                            .foregroundStyle(.white.opacity(0.48))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Text(song.formattedDuration)
                        .font(BeansFont.appFont(11, .regular, .monospaced))
                        .foregroundStyle(.white.opacity(0.36))
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            QueueReorderHandle(
                position: position,
                maxPosition: maxPosition,
                rowStep: 60,
                activePosition: $activePosition,
                startPosition: $startPosition,
                onMove: onMove
            )
            .foregroundStyle(.white.opacity(0.54))
        }
        .contextMenu {
            Button("从播放列表移除", role: .destructive) {
                player.removeFromQueue(at: index)
            }
        }
        .accessibilityLabel("\(song.name)，\(song.artists)")
    }
}

struct ReferenceScrubber: View {
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
                .highPriorityGesture(
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

struct AppleMusicLyricsSection: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var clock: PlaybackClock
    @AppStorage("beans.lyricKaraokeEnabled") private var karaokeEnabled = true

    let lyrics: [LyricLine]
    let primary: Color
    let secondary: Color
    let lyricOffset: CGFloat
    let onTapLine: (LyricLine) -> Void

    @State private var lyricCenters: [UUID: CGFloat] = [:]
    @State private var focusedLyricID: UUID?
    @State private var selectedLyricID: UUID?
    @State private var viewportHeight: CGFloat = 0
    @State private var isDraggingLyrics = false
    @State private var resumeTask: Task<Void, Never>?
    @State private var lyricTapTask: Task<Void, Never>?

    private var currentPlaybackLyricIndex: Int? {
        guard !lyrics.isEmpty else { return nil }
        let progress = LyricTiming.effectiveProgress(clock.progress, userOffset: Double(lyricOffset))
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
        isDraggingLyrics ? (focusedLyricID ?? currentPlaybackLyricID) : currentPlaybackLyricID
    }

    var body: some View {
        Group {
            if lyrics.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(secondary.opacity(0.5))
                    Text("暂无歌词")
                        .font(BeansFont.appFont(15, .semibold))
                        .foregroundStyle(primary.opacity(0.86))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 26) {
                            Color.clear.frame(height: max(88, viewportHeight * 0.30))
                            ForEach(lyrics) { line in
                                lyricLine(line, isFocused: line.id == currentVisualLyricID, proxy: proxy)
                                    .id(line.id)
                                    .background {
                                        GeometryReader { rowGeometry in
                                            Color.clear.preference(
                                                key: ReferenceLyricCenterKey.self,
                                                value: [line.id: rowGeometry.frame(in: .named("iPadAppleLyricsViewport")).midY]
                                            )
                                        }
                                    }
                            }
                            Color.clear.frame(height: max(110, viewportHeight * 0.34))
                        }
                        .padding(.horizontal, 28)
                    }
                    .coordinateSpace(name: "iPadAppleLyricsViewport")
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
                                .onAppear { viewportHeight = viewport.size.height }
                                .onChange(of: viewport.size.height) { viewportHeight = $0 }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            resumeTask?.cancel()
            lyricTapTask?.cancel()
        }
    }

    private func lyricLine(_ line: LyricLine, isFocused: Bool, proxy: ScrollViewProxy) -> some View {
        let isSelected = selectedLyricID == line.id || (isDraggingLyrics && isFocused)
        let visualFocus = isFocused || isSelected
        let isActive = line.id == currentPlaybackLyricID
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                KaraokeLyricText(
                    line: line,
                    currentTime: LyricTiming.effectiveProgress(clock.progress, userOffset: Double(lyricOffset)),
                    isPlaying: player.isPlaying,
                    isActive: isActive,
                    enabled: karaokeEnabled,
                    font: BeansFont.appFont(visualFocus ? 27 : 23, visualFocus ? .bold : .semibold),
                    style: primary,
                    fallbackOpacity: visualFocus ? 1 : 0.36
                )
                    .fixedSize(horizontal: false, vertical: true)
                if isSelected {
                    Spacer(minLength: 8)
                    Text(beansTimeString(line.time))
                        .font(BeansFont.appFont(11, .semibold, .monospaced))
                        .foregroundStyle(secondary.opacity(0.82))
                    Button {
                        lyricTapTask?.cancel()
                        playLyric(line, proxy: proxy)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(primary)
                            .frame(width: 24, height: 24)
                            .background(primary.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if visualFocus, let translation = line.translation, !translation.isEmpty {
                Text(translation)
                    .font(BeansFont.appFont(15, .medium))
                    .foregroundStyle(secondary.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .scaleEffect(visualFocus ? 1.06 : 0.84, anchor: .leading)
        .blur(radius: visualFocus ? 0 : 0.7)
        .onTapGesture {
            scheduleLyricSelection(line.id)
        }
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    lyricTapTask?.cancel()
                    playLyric(line, proxy: proxy)
                }
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: visualFocus)
    }

    private func scheduleLyricSelection(_ id: UUID) {
        lyricTapTask?.cancel()
        lyricTapTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                selectedLyricID = id
            }
            BeansHaptics.tap()
        }
    }

    private func playLyric(_ line: LyricLine, proxy: ScrollViewProxy) {
        selectedLyricID = line.id
        resumeTask?.cancel()
        isDraggingLyrics = false
        focusedLyricID = nil
        BeansHaptics.tap()
        onTapLine(line)
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.3)) {
            proxy.scrollTo(line.id, anchor: .center)
        }
    }

    private func updateFocusedLyric(from centers: [UUID: CGFloat]) {
        guard viewportHeight > 0, !centers.isEmpty else { return }
        let center = viewportHeight / 2
        let nextID = centers.min { abs($0.value - center) < abs($1.value - center) }?.key
        focusedLyricID = nextID
        if isDraggingLyrics {
            selectedLyricID = nextID
        }
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
                    selectedLyricID = id
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
}

struct ReferenceVolumeControl: View {
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
