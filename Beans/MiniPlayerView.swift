import SwiftUI

/// 底部播放器：信息区、播放控制和上划展开手势保持同一交互层，
/// 避免外层 Button 抢走拖动事件。
struct MiniPlayerView: View {
    enum Presentation {
        case dock
        case accessory
        case inlineAccessory

        var isInline: Bool { self == .inlineAccessory }
        var drawsBackground: Bool { self == .dock }
    }

    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var clock: PlaybackClock
    @Binding var showPlayer: Bool
    var presentation: Presentation = .dock
    var transitionNamespace: Namespace.ID?
    @State private var miniLyrics: [LyricLine] = []
    @AppStorage("beans.lyricOffset") private var lyricOffset = 0.0

    private var currentLyricLine: LyricLine? {
        guard !miniLyrics.isEmpty else { return nil }
        let progress = LyricTiming.effectiveProgress(clock.progress, userOffset: lyricOffset)
        var low = 0
        var high = miniLyrics.count - 1
        var answer: LyricLine?
        while low <= high {
            let middle = (low + high) / 2
            if miniLyrics[middle].time <= progress {
                answer = miniLyrics[middle]
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return answer
    }

    var body: some View {
        playerBarSurface
            .simultaneousGesture(expandGesture)
            .transitionSource(in: transitionNamespace)
            .task(id: player.currentSong?.identityKey) {
                await loadMiniLyrics()
            }
    }

    @ViewBuilder
    private var playerBarSurface: some View {
        if presentation.drawsBackground {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 4) {
            Button(action: showNowPlaying) {
                trackSummary
            }
            .buttonStyle(.plain)
            .accessibilityLabel(nowPlayingAccessibilityLabel)
            .accessibilityHint("打开正在播放")

            if !presentation.isInline {
                PlayerTransportButton(icon: "backward.fill", label: "上一首") {
                    player.previous()
                }
            }

            PlayerTransportButton(
                icon: player.isPlaying ? "pause.fill" : "play.fill",
                label: player.isPlaying ? "暂停" : "播放",
                weight: .bold
            ) {
                player.togglePlayPause()
            }

            if !presentation.isInline {
                PlayerTransportButton(icon: "forward.fill", label: "下一首") {
                    player.next()
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
    }

    private var trackSummary: some View {
        HStack(alignment: .top, spacing: 8) {
            CoverImage(
                url: player.currentSong?.coverURL,
                size: presentation.isInline ? 28 : 32,
                cornerRadius: 7
            )
            .shadow(color: .black.opacity(0.15), radius: 4, y: 1)

            VStack(alignment: .leading, spacing: presentation.isInline ? 2 : 3) {
                Text(player.currentSong?.name ?? "")
                    .font(.system(size: presentation.isInline ? 10 : 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(currentLyricLine?.text ?? player.currentSong?.artists ?? "")
                    .font(.system(size: presentation.isInline ? 8 : 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .animation(.easeInOut(duration: 0.25), value: currentLyricLine?.text)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nowPlayingAccessibilityLabel: String {
        let title = player.currentSong?.name ?? String(localized: "正在播放")
        guard let artist = player.currentSong?.artists, !artist.isEmpty else {
            return title
        }
        return "\(title)，\(artist)"
    }

    private var expandGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onEnded { value in
                let translation = value.translation.height
                let prediction = value.predictedEndTranslation.height
                guard translation < -50 || prediction < -100 else { return }
                showNowPlaying()
            }
    }

    private func showNowPlaying() {
        BeansHaptics.tap()
        showPlayer = true
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
        guard !Task.isCancelled, let raw else { return }
        guard player.currentSong?.identityKey == identity else { return }
        miniLyrics = LyricParser.parse(raw)
    }
}

private struct PlayerTransportButton: View {
    let icon: String
    let label: String
    var weight: Font.Weight = .semibold
    let action: () -> Void

    var body: some View {
        Button {
            BeansHaptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: weight))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle())
        .accessibilityLabel(label)
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
