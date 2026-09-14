import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BeansNavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("播放队列").font(BeansFont.appFont(18, .semibold)).foregroundStyle(Color.beansLabel)
                        Text("共 \(player.queue.count) 首歌曲").font(BeansFont.appFont(12)).foregroundStyle(Color.beansComment)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.beansComment).frame(width: 28, height: 28)
                            .background(Color.beansLabel.opacity(0.08), in: Circle())
                    }.buttonStyle(GlassPressButtonStyle(scale: 0.92))
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                Divider().opacity(0.3)
                content
            }
            .frame(maxWidth: 340, maxHeight: .infinity)
            .background { background }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.beansLabel.opacity(0.06), lineWidth: 0.5) }
        }
        .modifier(BeansSheetModifier(detents: [.medium, .large], dragIndicator: false))
        .modifier(QueueSheetPresentation())
    }

    @ViewBuilder private var content: some View {
        if player.queue.isEmpty {
            EmptyStateView(icon: "list.bullet", text: "播放队列为空").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    section("正在播放")
                    if player.queue.indices.contains(player.currentIndex) { row(player.queue[player.currentIndex], index: player.currentIndex, current: true) }
                    if !upcoming.isEmpty {
                        section("即将播放").padding(.top, 10)
                        ForEach(upcoming, id: \.index) { item in row(item.song, index: item.index, current: false) }
                    }
                }.padding(10).padding(.bottom, 20)
            }
        }
    }

    private var upcoming: [(index: Int, song: Song)] {
        player.queue.enumerated().compactMap { index, song in index == player.currentIndex ? nil : (index, song) }
    }

    private func section(_ title: String) -> some View {
        Text(title).font(BeansFont.appFont(11, .semibold)).foregroundStyle(Color.beansComment).padding(.horizontal, 8).padding(.vertical, 5)
    }

    private func row(_ song: Song, index: Int, current: Bool) -> some View {
        Button { player.playQueueIndex(index) } label: {
            HStack(spacing: 10) {
                CoverImage(url: song.coverURL, size: 38, cornerRadius: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.name).font(BeansFont.appFont(13, current ? .semibold : .medium)).foregroundStyle(current ? Color.beansAmber : Color.beansLabel).lineLimit(1)
                    Text(song.artists).font(BeansFont.appFont(11)).foregroundStyle(Color.beansComment).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if current { Image(systemName: player.isPlaying ? "waveform" : "pause.fill").foregroundStyle(Color.beansAmber) }
                else { Text(song.formattedDuration).font(BeansFont.appFont(10, .regular, .monospaced)).foregroundStyle(Color.beansComment) }
            }.padding(.horizontal, 8).padding(.vertical, 5).contentShape(Rectangle())
        }.buttonStyle(.plain).contextMenu {
            Button(role: .destructive) { player.removeFromQueue(at: index) } label: { Label("移除", systemImage: "trash") }
        }
    }

    @ViewBuilder private var background: some View {
        if #available(iOS 15.0, *) {
            Rectangle().fill(.regularMaterial)
        }
        if let url = player.currentSong?.coverURL {
            CoverBlurBackground(url: url, scheme: colorScheme).opacity(0.18)
        } else {
            GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil).opacity(0.35)
        }
        Color.black.opacity(colorScheme == .dark ? 0.18 : 0.03)
    }
}

private struct QueueSheetPresentation: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) { content.presentationBackground(.clear).presentationCornerRadius(28) } else { content }
    }
}
