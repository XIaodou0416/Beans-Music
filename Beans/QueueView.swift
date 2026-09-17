import SwiftUI

/// 播放列表以播放器面板的形式呈现：当前歌曲、播放模式和队列保持在同一张半屏面板内。
struct QueueView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let _ = theme.accent
        BeansNavigationStack {
            ZStack {
                if let coverURL = player.currentSong?.coverURL {
                    CoverBlurBackground(url: coverURL, scheme: colorScheme)
                } else {
                    GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                }
                Color.black.opacity(colorScheme == .dark ? 0.26 : 0.10)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        queueHeader
                        modeControls
                        queueList
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 150)
                }
            }
            .navigationTitle("播放列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            player.clearQueue()
                        } label: {
                            Label("清空队列", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                transportControls
            }
        }
        .modifier(BeansSheetModifier(detents: [.medium, .large], dragIndicator: true))
        .modifier(QueueSheetPresentation())
    }

    private var queueHeader: some View {
        HStack(spacing: 16) {
            CoverImage(url: player.currentSong?.coverURL, song: player.currentSong, size: 82, cornerRadius: 16)
                .shadow(color: .black.opacity(0.28), radius: 16, y: 8)

            VStack(alignment: .leading, spacing: 5) {
                Text(player.currentSong?.name ?? "未在播放")
                    .font(BeansFont.appFont(24, .bold))
                    .foregroundStyle(Color.beansLabel)
                    .lineLimit(1)
                Text(player.currentSong?.artists ?? "暂无歌曲")
                    .font(BeansFont.appFont(15, .medium))
                    .foregroundStyle(Color.beansComment)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modeControls: some View {
        HStack(spacing: 10) {
            modeButton(icon: "arrow.right", title: "顺序", active: player.playMode == .sequential) {
                player.setPlayMode(.sequential)
            }
            modeButton(icon: "repeat", title: "列表循环", active: player.playMode == .repeatAll) {
                player.setPlayMode(.repeatAll)
            }
            modeButton(icon: "shuffle", title: "随机", active: player.playMode == .shuffle) {
                player.setPlayMode(.shuffle)
            }
            modeButton(icon: "repeat.1", title: "单曲", active: player.playMode == .repeatOne) {
                player.setPlayMode(.repeatOne)
            }
        }
    }

    private func modeButton(icon: String, title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(BeansFont.appFont(11, .medium))
            }
            .foregroundStyle(active ? Color.beansAmber : Color.beansLabel.opacity(0.76))
            .frame(maxWidth: .infinity, minHeight: 58)
            .background {
                BeansGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous), forceLiquid: true)
            }
            .overlay {
                if active {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.beansAmber.opacity(0.42), lineWidth: 1)
                }
            }
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.96))
    }

    private var queueList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("继续播放")
                    .font(BeansFont.appFont(23, .bold))
                    .foregroundStyle(Color.beansLabel)
                Spacer()
                Text("\(player.queue.count) 首")
                    .font(BeansFont.appFont(13, .medium))
                    .foregroundStyle(Color.beansComment)
            }

            if player.queue.isEmpty {
                EmptyStateView(icon: "music.note.list", text: "播放队列为空")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(Array(player.queue.enumerated()), id: \.element.identityKey) { index, song in
                        row(song, index: index)
                    }
                }
            }
        }
    }

    private func row(_ song: Song, index: Int) -> some View {
        let isCurrent = index == player.currentIndex
        return Button {
            guard player.queue.indices.contains(index) else { return }
            player.playQueueIndex(index)
        } label: {
            HStack(spacing: 12) {
                CoverImage(url: song.coverURL, song: song, size: 48, cornerRadius: 12)
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.name)
                        .font(BeansFont.appFont(15, isCurrent ? .semibold : .medium))
                        .foregroundStyle(isCurrent ? Color.beansAmber : Color.beansLabel)
                        .lineLimit(1)
                    Text(song.artists)
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isCurrent {
                    Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                        .foregroundStyle(Color.beansAmber)
                } else {
                    Text(song.formattedDuration)
                        .font(BeansFont.appFont(12, .regular, .monospaced))
                        .foregroundStyle(Color.beansComment)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                BeansGlass(shape: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.985))
        .contextMenu {
            Button(role: .destructive) {
                player.removeFromQueue(at: index)
            } label: {
                Label("移除", systemImage: "trash")
            }
        }
    }

    private var transportControls: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let total = max(player.duration, player.currentSong?.duration ?? 1)
                let fraction = min(max(player.progress / total, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.beansComment.opacity(0.22)).frame(height: 4)
                    Capsule().fill(Color.beansAmber).frame(width: geometry.size.width * fraction, height: 4)
                }
            }
            .frame(height: 10)

            HStack {
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill")
                }
                .buttonStyle(.plain)
                Spacer()
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                }
                .buttonStyle(.plain)
                Spacer()
                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Color.beansLabel)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background {
            BeansGlass(shape: RoundedRectangle(cornerRadius: 24, style: .continuous), forceLiquid: true)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }
}

private struct QueueSheetPresentation: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content
                .presentationBackground(.clear)
                .presentationCornerRadius(28)
        } else {
            content
        }
    }
}
