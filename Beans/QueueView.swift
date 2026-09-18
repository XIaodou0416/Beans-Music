import SwiftUI

/// 经典播放器使用的原始播放队列列表。
struct QueueView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @AppStorage("beans.queueOverlayPresented") private var queueOverlayPresented = false

    var body: some View {
        let _ = theme.accent
        BeansNavigationStack {
            Group {
                if player.queue.isEmpty {
                    EmptyStateView(icon: "music.note.list", text: "播放队列为空")
                } else {
                    List {
                        Section("接下来 (\(player.queue.count) 首)") {
                            ForEach(Array(player.queue.enumerated()), id: \.element.identityKey) { index, song in
                                row(song, index: index)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                            .onDelete { offsets in
                                for index in offsets.sorted(by: >) where player.queue.indices.contains(index) {
                                    player.removeFromQueue(at: index)
                                }
                            }
                        }
                    }
                    .beansScrollContentBackgroundHidden()
                    .listStyle(.plain)
                    .background(LinearGradient.beansBackdrop)
                }
            }
            .navigationTitle("播放队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            player.clearQueue()
                        } label: {
                            Label("清空队列", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear { queueOverlayPresented = true }
        .onDisappear { queueOverlayPresented = false }
    }

    private func row(_ song: Song, index: Int) -> some View {
        let isCurrent = index == player.currentIndex
        return Button {
            guard player.queue.indices.contains(index) else { return }
            player.playQueueIndex(index)
        } label: {
            HStack(spacing: 12) {
                CoverImage(url: song.coverURL, song: song, size: 42, cornerRadius: 9)
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.name)
                        .font(BeansFont.appFont(15, isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? Color.beansAmber : Color.beansLabel)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(song.artists)
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                if isCurrent {
                    if player.isPlaying {
                        NowPlayingIndicator()
                    } else {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.beansAmber)
                    }
                } else {
                    Text(song.formattedDuration)
                        .font(BeansFont.appFont(12, .regular, .monospaced))
                        .foregroundStyle(Color.beansComment)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background {
                BeansGlass(shape: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
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
}
