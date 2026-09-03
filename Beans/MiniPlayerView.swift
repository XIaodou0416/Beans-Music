import SwiftUI

struct MiniPlayerView: View {
    enum Presentation {
        case dock
        case accessory

        var showsCardSurface: Bool { self == .dock }
    }

    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var clock: PlaybackClock
    @Binding var showPlayer: Bool
    var presentation: Presentation = .dock
    var transitionNamespace: Namespace.ID?
    @State private var miniLyrics: [LyricLine] = []
    @AppStorage("beans.lyricOffset") private var lyricOffset = 0.0
    @AppStorage("beans.uiStyle") private var uiStyleRaw = BeansUIStyle.liquid.rawValue
    @AppStorage("beans.showSongVIPBadge") private var showSongVIPBadge = true

    private var coverSize: CGFloat { 36 }
    private var controlSize: CGFloat { 32 }
    private var containerRadius: CGFloat { 18 }
    private var verticalPadding: CGFloat { 4 }

    /// 二分查找当前播放到的歌词行（歌词按时间升序）
    private var currentLyricLine: LyricLine? {
        guard !miniLyrics.isEmpty else { return nil }
        var low = 0
        var high = miniLyrics.count - 1
        var answer: LyricLine?
        while low <= high {
            let mid = (low + high) / 2
            if miniLyrics[mid].time <= LyricTiming.effectiveProgress(clock.progress, userOffset: lyricOffset) {
                answer = miniLyrics[mid]
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return answer
    }

    var body: some View {
        let _ = theme.accent
        Button {
            BeansHaptics.tap()
            showPlayer = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(theme.accent.highlight.opacity(0.32))
                        .frame(width: 42, height: 42)
                        .blur(radius: 9)
                    CoverImage(url: player.currentSong?.coverURL, size: coverSize, cornerRadius: 7)
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(player.currentSong?.name ?? "")
                            .font(BeansFont.appFont(12, .semibold))
                            .foregroundStyle(Color.beansLabel)
                            .lineLimit(1)
                        if showSongVIPBadge, player.currentSong?.isVIP == true {
                            Text("VIP")
                                .font(BeansFont.appFont(8, .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Color(red: 0.93, green: 0.25, blue: 0.22)))
                        }
                    }
                    Text(currentLyricLine?.text ?? player.currentSong?.artists ?? "")
                        .font(BeansFont.appFont(10))
                        .foregroundStyle(Color.beansComment)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .animation(.easeInOut(duration: 0.25), value: currentLyricLine?.text)
                }
                Spacer(minLength: 8)
                Button {
                    BeansHaptics.tap()
                    player.previous()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.beansLabel)
                        .frame(width: controlSize, height: controlSize)
                        .contentShape(Circle())
                }
                .buttonStyle(GlassPressButtonStyle())
                Button {
                    BeansHaptics.tap()
                    player.togglePlayPause()
                } label: {
                    PlayPauseMorphIcon(isPlaying: player.isPlaying, size: 16)
                        .foregroundStyle(Color.beansLabel)
                        .frame(width: controlSize, height: controlSize)
                        .contentShape(Circle())
                }
                .buttonStyle(GlassPressButtonStyle())
                Button {
                    BeansHaptics.tap()
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.beansLabel)
                        .frame(width: controlSize, height: controlSize)
                        .contentShape(Circle())
                }
                .buttonStyle(GlassPressButtonStyle())
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, verticalPadding)
            .background {
                if presentation.showsCardSurface {
                    // 普通底部浮层：保留卡片质感与阴影。
                    BeansGlass(
                        shape: RoundedRectangle(cornerRadius: containerRadius, style: .continuous),
                        forceLiquid: false
                    )
                    .overlay {
                        LinearGradient(
                            colors: [.white.opacity(0.25), .clear, .white.opacity(0.05)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: containerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.45), .white.opacity(0.08)],
                                    startPoint: .top, endPoint: .bottom
                                ),
                                lineWidth: 0.8
                            )
                    }
                } else {
                    // 进入底栏 accessory 时不再叠一层卡片，交给系统/底栏容器去承载。
                    RoundedRectangle(cornerRadius: containerRadius, style: .continuous)
                        .fill(.clear)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: containerRadius, style: .continuous))
            .shadow(color: presentation.showsCardSurface ? .black.opacity(0.16) : .clear, radius: 12, y: 6)
            .scaleEffect(showPlayer ? 0.985 : 1)
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: showPlayer)
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
        .transitionSource(in: transitionNamespace)
        .padding(.horizontal, presentation.showsCardSurface ? 12 : 0)
        .task(id: player.currentSong?.identityKey) {
            await loadMiniLyrics()
        }
    }

    private func loadMiniLyrics() async {
        miniLyrics = []
        guard let song = player.currentSong else { return }
        let identity = song.identityKey
        var raw: String?
        if song.source == .kugou, let hash = song.kugouHash {
            raw = await KugouMusicAPI.shared.lyric(hash: hash, duration: song.duration)
        } else if song.source == .qq, let mid = song.qqMid {
            raw = try? await QQMusicAPI.shared.lyric(songmid: mid)
        } else {
            raw = try? await NetEaseAPI.shared.lyric(id: song.id)
        }
        guard let raw else { return }
        guard player.currentSong?.identityKey == identity else { return }
        miniLyrics = LyricParser.parse(raw)
    }
}

enum BeansNowPlayingTransitionID {
    static let surface = "beans-now-playing-surface"
}

private struct BeansTransitionSourceModifier: ViewModifier {
    let namespace: Namespace.ID?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace, #available(iOS 18.0, *) {
            content.matchedTransitionSource(
                id: BeansNowPlayingTransitionID.surface,
                in: namespace
            )
        } else {
            content
        }
    }
}

private extension View {
    @ViewBuilder
    func transitionSource(in namespace: Namespace.ID?) -> some View {
        modifier(BeansTransitionSourceModifier(namespace: namespace))
    }
}
