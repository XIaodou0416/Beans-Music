import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var clock: PlaybackClock
    @Binding var showPlayer: Bool
    @State private var miniLyrics: [LyricLine] = []
    @AppStorage("beans.lyricOffset") private var lyricOffset = 0.0
    @AppStorage("beans.uiStyle") private var uiStyleRaw = BeansUIStyle.liquid.rawValue

    private var isNativeClean: Bool {
        BeansUIStyle(rawValue: uiStyleRaw) == .nativeClean
    }

    private var coverSize: CGFloat { isNativeClean ? 36 : 40 }
    private var controlSize: CGFloat { isNativeClean ? 32 : 38 }
    private var containerRadius: CGFloat { isNativeClean ? 18 : 22 }
    private var verticalPadding: CGFloat { isNativeClean ? 4 : 8 }

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
                        .frame(width: isNativeClean ? 42 : 48, height: isNativeClean ? 42 : 48)
                        .blur(radius: 9)
                    CoverImage(url: player.currentSong?.coverURL, size: coverSize, cornerRadius: 7)
                }
                .frame(width: isNativeClean ? 42 : 48, height: isNativeClean ? 42 : 48)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(player.currentSong?.name ?? "")
                            .font(BeansFont.appFont(isNativeClean ? 12 : 14, .semibold))
                            .foregroundStyle(Color.beansLabel)
                            .lineLimit(1)
                        if player.currentSong?.isVIP == true {
                            Text("VIP")
                                .font(BeansFont.appFont(8, .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Color(red: 0.93, green: 0.25, blue: 0.22)))
                        }
                    }
                    Text(currentLyricLine?.text ?? player.currentSong?.artists ?? "")
                        .font(BeansFont.appFont(isNativeClean ? 10 : 12))
                        .foregroundStyle(Color.beansComment)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .animation(.easeInOut(duration: 0.25), value: currentLyricLine?.text)
                }
                Spacer(minLength: 8)
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
                // Apple 简洁样式也强制使用液态播放器底板，低系统自动回退为材质模拟。
                BeansGlass(
                    shape: RoundedRectangle(cornerRadius: containerRadius, style: .continuous),
                    forceLiquid: isNativeClean
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
            }
            .overlay(alignment: .bottom) {
                ProgressLine(progress: clock.progress, duration: clock.duration)
                    .frame(height: 2.5)
                    .padding(.horizontal, 12)
            }
            .clipShape(RoundedRectangle(cornerRadius: containerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
            .scaleEffect(showPlayer ? 0.985 : 1)
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: showPlayer)
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
        .padding(.horizontal, 12)
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
