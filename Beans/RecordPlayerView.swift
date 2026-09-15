import SwiftUI

/// The dedicated record mode keeps the turntable mode separate from the
/// existing vinyl player while following the reference player's mobile flow:
/// artwork, metadata, lyrics, queue, scrubber, and transport controls share
/// one screen and replace each other in place.
struct RecordPlayerView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var clock: PlaybackClock
    @Environment(\.colorScheme) private var colorScheme

    let song: Song?
    let lyrics: [LyricLine]
    @Binding var isPresented: Bool
    let onFavorite: () -> Void
    let onComments: () -> Void
    let onMore: () -> Void
    let onSettings: () -> Void

    @State private var showsLyrics = false
    @State private var showsQueue = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CoverBlurBackground(url: song?.coverURL, scheme: colorScheme)
                    .ignoresSafeArea()
                LinearGradient(
                    colors: [.black.opacity(0.20), .clear, .black.opacity(0.48)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if showsQueue {
                    queuePage
                        .transition(.opacity)
                } else if showsLyrics {
                    lyricsPage
                        .transition(.opacity)
                } else {
                    mainPage(size: geo.size)
                        .transition(.opacity)
                }

                topBar
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .simultaneousGesture(commentGesture)
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.22), value: showsLyrics)
        .animation(.easeInOut(duration: 0.22), value: showsQueue)
    }

    private var topBar: some View {
        VStack {
            HStack(spacing: 12) {
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("关闭播放器")

                Spacer()

                if let song {
                    Button(action: onFavorite) {
                        Image(systemName: "heart")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 40, height: 40)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                    .accessibilityLabel("收藏")

                    Button(action: onMore) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 40, height: 40)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                    .accessibilityLabel("更多操作")
                    .disabled(song.identityKey.isEmpty)
                }
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 20)
            .padding(.top, 12)
            Spacer()
        }
        .allowsHitTesting(true)
    }

    private func mainPage(size: CGSize) -> some View {
        let artworkSize = min(size.width - 72, size.height * 0.42, 310)
        return VStack(spacing: 0) {
            Spacer(minLength: 54)

            VinylTurntableView(
                coverURL: song?.coverURL,
                isPlaying: player.isPlaying,
                trackId: song?.id,
                size: artworkSize,
                onTap: { showsLyrics = true },
                onNextTrack: player.next,
                onPreviousTrack: player.previous
            )
            .frame(maxWidth: .infinity)

            recordMetadata
                .padding(.top, 10)

            recordMiniLyrics
                .frame(maxWidth: 420, maxHeight: .infinity)
                .padding(.top, 10)

            recordControls
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
        }
        .padding(.horizontal, 16)
    }

    private var recordMetadata: some View {
        VStack(spacing: 5) {
            Text(song?.name ?? "未在播放")
                .font(BeansFont.appFont(21, .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(song.map { "\($0.artists) — \($0.album)" } ?? "")
                .font(BeansFont.appFont(13.5, .regular))
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(1)
            HStack(spacing: 8) {
                Button {
                    onComments()
                } label: {
                    Label("评论", systemImage: "text.bubble")
                        .font(BeansFont.appFont(12, .semibold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 38)
                        .background(.white.opacity(0.12), in: Capsule())
                }
                Button {
                    onSettings()
                } label: {
                    Label("设置", systemImage: "slider.horizontal.3")
                        .font(BeansFont.appFont(12, .semibold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 38)
                        .background(.white.opacity(0.12), in: Capsule())
                }
            }
            .foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: 420)
    }

    private var recordMiniLyrics: some View {
        Button {
            showsLyrics = true
        } label: {
            VStack(spacing: 8) {
                if lyrics.isEmpty {
                    Text("暂无歌词")
                        .font(BeansFont.appFont(15, .semibold))
                        .foregroundStyle(.white.opacity(0.52))
                } else {
                    ForEach(Array(visibleLyricRows.enumerated()), id: \.offset) { item in
                        Text(item.element.text.isEmpty ? " " : item.element.text)
                            .font(BeansFont.appFont(item.offset == 1 ? 17 : 15, item.offset == 1 ? .semibold : .medium))
                            .foregroundStyle(.white.opacity(item.offset == 1 ? 0.88 : 0.5))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var visibleLyricRows: [LyricLine] {
        guard !lyrics.isEmpty else { return [] }
        let progress = clock.progress
        let current = lyrics.lastIndex(where: { $0.time <= progress }) ?? 0
        let start = max(0, min(current - 1, max(lyrics.count - 3, 0)))
        return Array(lyrics[start..<min(start + 3, lyrics.count)])
    }

    private var recordControls: some View {
        VStack(spacing: 12) {
            ReferenceScrubber()
            HStack(spacing: 0) {
                recordButton(icon: player.playMode.icon, active: player.playMode == .shuffle) {
                    player.togglePlayMode()
                }
                recordButton(icon: "backward.fill") { player.previous() }
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.black.opacity(0.86))
                        .frame(width: 58, height: 58)
                        .background(.white, in: Circle())
                        .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
                }
                .frame(maxWidth: .infinity)
                recordButton(icon: "forward.fill") { player.next() }
                recordButton(icon: showsQueue ? "xmark" : "list.bullet", active: showsQueue) {
                    showsQueue.toggle()
                }
            }
        }
        .foregroundStyle(.white)
    }

    private func recordButton(icon: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(active ? .white : .white.opacity(0.82))
                .frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(.plain)
    }

    private var lyricsPage: some View {
        VStack(spacing: 0) {
            recordPageHeader(title: "歌词") {
                showsLyrics = false
            }
            AppleMusicLyricsSection(
                lyrics: lyrics,
                primary: .white,
                secondary: .white.opacity(0.58),
                lyricOffset: 0
            ) { line in
                player.seekPrecisely(to: LyricTiming.seekTime(for: line, userOffset: 0))
            }
            .padding(.horizontal, 14)
            recordControls
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
        }
        .padding(.top, 62)
    }

    private var queuePage: some View {
        VStack(spacing: 0) {
            recordPageHeader(title: "播放列表") {
                showsQueue = false
            }
            AppleMusicCompactQueueContent()
                .padding(.horizontal, 20)
            recordControls
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
        }
        .padding(.top, 62)
    }

    private func recordPageHeader(title: String, onBack: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.12), in: Circle())
            }
            Text(title)
                .font(BeansFont.appFont(18, .bold))
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private var commentGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard value.translation.height < -54,
                      abs(value.translation.height) > abs(value.translation.width),
                      song != nil else { return }
                onComments()
            }
    }
}
