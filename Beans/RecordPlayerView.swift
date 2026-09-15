import SwiftUI

// Adapted under LGPL-3.0. See THIRD_PARTY_NOTICES.md.
struct RecordPlayerView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var clock: PlaybackClock
    @Environment(\.colorScheme) private var colorScheme

    let song: Song?
    let lyrics: [LyricLine]
    @Binding var isPresented: Bool
    let layoutData: [String: PlayerLayoutEntry]
    let initialShowsLyrics: Bool
    let isFavorite: Bool
    let onFavorite: () -> Void
    let onComments: () -> Void
    let onSettings: () -> Void
    let onSleepTimer: () -> Void
    let onAddToLocalPlaylist: () -> Void
    let onDownload: () -> Void
    let downloadFeatureUnlocked: Bool

    @State private var showLyrics = false
    @State private var showQueue = false
    @State private var showQualityPicker = false
    @AppStorage("beans.audioQuality") private var playbackQualityRaw = BeansAudioQuality.hires.rawValue

    init(
        song: Song?,
        lyrics: [LyricLine],
        isPresented: Binding<Bool>,
        layoutData: [String: PlayerLayoutEntry] = [:],
        initialShowsLyrics: Bool = false,
        isFavorite: Bool = false,
        onFavorite: @escaping () -> Void,
        onComments: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onSleepTimer: @escaping () -> Void = {},
        onAddToLocalPlaylist: @escaping () -> Void = {},
        onDownload: @escaping () -> Void = {},
        downloadFeatureUnlocked: Bool = false
    ) {
        self.song = song
        self.lyrics = lyrics
        self._isPresented = isPresented
        self.layoutData = layoutData
        self.initialShowsLyrics = initialShowsLyrics
        self.isFavorite = isFavorite
        self.onFavorite = onFavorite
        self.onComments = onComments
        self.onSettings = onSettings
        self.onSleepTimer = onSleepTimer
        self.onAddToLocalPlaylist = onAddToLocalPlaylist
        self.onDownload = onDownload
        self.downloadFeatureUnlocked = downloadFeatureUnlocked
        self._showLyrics = State(initialValue: initialShowsLyrics)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backdrop
                if isPhoneLandscape(size: geometry.size) {
                    landscapeLayout(size: geometry.size)
                } else if geometry.size.width < 720 {
                    compactLayout(size: geometry.size)
                } else {
                    regularLayout(size: geometry.size)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .simultaneousGesture(dismissGesture)
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.22), value: showLyrics)
        .sheet(isPresented: $showQualityPicker) {
            RecordModeQualityPickerSheet(song: song)
                .environmentObject(player)
        }
        .overlay(alignment: .top) {
            recordHeader
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .zIndex(10)
        }
    }

    private var backdrop: some View {
        ZStack {
            CoverBlurBackground(url: song?.coverURL, scheme: colorScheme)
            RadialGradient(
                colors: [.white.opacity(0.12), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 700
            )
            LinearGradient(
                colors: [.clear, .black.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private func compactLayout(size: CGSize) -> some View {
        let artworkDimension = max(150, min(size.width - 72, size.height * 0.43, 310))
        return VStack(spacing: 16) {
            Spacer().frame(height: 34)
            if showQueue {
                recordQueuePage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else if showLyrics {
                lyricsColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else {
                turntable(size: artworkDimension)
                    .modifier(recordLayout(.vinylCover))
                    .frame(maxWidth: .infinity)
                trackMetadata
                    .modifier(recordLayout(.vinylTitle))
                RecordModeMiniLyrics(lyrics: lyrics) {
                    withAnimation(.easeInOut(duration: 0.22)) { showLyrics = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            RecordModeScrubber()
                .padding(.horizontal, 20)
                .modifier(recordLayout(.progress))
            controls
                .padding(.bottom, 20)
                .modifier(recordLayout(.controls))
        }
        .padding(.horizontal, 16)
    }

    private func landscapeLayout(size: CGSize) -> some View {
        let artworkDimension = min(190, max(120, size.height - 175))
        return VStack(spacing: 6) {
            HStack(spacing: 18) {
                if showQueue {
                    recordQueuePage
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                } else if showLyrics {
                    lyricsColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 7) {
                        turntable(size: artworkDimension)
                            .modifier(recordLayout(.vinylCover))
                        trackMetadata
                            .modifier(recordLayout(.vinylTitle))
                    }
                    .frame(maxWidth: .infinity)
                    lyricsColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
            VStack(spacing: 4) {
                RecordModeScrubber()
                    .padding(.horizontal, 24)
                    .modifier(recordLayout(.progress))
                transportControls
                    .frame(maxWidth: 360)
            }
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
    }

    private func regularLayout(size: CGSize) -> some View {
        let artworkDimension = max(180, min(330, size.width * 0.30, size.height - 300))
        return Group {
            if showQueue {
                VStack(spacing: 14) {
                    recordQueuePage
                    RecordModeScrubber()
                        .frame(maxWidth: 380)
                        .modifier(recordLayout(.progress))
                    controls
                        .modifier(recordLayout(.controls))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    VStack(spacing: 22) {
                        Spacer()
                        turntable(size: artworkDimension)
                            .modifier(recordLayout(.vinylCover))
                        trackMetadata
                            .modifier(recordLayout(.vinylTitle))
                        VStack(spacing: 14) {
                            RecordModeScrubber()
                                .frame(maxWidth: 380)
                                .modifier(recordLayout(.progress))
                            controls
                                .modifier(recordLayout(.controls))
                        }
                        Spacer()
                    }
                    .padding(.trailing, 30)
                    .frame(maxWidth: .infinity)
                    lyricsColumn
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 48)
        .padding(.vertical, size.height < 500 ? 24 : 40)
    }

    private func turntable(size: CGFloat) -> some View {
        RecordModeTurntableView(
            coverURL: song?.coverURL,
            isPlaying: player.isPlaying,
            trackId: song?.id,
            size: size,
            onTap: { withAnimation(.easeInOut(duration: 0.22)) { showLyrics = true } },
            onNextTrack: { player.next() },
            onPreviousTrack: { player.previous() }
        )
    }

    private var trackMetadata: some View {
        VStack(spacing: 5) {
            Text(song?.name ?? "")
                .font(BeansFont.appFont(21, .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(song.map { "\($0.artists) — \($0.album)" } ?? "")
                .font(BeansFont.appFont(13.5))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
            Text("来源：\(sourceName)")
                .font(BeansFont.appFont(11))
                .foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 8) {
                metadataButton(title: "音质：\(BeansAudioQuality(rawValue: playbackQualityRaw)?.displayName ?? BeansAudioQuality.hires.displayName)", icon: "waveform") {
                    showQualityPicker = true
                }
                metadataButton(title: "评论", icon: "text.bubble", action: onComments)
            }
        }
        .frame(maxWidth: 400)
    }

    private func metadataButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(BeansFont.appFont(12, .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(.white.opacity(0.12), in: Capsule())
        }
        .buttonStyle(RecordModePressButtonStyle())
    }

    private var sourceName: String {
        switch song?.source {
        case .netease: return "网易云"
        case .qq: return "QQ音乐"
        case .kugou: return "酷狗"
        case nil: return "未知"
        }
    }

    private var controls: some View {
        HStack(spacing: 0) {
            circleButton(icon: player.playMode.icon, size: 14, tint: player.playMode == .sequential ? nil : .red) {
                player.togglePlayMode()
            }
            .frame(maxWidth: .infinity)
            circleButton(icon: "backward.fill", size: 16) { player.previous() }
                .frame(maxWidth: .infinity)
            playPauseButton
                .frame(maxWidth: .infinity)
            circleButton(icon: "forward.fill", size: 16) { player.next() }
                .frame(maxWidth: .infinity)
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    showQueue.toggle()
                    if showQueue {
                        showLyrics = false
                    }
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(RecordModePressButtonStyle())
                .frame(maxWidth: .infinity)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 0) {
            transportButton(icon: "backward.fill", size: 25) { player.previous() }
            transportButton(icon: player.isPlaying ? "pause.fill" : "play.fill", size: 36) {
                player.togglePlayPause()
            }
            transportButton(icon: "forward.fill", size: 25) { player.next() }
        }
        .foregroundStyle(.white)
    }

    private func transportButton(icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: size == 36 ? 64 : 58)
        }
        .buttonStyle(RecordModePressButtonStyle())
    }

    private var playPauseButton: some View {
        Button {
            player.togglePlayPause()
        } label: {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 58, height: 58)
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.black.opacity(0.85))
            }
        }
        .buttonStyle(RecordModePressButtonStyle())
    }

    private func circleButton(
        icon: String,
        size: CGFloat,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(tint ?? .white.opacity(0.8))
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.1), in: Circle())
        }
        .buttonStyle(RecordModePressButtonStyle())
    }

    private var recordQueuePage: some View {
        VStack(spacing: 12) {
            HStack(spacing: 11) {
                CoverImage(url: song?.coverURL, size: 46, cornerRadius: 10)
                    .shadow(color: .black.opacity(0.26), radius: 9, y: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text(song?.name ?? "未在播放")
                        .font(BeansFont.appFont(16, .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(song?.artists ?? "")
                        .font(BeansFont.appFont(12, .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isFavorite ? .red : .white.opacity(0.86))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(RecordModePressButtonStyle())
            }
            .frame(maxWidth: 520)
            AppleMusicCompactQueueContent()
        }
        .padding(.horizontal, 8)
    }

    private var lyricsColumn: some View {
        AppleMusicLyricsSection(
            lyrics: lyrics,
            primary: .white,
            secondary: .white.opacity(0.58),
            lyricOffset: 0
        ) { line in
            player.seekPrecisely(to: LyricTiming.seekTime(for: line, userOffset: 0))
        }
        .padding(.horizontal, 8)
        .modifier(recordLayout(.vinylLyricsText))
    }

    private var recordHeader: some View {
        HStack {
            Menu {
                if showLyrics || showQueue {
                    Button("返回唱片") {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            showLyrics = false
                            showQueue = false
                        }
                    }
                }
                Button("定时关闭", action: onSleepTimer)
                Button("添加到本地歌单", action: onAddToLocalPlaylist)
                if downloadFeatureUnlocked {
                    Button("下载歌曲", action: onDownload)
                }
                Button("播放器设置", action: onSettings)
                Button("关闭播放器", role: .destructive) {
                    isPresented = false
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RecordModePressButtonStyle())
            .accessibilityLabel("更多设置")

            Spacer()

            Button(action: onFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(isFavorite ? .red : .white.opacity(0.88))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RecordModePressButtonStyle())
            .accessibilityLabel(isFavorite ? "取消收藏" : "收藏")
        }
    }

    private func isPhoneLandscape(size: CGSize) -> Bool {
        UIDevice.current.userInterfaceIdiom == .phone && size.width > size.height
    }

    private func recordLayout(_ part: PlayerLayoutPart) -> some ViewModifier {
        RecordModeLayoutTransform(
            entry: layoutData[part.rawValue] ?? VinylPlayerLayoutStore.defaultEntry(for: part)
        )
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard value.translation.height > 70,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                if showLyrics {
                    showLyrics = false
                } else {
                    isPresented = false
                }
            }
    }
}

private struct RecordModeQualityPickerSheet: View {
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.dismiss) private var dismiss

    let song: Song?
    @AppStorage("beans.audioQuality") private var selectedRaw = BeansAudioQuality.hires.rawValue

    var body: some View {
        BeansNavigationStack {
            List {
                Section("当前歌曲") {
                    Text(song?.name ?? "未播放歌曲")
                        .lineLimit(2)
                    Text("可用音质会随当前平台和音源变化")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("选择播放音质") {
                    ForEach(BeansAudioQuality.allCases) { quality in
                        Button {
                            selectedRaw = quality.rawValue
                            player.retryCurrent()
                            dismiss()
                        } label: {
                            HStack {
                                Text(quality.displayName)
                                Spacer()
                                if selectedRaw == quality.rawValue {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.beansAmber)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                        .frame(minHeight: 44)
                    }
                }

                Section {
                    Text("如果选定音质不可用，播放器会自动回退到当前音源支持的较低音质。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("播放音质")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct RecordModeLayoutTransform: ViewModifier {
    let entry: PlayerLayoutEntry

    func body(content: Content) -> some View {
        content
            .scaleEffect(entry.scale)
            .rotationEffect(.degrees(entry.rotation))
            .opacity(entry.opacity)
            .offset(x: entry.x, y: entry.y)
    }
}

private struct RecordModePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct RecordModeMiniLyrics: View {
    @EnvironmentObject private var clock: PlaybackClock

    let lyrics: [LyricLine]
    let onOpen: () -> Void

    private var lines: (previous: LyricLine?, current: LyricLine?, next: LyricLine?) {
        guard !lyrics.isEmpty else { return (nil, nil, nil) }
        let index = lyrics.lastIndex(where: { $0.time <= clock.progress })
        guard let index else { return (nil, nil, lyrics.first) }
        return (
            index > 0 ? lyrics[index - 1] : nil,
            lyrics[index],
            index + 1 < lyrics.count ? lyrics[index + 1] : nil
        )
    }

    var body: some View {
        let visible = lines
        Group {
            if visible.current != nil || visible.next != nil {
                VStack(spacing: 12) {
                    line(visible.previous, emphasized: false)
                    line(visible.current, emphasized: true)
                    line(visible.next, emphasized: false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: visible.current?.id)
            } else {
                Color.clear
            }
        }
    }

    private func line(_ line: LyricLine?, emphasized: Bool) -> some View {
        Text(line?.text.isEmpty == false ? line!.text : " ")
            .font(BeansFont.appFont(emphasized ? 17 : 14, emphasized ? .bold : .medium))
            .foregroundStyle(.white.opacity(emphasized ? 1 : 0.45))
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
            .id(line?.id)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

private struct RecordModeScrubber: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var clock: PlaybackClock
    @State private var isDragging = false
    @State private var dragProgress = 0.0

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let duration = max(clock.duration, player.currentSong?.duration ?? 0)
                let value = isDragging ? dragProgress : clock.progress
                let fraction = duration > 0 ? min(max(value / duration, 0), 1) : 0

                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25)).frame(height: 4)
                    Capsule().fill(.white).frame(width: max(4, width * fraction), height: 4)
                    Circle()
                        .fill(.white)
                        .frame(width: isDragging ? 13 : 9, height: isDragging ? 13 : 9)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .offset(x: max(0, min(width - (isDragging ? 13 : 9), width * fraction - (isDragging ? 6.5 : 4.5))))
                        .opacity(isDragging ? 1 : 0)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            isDragging = true
                            dragProgress = min(max(value.location.x / max(width, 1), 0), 1) * duration
                        }
                        .onEnded { _ in
                            player.seek(to: dragProgress)
                            isDragging = false
                        }
                )
            }
            .frame(height: 14)
            HStack {
                Text(beansTimeString(isDragging ? dragProgress : clock.progress))
                Spacer()
                Text(beansTimeString(max(clock.duration, player.currentSong?.duration ?? 0)))
            }
            .font(BeansFont.appFont(10.5, .regular, .monospaced))
            .foregroundStyle(.white.opacity(0.55))
        }
    }
}

private struct RecordModeTurntableView: View {
    let coverURL: URL?
    let isPlaying: Bool
    let trackId: Int?
    let size: CGFloat
    var onTap: (() -> Void)?
    var onNextTrack: (() -> Void)?
    var onPreviousTrack: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotationState = RecordModeRotationState()
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var isTransitioningTrack = false

    var body: some View {
        let armHeight = size * 0.68
        ZStack(alignment: .top) {
            TimelineView(.animation(
                minimumInterval: 1.0 / 30.0,
                paused: !isPlaying || isDragging || isTransitioningTrack || reduceMotion
            )) { timeline in
                RecordModeDiscView(coverURL: coverURL, size: size)
                    .rotationEffect(.degrees(rotationState.currentAngle(at: timeline.date)))
            }
            .offset(x: dragOffset)
            .padding(.top, armHeight * 0.36)
            .contentShape(Circle())
            .gesture(swipeGesture)
            .onTapGesture { onTap?() }
            .zIndex(1)

            RecordModeTonearmView(
                isPlaying: isPlaying && !isDragging && !isTransitioningTrack,
                height: armHeight,
                reduceMotion: reduceMotion
            )
            .offset(x: size * 0.12, y: -armHeight * 0.08)
            .allowsHitTesting(false)
            .zIndex(2)
        }
        .frame(width: size + 48, height: size + armHeight * 0.38, alignment: .top)
        .onAppear {
            if isPlaying { rotationState.start() }
        }
        .onChange(of: isPlaying) { playing in
            if playing { rotationState.start() } else { rotationState.stop() }
        }
        .onChange(of: trackId) { _ in
            isTransitioningTrack = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 320_000_000)
                isTransitioningTrack = false
            }
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 0.6 else { return }
                isDragging = true
                dragOffset = value.translation.width
            }
            .onEnded { value in
                let translation = value.translation.width
                let predicted = value.predictedEndTranslation.width
                if translation < -45 || predicted < -100 {
                    switchTrack(offset: -size * 1.25, callback: onNextTrack)
                } else if translation > 45 || predicted > 100 {
                    switchTrack(offset: size * 1.25, callback: onPreviousTrack)
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                        dragOffset = 0
                        isDragging = false
                    }
                }
            }
    }

    private func switchTrack(offset: CGFloat, callback: (() -> Void)?) {
        withAnimation(.easeOut(duration: 0.20)) { dragOffset = offset }
        callback?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            dragOffset = offset > 0 ? -size * 1.25 : size * 1.25
            withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
                dragOffset = 0
                isDragging = false
            }
        }
    }
}

private struct RecordModeDiscView: View {
    let coverURL: URL?
    let size: CGFloat

    var body: some View {
        let labelSize = size * 0.64
        let spindleSize = max(7, size * 0.032)
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.42))
                .frame(width: size + 8, height: size + 8)
                .blur(radius: max(8, size * 0.045))
                .offset(y: size * 0.04)
            Circle()
                .fill(RadialGradient(
                    colors: [Color(white: 0.16), Color(white: 0.08), Color(white: 0.025)],
                    center: .center,
                    startRadius: size * 0.08,
                    endRadius: size * 0.52
                ))
                .frame(width: size, height: size)
                .overlay {
                    Circle().stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.28), .white.opacity(0.04), .black.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
                }
            Circle()
                .fill(AngularGradient(
                    gradient: Gradient(colors: [
                        .white.opacity(0.04), .white.opacity(0.16), .black.opacity(0.16),
                        .white.opacity(0.11), .black.opacity(0.12), .white.opacity(0.05)
                    ]),
                    center: .center
                ))
                .frame(width: size - 4, height: size - 4)
                .opacity(0.9)
            ForEach(0..<18, id: \.self) { index in
                let factor = 0.68 + (Double(index) / 17) * 0.29
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(index % 4 == 0 ? 0.14 : 0.06),
                                .black.opacity(0.42),
                                .white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: index % 4 == 0 ? 0.8 : 0.45
                    )
                    .frame(width: size * factor, height: size * factor)
            }
            Circle()
                .fill(AngularGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.00),
                        .init(color: .white.opacity(0.22), location: 0.15),
                        .init(color: .clear, location: 0.28),
                        .init(color: .clear, location: 0.52),
                        .init(color: .white.opacity(0.14), location: 0.66),
                        .init(color: .clear, location: 0.82),
                        .init(color: .clear, location: 1.00)
                    ]),
                    center: .center,
                    angle: .degrees(35)
                ))
                .frame(width: size - 2, height: size - 2)
                .blendMode(.screen)
                .allowsHitTesting(false)
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(white: 0.18), Color(white: 0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: labelSize + 6, height: labelSize + 6)
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                Group {
                    if coverURL != nil {
                        CoverImage(url: coverURL, size: labelSize, cornerRadius: labelSize / 2, emptyHint: nil)
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [Color(white: 0.22), Color(white: 0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "music.note")
                                .font(.system(size: labelSize * 0.35, weight: .light))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }
                .frame(width: labelSize, height: labelSize)
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(.black.opacity(0.45), lineWidth: 1.5) }
                Circle()
                    .stroke(.white.opacity(0.26), lineWidth: 0.8)
                    .frame(width: labelSize * 0.86, height: labelSize * 0.86)
                Circle()
                    .fill(LinearGradient(
                        colors: [.white.opacity(0.95), .white.opacity(0.45), .black.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: spindleSize * 2.4, height: spindleSize * 2.4)
                Circle()
                    .fill(Color(white: 0.04))
                    .frame(width: spindleSize, height: spindleSize)
            }
        }
        .frame(width: size + 8, height: size + 8)
    }
}

private struct RecordModeTonearmView: View {
    let isPlaying: Bool
    let height: CGFloat
    let reduceMotion: Bool

    var body: some View {
        let width = height * 0.58
        let pivotSize = width * 0.46
        ZStack(alignment: .top) {
            Circle()
                .fill(LinearGradient(
                    colors: [Color(white: 0.9), Color(white: 0.28), Color(white: 0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: pivotSize, height: pivotSize)
                .overlay {
                    Circle()
                        .fill(Color(white: 0.12))
                        .padding(pivotSize * 0.19)
                }
                .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
                .zIndex(2)
            RecordModeTonearmPath()
                .stroke(Color.black.opacity(0.36), lineWidth: max(5, width * 0.09))
                .blur(radius: 2)
                .offset(x: 2, y: 3)
            RecordModeTonearmPath()
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.96), .white.opacity(0.52), .white.opacity(0.90), .white.opacity(0.38)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(
                        lineWidth: max(3.5, width * 0.058),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .rotationEffect(
                    .degrees(isPlaying ? 0 : -32),
                    anchor: UnitPoint(x: 0.5, y: pivotSize * 0.5 / height)
                )
                .animation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.74), value: isPlaying)
                .zIndex(1)
        }
        .frame(width: width, height: height, alignment: .top)
    }
}

private struct RecordModeTonearmPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.width * 0.5, y: 0)
        let first = CGPoint(x: rect.width * 0.58, y: rect.height * 0.28)
        let second = CGPoint(x: rect.width * 0.42, y: rect.height * 0.55)
        let end = CGPoint(x: rect.width * 0.31, y: rect.height * 0.74)
        path.move(to: start)
        path.addCurve(
            to: first,
            control1: CGPoint(x: rect.width * 0.52, y: rect.height * 0.1),
            control2: CGPoint(x: rect.width * 0.58, y: rect.height * 0.2)
        )
        path.addCurve(
            to: second,
            control1: CGPoint(x: rect.width * 0.58, y: rect.height * 0.38),
            control2: CGPoint(x: rect.width * 0.45, y: rect.height * 0.48)
        )
        path.addCurve(
            to: end,
            control1: CGPoint(x: rect.width * 0.38, y: rect.height * 0.62),
            control2: CGPoint(x: rect.width * 0.33, y: rect.height * 0.70)
        )
        return path
    }
}

private struct RecordModeRotationState: Equatable, Sendable {
    let degreesPerSecond: Double
    private(set) var isAnimating = false
    private var baseAngle = 0.0
    private var startedAt = Date(timeIntervalSinceReferenceDate: 0)
    private var stoppedAngle = 0.0

    init(degreesPerSecond: Double = 24) {
        self.degreesPerSecond = degreesPerSecond
    }

    mutating func start(at date: Date = Date()) {
        guard !isAnimating else { return }
        baseAngle = stoppedAngle
        startedAt = date
        isAnimating = true
    }

    mutating func stop(at date: Date = Date()) {
        guard isAnimating else { return }
        stoppedAngle = currentAngle(at: date)
        isAnimating = false
    }

    func currentAngle(at date: Date) -> Double {
        guard isAnimating else { return stoppedAngle }
        return baseAngle + max(0, date.timeIntervalSince(startedAt)) * degreesPerSecond
    }
}
